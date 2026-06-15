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
    
    @ObservedObject var sendExchangeDataWrapper = ExchangeDataWrapper()
    @ObservedObject var receiveExchangeDataWrapper = ExchangeDataWrapper()
    var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
    @ObservedObject var rpcModel: RPCModel
    private var cancellables = Set<AnyCancellable>()
    var externalStrokeFileWapper: ExternalStrokeFileWapper = ExternalStrokeFileWapper()
    
    init() {
        let sendExchangeDataWrapper = ExchangeDataWrapper()
        let receiveExchangeDataWrapper = ExchangeDataWrapper()

        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper

        let mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
        self.rpcModel = RPCModel(sendExchangeDataWrapper: sendExchangeDataWrapper, receiveExchangeDataWrapper: receiveExchangeDataWrapper)
        // AppModel と RPCModel で同じ wrapper を共有
        self.rpcModel.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        
        // 子の通知を、親（AppModel）の通知として外に流す
        mcPeerIDUUIDWrapper.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
