//
//  PeerManager.swift
//  multipeer-share-coordinate-throw-ball
//
//  Created by blueken on 2024/12/02.
//

import Combine
import Foundation
import Network

@Observable
final class PeerManager {
    private let networkManager: RPCNetworkManager

    init(
        sendExchangeDataWrapper: ExchangeDataWrapper,
        receiveExchangeDataWrapper: ExchangeDataWrapper,
        mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
    ) {
        self.networkManager = RPCNetworkManager(
            sendExchangeDataWrapper: sendExchangeDataWrapper,
            receiveExchangeDataWrapper: receiveExchangeDataWrapper,
            peerDirectory: mcPeerIDUUIDWrapper,
            serviceType: "painting-rpc"
        )
    }

    func start() {
        networkManager.start()
    }

    func stop() {
        networkManager.stop()
    }
}

// MARK: - Network.framework + Bonjour (based on ImmersiveRPCKit/Network)

final class RPCNetworkManager {
    private let sendExchangeDataWrapper: ExchangeDataWrapper
    private let receiveExchangeDataWrapper: ExchangeDataWrapper
    private let peerDirectory: MCPeerIDUUIDWrapper
    private var cancellable: AnyCancellable?

    private let topologyManager: NetworkTopologyManager
    private let server: RPCServer
    private let browser: RPCBrowser

    init(
        sendExchangeDataWrapper: ExchangeDataWrapper,
        receiveExchangeDataWrapper: ExchangeDataWrapper,
        peerDirectory: MCPeerIDUUIDWrapper,
        serviceType: String
    ) {
        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
        self.peerDirectory = peerDirectory

        let topology = NetworkTopologyManager(
            localPeerId: peerDirectory.myId,
            onRoleChanged: nil,
            onPeersChanged: { [weak peerDirectory] peerIds in
                DispatchQueue.main.async {
                    peerDirectory?.setConnectedPeerIds(peerIds)
                }
            },
            onReceiveData: { [weak receiveExchangeDataWrapper] data in
                DispatchQueue.main.async {
                    receiveExchangeDataWrapper?.setData(data)
                }
            }
        )
        self.topologyManager = topology

        self.server = RPCServer(
            topologyManager: topology,
            serviceType: serviceType,
            localPeerId: peerDirectory.myId,
            localPriority: topology.localPriority
        )
        self.browser = RPCBrowser(topologyManager: topology, serviceType: serviceType)

        cancellable = sendExchangeDataWrapper.$exchangeData.sink { [weak self] exchangeData in
            self?.sendExchangeDataDidChange(exchangeData)
        }
    }

    func start() {
        do {
            try server.start()
        } catch {
            print("Failed to start RPC server: \(error.localizedDescription)")
        }
        browser.start()
    }

    func stop() {
        server.stop()
        browser.stop()
    }

    private func sendExchangeDataDidChange(_ exchangeData: ExchangeData) {
        if exchangeData.mcPeerId != 0 {
            guard let peerId = peerDirectory.peerId(forHash: exchangeData.mcPeerId) else {
                print("RPCNetworkManager: target peer not found for hash \(exchangeData.mcPeerId)")
                return
            }
            Task {
                await topologyManager.send(data: exchangeData.data, to: peerId)
            }
        } else {
            Task {
                await topologyManager.send(data: exchangeData.data, to: nil)
            }
        }
    }
}

final class RPCConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let topologyManager: NetworkTopologyManager
    private let endpoint: NWEndpoint

    private var peerId: UUID?

    init(connection: NWConnection, peerId: UUID?, topologyManager: NetworkTopologyManager) {
        self.connection = connection
        self.peerId = peerId
        self.topologyManager = topologyManager
        self.endpoint = connection.endpoint
    }

    func setPeerId(_ peerId: UUID) {
        self.peerId = peerId
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.startReceiveLoop()
            case .failed, .cancelled:
                self?.handleFailure()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    /// メッセージ送信（4バイトの長さヘッダーを付与して Big Endian パッキング）
    func send(data: Data) async throws {
        var packet = Data()
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(data)

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func startReceiveLoop() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, _, error in
            guard let self, error == nil, let content, content.count == 4 else {
                self?.handleFailure()
                return
            }

            let length = content.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0 else {
                self.startReceiveLoop()
                return
            }

            self.connection.receive(
                minimumIncompleteLength: Int(length),
                maximumLength: Int(length)
            ) { payload, _, _, error in
                guard error == nil, let payload else {
                    self.handleFailure()
                    return
                }

                Task {
                    await self.topologyManager.handleIncoming(data: payload, from: self.peerId)
                }

                self.startReceiveLoop()
            }
        }
    }

    private func handleFailure() {
        connection.cancel()
        Task {
            await topologyManager.handleDisconnect(peerId: peerId, endpoint: endpoint)
        }
    }
}

final class RPCServer {
    private var listener: NWListener?
    private let topologyManager: NetworkTopologyManager
    private let serviceType: String
    private let localPeerId: UUID
    private let localPriority: Int64

    init(
        topologyManager: NetworkTopologyManager,
        serviceType: String,
        localPeerId: UUID,
        localPriority: Int64
    ) {
        self.topologyManager = topologyManager
        self.serviceType = serviceType
        self.localPeerId = localPeerId
        self.localPriority = localPriority
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let listener = try NWListener(using: parameters)

        listener.service = NWListener.Service(
            name: localPeerId.uuidString,
            type: "_\(serviceType)._tcp",
            domain: "local.",
            txtRecord: [
                "peer_id": localPeerId.uuidString,
                "priority": String(localPriority),
            ].toTXTRecordData()
        )

        let topologyManager = self.topologyManager
        listener.newConnectionHandler = { newConnection in
            let rpcConnection = RPCConnection(connection: newConnection, peerId: nil, topologyManager: topologyManager)
            Task {
                await topologyManager.registerInboundConnection(rpcConnection, endpoint: newConnection.endpoint)
                rpcConnection.start()
            }
        }

        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

final class RPCBrowser: @unchecked Sendable {
    private var browser: NWBrowser?
    private let topologyManager: NetworkTopologyManager
    private let serviceType: String

    private var knownPeers: [UUID: NWEndpoint] = [:]

    init(topologyManager: NetworkTopologyManager, serviceType: String) {
        self.topologyManager = topologyManager
        self.serviceType = serviceType
    }

    func start() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_\(serviceType)._tcp", domain: "local.")
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: parameters)

        let topologyManager = self.topologyManager
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }

            var currentPeers: [UUID: NWEndpoint] = [:]

            for result in results {
                let metadata = result.metadata
                var txtRecord: [String: String] = [:]
                if case let .bonjour(bonjour) = metadata {
                    txtRecord = Self.parseTXTRecord(bonjour)
                } else {
                    print("RPCBrowser non-bonjour result: \(result.endpoint)")
                }

                if txtRecord.isEmpty {
                    print("RPCBrowser txtRecord empty for endpoint: \(result.endpoint)")
                }

                guard let peerId = Self.peerId(from: result.endpoint, txtRecord: txtRecord) else {
                    print("RPCBrowser missing peerId for endpoint: \(result.endpoint), txtRecord: \(txtRecord)")
                    continue
                }
                let priority = Self.priority(from: txtRecord) ?? Self.fallbackPriority(from: peerId)
                if txtRecord["priority"] == nil {
                    print("RPCBrowser using fallback priority for peerId: \(peerId)")
                }

                currentPeers[peerId] = result.endpoint

                Task {
                    await topologyManager.updatePeerPriority(
                        id: peerId,
                        priority: priority,
                        endpoint: result.endpoint
                    )
                }
            }

            let removed = Set(self.knownPeers.keys).subtracting(currentPeers.keys)
            for peerId in removed {
                if let endpoint = self.knownPeers[peerId] {
                    Task {
                        await topologyManager.handleDisconnect(peerId: peerId, endpoint: endpoint)
                    }
                }
            }

            self.knownPeers = currentPeers
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        knownPeers.removeAll()
    }

    private static func parseTXTRecord(_ record: NWTXTRecord) -> [String: String] {
        let dict = NetService.dictionary(fromTXTRecord: record.data)
        var result: [String: String] = [:]
        for (key, value) in dict {
            if let string = String(data: value, encoding: .utf8) {
                result[key] = string
            }
        }
        return result
    }

    private static func priority(from txtRecord: [String: String]) -> Int64? {
        guard let priorityStr = txtRecord["priority"] else { return nil }
        return Int64(priorityStr)
    }

    private static func peerId(from endpoint: NWEndpoint, txtRecord: [String: String]) -> UUID? {
        if let explicit = txtRecord["peer_id"], let uuid = UUID(uuidString: explicit) {
            return uuid
        }
        if case let .service(name, _, _, _) = endpoint {
            return UUID(uuidString: name)
        }
        return nil
    }

    private static func fallbackPriority(from peerId: UUID) -> Int64 {
        var uuid = peerId.uuid
        let value = withUnsafeBytes(of: &uuid) { raw -> UInt64 in
            var result: UInt64 = 0
            for byte in raw.prefix(8) {
                result = (result << 8) | UInt64(byte)
            }
            return result
        }
        return Int64(bitPattern: value)
    }
}

actor NetworkTopologyManager {
    nonisolated let localPeerId: UUID
    nonisolated let localPriority: Int64

    private var inboundConnections: [UUID: RPCConnection] = [:]
    private var outboundConnections: [UUID: RPCConnection] = [:]
    private var pendingInboundConnections: [NWEndpoint: RPCConnection] = [:]

    private var peerPriorities: [UUID: Int64] = [:]
    private var endpointByPeerId: [UUID: NWEndpoint] = [:]

    private var isMasterHost: Bool = true

    private var onRoleChanged: ((Bool) -> Void)?
    private var onPeersChanged: (([UUID]) -> Void)?
    private var onReceiveData: ((Data) -> Void)?

    init(
        localPeerId: UUID = UUID(),
        onRoleChanged: ((Bool) -> Void)? = nil,
        onPeersChanged: (([UUID]) -> Void)? = nil,
        onReceiveData: ((Data) -> Void)? = nil
    ) {
        self.localPeerId = localPeerId
        self.localPriority = Self.priority(from: localPeerId)
        self.peerPriorities[localPeerId] = localPriority
        self.onRoleChanged = onRoleChanged
        self.onPeersChanged = onPeersChanged
        self.onReceiveData = onReceiveData
    }

    private static func priority(from peerId: UUID) -> Int64 {
        var uuid = peerId.uuid
        let value = withUnsafeBytes(of: &uuid) { raw -> UInt64 in
            var result: UInt64 = 0
            for byte in raw.prefix(8) {
                result = (result << 8) | UInt64(byte)
            }
            return result
        }
        return Int64(bitPattern: value)
    }

    func updatePeerPriority(id: UUID, priority: Int64, endpoint: NWEndpoint) {
        guard id != localPeerId else { return }

        peerPriorities[id] = priority
        endpointByPeerId[id] = endpoint

        if let pending = pendingInboundConnections.removeValue(forKey: endpoint) {
            registerInboundConnection(pending, peerId: id)
        } else if pendingInboundConnections.count == 1,
            inboundConnections[id] == nil,
            outboundConnections[id] == nil
        {
            let pending = pendingInboundConnections.values.first
            pendingInboundConnections.removeAll()
            if let pending {
                registerInboundConnection(pending, peerId: id)
            }
        }

        evaluateTopology(targetEndpoint: endpoint, targetPeerId: id)
    }

    func registerInboundConnection(_ rpcConnection: RPCConnection, peerId: UUID) {
        inboundConnections[peerId] = rpcConnection
        rpcConnection.setPeerId(peerId)
        notifyPeersChanged()
    }

    func registerInboundConnection(_ rpcConnection: RPCConnection, endpoint: NWEndpoint) {
        if let peerId = peerId(for: endpoint) {
            registerInboundConnection(rpcConnection, peerId: peerId)
        } else {
            pendingInboundConnections[endpoint] = rpcConnection
        }
    }

    func registerOutboundConnection(_ rpcConnection: RPCConnection, peerId: UUID) {
        outboundConnections[peerId] = rpcConnection
        rpcConnection.setPeerId(peerId)
        notifyPeersChanged()
    }

    func handleDisconnect(peerId: UUID?, endpoint: NWEndpoint) {
        if let peerId {
            inboundConnections.removeValue(forKey: peerId)
            outboundConnections.removeValue(forKey: peerId)
            peerPriorities.removeValue(forKey: peerId)
            endpointByPeerId.removeValue(forKey: peerId)
        } else {
            pendingInboundConnections.removeValue(forKey: endpoint)
        }

        evaluateTopology(targetEndpoint: nil, targetPeerId: nil)
        notifyPeersChanged()
    }

    func send(data: Data, to targetPeerId: UUID?) async {
        if let targetPeerId {
            if let connection = outboundConnections[targetPeerId] ?? inboundConnections[targetPeerId] {
                try? await connection.send(data: data)
            }
            return
        }
        await broadcast(data: data, excluding: nil)
    }

    func handleIncoming(data: Data, from originPeerId: UUID?) async {
        if let originPeerId, isMasterHost {
            await broadcast(data: data, excluding: originPeerId)
        }
        onReceiveData?(data)
    }

    private func evaluateTopology(targetEndpoint: NWEndpoint?, targetPeerId: UUID?) {
        let higherPeers = peerPriorities.filter { $0.value < localPriority }

        if higherPeers.isEmpty {
            if !isMasterHost {
                isMasterHost = true
                onRoleChanged?(true)
            }
            return
        }

        if isMasterHost {
            isMasterHost = false
            onRoleChanged?(false)
        }

        guard let trueMaster = peerPriorities.min(by: { $0.value < $1.value }) else { return }

        if let endpoint = targetEndpoint, targetPeerId == trueMaster.key {
            initiateOutboundConnection(to: endpoint, peerId: trueMaster.key)
        }
    }

    private func initiateOutboundConnection(to endpoint: NWEndpoint, peerId: UUID) {
        if outboundConnections[peerId] != nil || inboundConnections[peerId] != nil {
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        let rpcConnection = RPCConnection(connection: connection, peerId: peerId, topologyManager: self)
        outboundConnections[peerId] = rpcConnection
        rpcConnection.start()
        notifyPeersChanged()
    }

    private func broadcast(data: Data, excluding originPeerId: UUID?) async {
        for (peerId, connection) in inboundConnections where peerId != originPeerId {
            try? await connection.send(data: data)
        }
        for (peerId, connection) in outboundConnections where peerId != originPeerId {
            try? await connection.send(data: data)
        }
    }

    private func peerId(for endpoint: NWEndpoint) -> UUID? {
        endpointByPeerId.first(where: { $0.value == endpoint })?.key
    }

    private func notifyPeersChanged() {
        let inboundIds = inboundConnections.keys
        let outboundIds = outboundConnections.keys
        let combined = Set(inboundIds).union(outboundIds)
        let peers = combined.filter { $0 != localPeerId }
        onPeersChanged?(Array(peers))
    }
}

extension Dictionary where Key == String, Value == String {
    fileprivate func toTXTRecordData() -> Data {
        var txtData = Data()
        for (key, value) in self {
            let string = "\(key)=\(value)"
            if let stringData = string.data(using: .utf8), stringData.count <= 255 {
                txtData.append(UInt8(stringData.count))
                txtData.append(stringData)
            }
        }
        return txtData
    }
}
