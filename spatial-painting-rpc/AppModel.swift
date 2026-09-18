//
//  AppModel.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI
import Combine

/// Maintains app-wide state
@MainActor
class AppModel: ObservableObject {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    @Published var immersiveSpaceState = ImmersiveSpaceState.closed
    
    var model = ViewModel()
    
    let mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
    @ObservedObject var rpcModel: RPCModel
    private var cancellables = Set<AnyCancellable>()
    var externalStrokeFileWapper: ExternalStrokeFileWapper = ExternalStrokeFileWapper()
    
    init() {
        let mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
        // AppModel と RPCModel で同じ wrapper を共有
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        self.rpcModel = RPCModel(
            transport: RPCTransport(localPeerId: mcPeerIDUUIDWrapper.myId),
            mcPeerIDUUIDWrapper: mcPeerIDUUIDWrapper
        )
        
        // 子の通知を、親（AppModel）の通知として外に流す
        mcPeerIDUUIDWrapper.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
