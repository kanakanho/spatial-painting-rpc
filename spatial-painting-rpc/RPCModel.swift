//
//  Entities.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import Foundation
import simd
import Combine

/// PRC の Method として Entity を定義
enum Method: Codable, Sendable {
    case error(ErrorEntitiy.Method)
    case coordinateTransformEntity(CoordinateTransformEntity.Method)
    case paintingEntity(PaintingEntity.Method)
    case acknowledgment(AcknowledgmentEntity.Method)
}

/// PRC の Param として Entity を定義
enum Param: Codable, Sendable {
    case error(ErrorEntitiy.Param)
    case coordinateTransformEntity(CoordinateTransformEntity.Param)
    case paintingEntity(PaintingEntity.Param)
    case acknowledgment(AcknowledgmentEntity.Param)
    
    /// カスタムエンコード
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .error(let param):
            try container.encode(param, forKey: .error)
        case .coordinateTransformEntity(let param):
            try container.encode(param, forKey: .coordinateTransformEntity)
        case .paintingEntity(let param):
            try container.encode(param, forKey: .paintingEntity)
        case .acknowledgment(let param):
            try container.encode(param, forKey: .acknowledgment)
        }
    }
    
    /// カスタムデコード
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let param = try? container.decode(ErrorEntitiy.Param.self, forKey: .error) {
            self = .error(param)
        } else if let param = try? container.decode(CoordinateTransformEntity.Param.self, forKey: .coordinateTransformEntity) {
            self = .coordinateTransformEntity(param)
        } else if let param = try? container.decode(PaintingEntity.Param.self, forKey: .paintingEntity) {
            self = .paintingEntity(param)
        } else if let param = try? container.decode(AcknowledgmentEntity.Param.self, forKey: .acknowledgment) {
            self = .acknowledgment(param)
        } else {
            throw DecodingError.dataCorruptedError(forKey: CodingKeys.error, in: container, debugDescription: "Invalid parameter type")
        }
    }
    
    /// カスタムエンコード/デコードのための Key
    private enum CodingKeys: String, CodingKey {
        case error
        case coordinateTransformEntity
        case paintingEntity
        case acknowledgment
    }
}

/// 型安全な RequestSchema
struct RequestSchema: Codable, Sendable {
    /// 通信の一意な id
    let id: UUID
    /// 通信元の Peer の一意な id
    let peerId: Int
    /// RPC のメソッド
    let method: Method
    /// RPC のメソッドの引数
    let param: Param
    
    /// カスタムデコード
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.peerId = try container.decode(Int.self, forKey: .peerId)
        self.method = try container.decode(Method.self, forKey: .method)
        self.param = try container.decode(Param.self, forKey: .param)
    }
    
    init(id: UUID, peerId: Int, method: Method, param: Param) {
        self.id = id
        self.peerId = peerId
        self.method = method
        self.param = param
    }
    
    init(id: UUID, peerId: Int, method: CoordinateTransformEntity.Method, param: CoordinateTransformEntity.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .coordinateTransformEntity(method)
        self.param = .coordinateTransformEntity(param)
    }
    
    init(peerId: Int, method: CoordinateTransformEntity.Method, param: CoordinateTransformEntity.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .coordinateTransformEntity(method)
        self.param = .coordinateTransformEntity(param)
    }
    
    init(id: UUID, peerId: Int, method: ErrorEntitiy.Method, param: ErrorEntitiy.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .error(method)
        self.param = .error(param)
    }
    
    init(peerId: Int, method: ErrorEntitiy.Method, param: ErrorEntitiy.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .error(method)
        self.param = .error(param)
    }
    
    init(id: UUID, peerId: Int, method: PaintingEntity.Method, param: PaintingEntity.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .paintingEntity(method)
        self.param = .paintingEntity(param)
    }
    
    init(peerId: Int, method: PaintingEntity.Method, param: PaintingEntity.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .paintingEntity(method)
        self.param = .paintingEntity(param)
    }
    
    init(id: UUID, peerId: Int, method: AcknowledgmentEntity.Method, param: AcknowledgmentEntity.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .acknowledgment(method)
        self.param = .acknowledgment(param)
    }
    
    init(peerId: Int, method: AcknowledgmentEntity.Method, param: AcknowledgmentEntity.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .acknowledgment(method)
        self.param = .acknowledgment(param)
    }
    
    /// カスタムエンコード
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(peerId, forKey: .peerId)
        try container.encode(method, forKey: .method)
        try container.encode(param, forKey: .param)
    }
    
    /// カスタムエンコード/デコードのための Key
    private enum CodingKeys: String, CodingKey {
        case id
        case peerId
        case method
        case param
    }
}

/// RPC に関連するメソッドの共通の返り値
struct RPCResult: Sendable {
    /// 成功したかどうか
    let success: Bool
    /// エラーメッセージ
    let errorMessage: String
    
    /// 成功した場合
    init() {
        self.success = true
        self.errorMessage = ""
    }
    
    /// 失敗した場合
    init(_ errorMessage: String) {
        self.success = false
        self.errorMessage = errorMessage
    }
}

/// RPCを管理するクラス
/// このクラスの中で利用できるメソッドのみ、RPCでの呼び出しが可能
/// - Warning: このクラスの中以外のメソッドを呼び出すためにRPCを利用してはいけません
@MainActor
class RPCModel: ObservableObject {
    /// RPC リクエストの送受信（エンコード・デコード・再送・ack は MainActor の外で行う）
    let transport: RPCTransport

    /// Peer 情報 — AppModel のものを参照する
    let mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
    
    @Published var coordinateTransforms = CoordinateTransforms()
    @Published var painting = Painting()
    
    init(transport: RPCTransport, mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper) {
        self.transport = transport
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        
        // 受信したリクエストを受信した順番に実行する
        let requests = transport.requests
        Task { [weak self] in
            for await request in requests {
                guard let self else { return }
                _ = self.receiveRequest(request)
            }
        }
    }
    
    /// RPC の実行と RPC リクエストの送信
    ///
    /// - Note: このメソッドでは、全ての Peer と共通化して実行したいメソッドを呼び出します
    ///
    /// - Parameters: request: `RequestSchema`
    /// - Returns: `RPCResult`
    func sendRequest(_ request: RequestSchema) -> RPCResult {
//        print("sendRequest")
//        print("sendMethod: \(request.method)")
//        print("sendParam: \(request.param)")
        
        var rpcResult = RPCResult()
        switch (request.method, request.param) {
        case let (.coordinateTransformEntity(.requestTransform),.coordinateTransformEntity(.requestTransform(p))):
            rpcResult = coordinateTransforms.requestTransform(param: p)
        case let (.coordinateTransformEntity(.setTransform),.coordinateTransformEntity(.setTransform(p))):
            rpcResult = coordinateTransforms.setTransform(param: p)
        case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
            rpcResult = coordinateTransforms.setState(param: p)
        case let (.paintingEntity(.finishStroke),.paintingEntity(.finishStroke(p))):
            painting.finishStroke(param: p)
        case let
            (.paintingEntity(.setStrokeColor),.paintingEntity(.setStrokeColor(p))):
            painting.setStrokeColor(param: p)
        case (.paintingEntity(.removeAllStroke),.paintingEntity(.removeAllStroke(_))):
            painting.removeAllStroke()
        case let
            (.paintingEntity(.removeStroke),.paintingEntity(.removeStroke(p))):
            painting.removeStroke(param: p)
        case let (.paintingEntity(.changeFingerLineWidth),.paintingEntity(.changeFingerLineWidth(p))):
            painting.changeFingerLineWidth(param: p)
        case let (.paintingEntity(.finishControlPoint), .paintingEntity(.finishControlPoint(p))):
            painting.finishControlPoint(param: p)
        default:
            return RPCResult("Invalid request")
        }
        // リクエストを送信
        transport.send(request)
        return rpcResult
    }
    
    /// RPC の実行と RPC リクエストの送信
    ///
    /// - Note: このメソッドでは、全ての Peer と共通化して実行したいメソッドを呼び出します
    ///
    /// - Parameters:
    ///     - request: `RequestSchema`
    ///         - peerId: `Int`
    /// - Returns: `RPCResult`
    func sendRequest(_ request: RequestSchema, mcPeerId: Int) -> RPCResult {
//        print("sendRequest")
//        print("sendMethod: \(request.method)")
//        print("sendParam: \(request.param)")
        
        var rpcResult = RPCResult()
        switch (request.method, request.param) {
        case let (.coordinateTransformEntity(.requestTransform),.coordinateTransformEntity(.requestTransform(p))):
            rpcResult = coordinateTransforms.requestTransform(param: p)
        case let (.coordinateTransformEntity(.setTransform),.coordinateTransformEntity(.setTransform(p))):
            rpcResult = coordinateTransforms.setTransform(param: p)
        case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
            rpcResult = coordinateTransforms.setState(param: p)
        case (.paintingEntity(.addStrokePoint),.paintingEntity(.addStrokePoint(_))):
            // 自身に対して追加操作を行わない
            break
        case (.paintingEntity(.addBezierStrokePoints),.paintingEntity(.addBezierStrokePoints(_))):
            // 自身に対して追加操作を行わない
            break
        case (.paintingEntity(.addBezierStrokes),.paintingEntity(.addBezierStrokes(_))):
            // 自身に対して追加操作を行わない
            break
        case let
            (.paintingEntity(.setStrokeColor),.paintingEntity(.setStrokeColor(p))):
            painting.setStrokeColor(param: p)
        case (.paintingEntity(.moveControlPoint), .paintingEntity(.moveControlPoint(_))):
            // 自身に対して追加操作を行わない
            break
        default:
            return RPCResult("Invalid request")
        }
        // リクエストを送信
        transport.send(request, to: .peer(mcPeerId))
        return rpcResult
    }
    
    /// 全ての Peer に、それぞれの座標系へ変換したリクエストを送信する
    ///
    /// - Parameter makeRequest: 送信先の座標系へのアフィン行列からリクエストを生成する
    func sendRequestToPeers(_ makeRequest: (simd_float4x4) -> RequestSchema) {
        for (id, affineMatrix) in coordinateTransforms.affineMatrixs {
            _ = sendRequest(makeRequest(affineMatrix), mcPeerId: id)
        }
    }
    
    /// 受信した RPC の実行
    /// - Parameters: request: `RequestSchema`
    /// - Returns: `RPCResult`
    func receiveRequest(_ request: RequestSchema) -> RPCResult {
//        print("receiveRequest")
//        print("ReceiveMethod: \(request.method)")
//        print("ReceiveParam \(request.param)")
        
        // acknowledgment は RPCTransport で処理済み
        var rpcResult = RPCResult()
        switch (request.method, request.param) {
        case let (.coordinateTransformEntity(.requestTransform),.coordinateTransformEntity(.requestTransform(p))):
            rpcResult = coordinateTransforms.requestTransform(param: p)
        case let (.coordinateTransformEntity(.setTransform),.coordinateTransformEntity(.setTransform(p))):
            rpcResult = coordinateTransforms.setTransform(param: p)
        case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
            rpcResult = coordinateTransforms.setState(param: p)
        case let (.paintingEntity(.addStrokePoint),.paintingEntity(.addStrokePoint(p))):
            painting.addStrokePoint(param: p)
        case let (.paintingEntity(.addBezierStrokePoints),.paintingEntity(.addBezierStrokePoints(p))):
            painting.addBezierStrokePoints(param: p)
        case let (.paintingEntity(.finishStroke),.paintingEntity(.finishStroke(p))):
            painting.finishStroke(param: p)
        case let (.paintingEntity(.addBezierStrokes),.paintingEntity(.addBezierStrokes(p))):
            painting.addBezierStrokes(param: p)
        case let
            (.paintingEntity(.setStrokeColor),.paintingEntity(.setStrokeColor(p))):
            painting.setStrokeColor(param: p)
        case (.paintingEntity(.removeAllStroke),.paintingEntity(.removeAllStroke(_))):
            painting.removeAllStroke()
        case let
            (.paintingEntity(.removeStroke),.paintingEntity(.removeStroke(p))):
            painting.removeStroke(param: p)
        case let (.paintingEntity(.changeFingerLineWidth),.paintingEntity(.changeFingerLineWidth(p))):
            painting.changeFingerLineWidth(param: p)
        case let (.paintingEntity(.moveControlPoint), .paintingEntity(.moveControlPoint(p))):
            painting.moveControlPoint(param: p)
        case let (.paintingEntity(.finishControlPoint), .paintingEntity(.finishControlPoint(p))):
            painting.finishControlPoint(param: p)
        default:
            return RPCResult("Invalid request")
        }
        if !rpcResult.success {
            transport.sendError(message: rpcResult.errorMessage, to: request.peerId)
            return rpcResult
        }
        
        // リクエストが成功したら acknowledgment を送信（除外対象のメソッドは送信しない）
        if RPCTransport.requiresAcknowledgment(request.method) {
            transport.sendAcknowledgment(requestId: request.id, to: request.peerId)
        }
        
        return rpcResult
    }
}
