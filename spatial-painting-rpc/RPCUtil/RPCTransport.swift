//
//  RPCTransport.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2026/09/18.
//

import Foundation
import Synchronization

/// RPC リクエストの送受信を担うクラス
///
/// エンコード・デコード、ログの記録、再送キュー、ack の処理を MainActor の外で行う。
/// - 送信: `send(_:to:)` を呼んだ順番に、1本の直列ストリームでエンコードしてネットワークに渡す
/// - 受信: 受け取った順番にデコードし、ack 以外を `requests` に流す
final class RPCTransport: Sendable {
    /// 送信待ちのリクエスト
    private struct Outgoing: Sendable {
        let request: RequestSchema
        let destination: RPCDestination
        let direction: RPCLogDirection
        /// ack を待って再送する対象かどうか
        let tracksAcknowledgment: Bool
    }

    /// 自身の Peer の id
    let localPeerId: UUID
    /// 自身の Peer の hash
    let localPeerHash: Int

    /// デコード済みの受信リクエスト（ack は除く）。受信した順番に流れる
    let requests: AsyncStream<RequestSchema>
    private let requestsContinuation: AsyncStream<RequestSchema>.Continuation

    private let outgoingContinuation: AsyncStream<Outgoing>.Continuation
    private let incomingContinuation: AsyncStream<Data>.Continuation

    /// 接続中のネットワーク（未接続なら nil）
    private let network = Mutex<NetworkTopologyManager?>(nil)
    /// 接続中の Peer（hash → UUID）
    private let connectedPeers = Mutex<[Int: UUID]>([:])

    /// リクエストキュー（再送管理用）
    let requestQueue: RequestQueue
    /// 送受信した RPC リクエストのロガー
    private let logger = RPCLogger()

    init(localPeerId: UUID, requestQueue: RequestQueue = RequestQueue()) {
        self.localPeerId = localPeerId
        self.localPeerHash = MCPeerIDUUIDWrapper.stableHash(for: localPeerId)
        self.requestQueue = requestQueue

        (requests, requestsContinuation) = AsyncStream.makeStream(of: RequestSchema.self)
        let (outgoing, outgoingContinuation) = AsyncStream.makeStream(of: Outgoing.self)
        let (incoming, incomingContinuation) = AsyncStream.makeStream(of: Data.self)
        self.outgoingContinuation = outgoingContinuation
        self.incomingContinuation = incomingContinuation

        Task.detached { [weak self] in
            for await item in outgoing {
                guard let self else { return }
                await self.deliver(item)
            }
        }

        Task.detached { [weak self] in
            for await data in incoming {
                guard let self else { return }
                self.handleIncoming(data)
            }
        }

        Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.retryTimedOutRequests()
            }
        }
    }

    deinit {
        outgoingContinuation.finish()
        incomingContinuation.finish()
        requestsContinuation.finish()
    }

    // MARK: - ネットワークとの接続

    /// ネットワークを接続する
    func attach(_ network: NetworkTopologyManager) {
        self.network.withLock { $0 = network }
    }

    /// ネットワークを切断する
    func detach() {
        network.withLock { $0 = nil }
        connectedPeers.withLock { $0.removeAll() }
    }

    /// 接続中の Peer を更新する
    func updateConnectedPeers(_ peerIds: [UUID]) {
        let peers = Dictionary(peerIds.map { (MCPeerIDUUIDWrapper.stableHash(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        connectedPeers.withLock { $0 = peers }
    }

    /// ネットワークから受信したデータを渡す
    ///
    /// - Note: 受信した順番に処理するため、ネットワーク側から順番に呼び出すこと
    func receive(_ data: Data) {
        incomingContinuation.yield(data)
    }

    // MARK: - 送信

    /// RPC リクエストを送信する
    ///
    /// - Note: 呼び出した順番に送信される
    /// - Parameters:
    ///   - request: 送信するリクエスト
    ///   - destination: 送信先
    func send(_ request: RequestSchema, to destination: RPCDestination = .broadcast) {
        outgoingContinuation.yield(
            Outgoing(
                request: request,
                destination: destination,
                direction: .send,
                tracksAcknowledgment: !Self.shouldExcludeFromRetry(request.method)
            )
        )
    }

    /// Acknowledgment を送信
    /// - Parameters:
    ///     - requestId: 確認するリクエストの ID
    ///     - peerHash: 送信先の Peer の hash
    func sendAcknowledgment(requestId: UUID, to peerHash: Int) {
        let ackRequest = RequestSchema(
            peerId: localPeerHash,
            method: .ack,
            param: .ack(AckParam(requestId: requestId))
        )
        outgoingContinuation.yield(
            Outgoing(request: ackRequest, destination: .peer(peerHash), direction: .send, tracksAcknowledgment: false)
        )
    }

    /// エラーを送信
    /// - Parameters:
    ///     - message: エラーメッセージ
    ///     - peerHash: 送信先の Peer の hash
    func sendError(message: String, to peerHash: Int) {
        let errorRequest = RequestSchema(
            peerId: localPeerHash,
            method: .error,
            param: .error(ErrorParam(errorMessage: message))
        )
        outgoingContinuation.yield(
            Outgoing(request: errorRequest, destination: .peer(peerHash), direction: .send, tracksAcknowledgment: false)
        )
    }

    /// 受信側で ack を返す対象かどうか
    static func requiresAcknowledgment(_ method: Method) -> Bool {
        !shouldExcludeFromRetry(method)
    }

    /// 再送処理から除外するメソッドかどうかを判定
    ///
    /// 送信順序を必ず維持しなければいけないメソッドでは、再送処理はノイズになるため
    /// 再送処理の対象から除外されます。これらのメソッドは：
    /// - キューに追加されません
    /// - acknowledgment を送信しません
    /// - タイムアウトによる再送が行われません
    ///
    /// - Parameter method: チェックするメソッド
    /// - Returns: 除外する場合はtrue
    private static func shouldExcludeFromRetry(_ method: Method) -> Bool {
        switch method {
        case .paintingEntity(.addStrokePoint),
             .paintingEntity(.addBezierStrokePoints),
             .coordinateTransformEntity(.requestTransform):
            return true
        default:
            return false
        }
    }

    // MARK: - 内部処理

    /// エンコードしてネットワークに渡す
    private func deliver(_ item: Outgoing) async {
        guard let network = network.withLock({ $0 }) else {
            print("RPCTransport: network is not attached")
            return
        }

        let targetPeerId: UUID?
        let targetPeerHash: Int?
        switch item.destination {
        case .broadcast:
            targetPeerId = nil
            targetPeerHash = nil
        case .peer(let hash):
            guard let peerId = peerId(forHash: hash) else {
                print("RPCTransport: target peer not found for hash \(hash)")
                return
            }
            targetPeerId = peerId
            targetPeerHash = hash
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(item.request)
        } catch {
            print("RPCTransport: failed to encode request: \(error)")
            return
        }

        if item.tracksAcknowledgment {
            requestQueue.enqueue(item.request, destination: item.destination)
        }

        logger.log(
            direction: item.direction,
            request: item.request,
            from: localPeerHash,
            fromUUID: localPeerId,
            to: targetPeerHash,
            toUUID: targetPeerId
        )

        await network.send(data: data, to: targetPeerId)
    }

    /// デコードして ack を処理し、それ以外を `requests` に流す
    private func handleIncoming(_ data: Data) {
        let request: RequestSchema
        do {
            request = try JSONDecoder().decode(RequestSchema.self, from: data)
        } catch {
            print("RPCTransport: failed to decode request: \(error)")
            return
        }

        logger.log(
            direction: .receive,
            request: request,
            from: request.peerId,
            fromUUID: peerId(forHash: request.peerId),
            to: localPeerHash,
            toUUID: localPeerId
        )

        // acknowledgment を受信したら、対応するリクエストをキューから削除
        if case let .acknowledgment(.ack(param)) = request.param {
            requestQueue.dequeue(param.requestId)
            return
        }

        requestsContinuation.yield(request)
    }

    /// タイムアウトしたリクエストを再送する
    private func retryTimedOutRequests() {
        for queued in requestQueue.takeRequestsToRetry() {
            print("Retrying Request \(queued.request.id) (\(queued.retryCount)/\(queued.maxRetries)) \(queued.request.method)")
            outgoingContinuation.yield(
                Outgoing(request: queued.request, destination: queued.destination, direction: .resend, tracksAcknowledgment: false)
            )
        }
    }

    /// Peer の hash から UUID を取得する（自身を含む）
    private func peerId(forHash hash: Int) -> UUID? {
        if hash == localPeerHash {
            return localPeerId
        }
        return connectedPeers.withLock { $0[hash] }
    }
}
