//
//  MCPeerIDUUIDWrapper.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/13.
//

import Foundation

struct PeerIdentity: Hashable {
    let id: UUID
    let displayName: String

    init(id: UUID) {
        self.id = id
        self.displayName = id.uuidString
    }

    var hash: Int {
        MCPeerIDUUIDWrapper.stableHash(for: id)
    }
}

/// 各端末の接続状況を管理するラッパー
class MCPeerIDUUIDWrapper: ObservableObject {
    /// 自身の id
    let myId: UUID
    /// 自身の Peer 情報
    @Published var mine: PeerIdentity
    /// 通信可能な Peer 情報
    @Published var standby: [PeerIdentity] = []

    init() {
        self.myId = UUID()
        self.mine = PeerIdentity(id: myId)
    }

    func setConnectedPeerIds(_ peerIds: [UUID]) {
        standby = peerIds
            .map { PeerIdentity(id: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    func peerId(forHash hash: Int) -> UUID? {
        standby.first { $0.hash == hash }?.id
    }

    func remove(peerId: UUID) {
        standby.removeAll { $0.id == peerId }
    }

    static func stableHash(for uuid: UUID) -> Int {
        var bytes = uuid.uuid
        let value = withUnsafeBytes(of: &bytes) { raw -> UInt64 in
            var result: UInt64 = 0
            for byte in raw.prefix(8) {
                result = (result << 8) | UInt64(byte)
            }
            return result
        }
        return Int(truncatingIfNeeded: value)
    }
}
