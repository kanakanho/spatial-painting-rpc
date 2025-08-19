//
//  ContentView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI
import RealityKit
import RealityKitContent

enum SharedCoordinateState {
    case prepare
    case sharing
    case shared
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sharedCoordinateState: SharedCoordinateState = .prepare
    @Environment(\.scenePhase) var scenePhase
    
    @Environment(\.openWindow) private var openWindow
    
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var startTime = Date()
    @State var isStartImmersiveSpace: Bool = false
    
    var body: some View {
        VStack {
            Button("File Manager") {
                openWindow(id: "ExternalStroke")
            }
            .padding(.horizontal)
            
            ToggleImmersiveSpaceButton()
                .environmentObject(appModel)
                .disabled(!isStartImmersiveSpace)
            NavigationStack {
                switch sharedCoordinateState {
                case .prepare:
                    VStack {
                        Spacer()
                        Button("Start Sharing") {
                            print(appModel.mcPeerIDUUIDWrapper.mine.displayName)
                            sharedCoordinateState = .sharing
                        }
                        Spacer()
                    }
                case .sharing:
                    TransformationMatrixPreparationView(rpcModel: appModel.rpcModel, sharedCoordinateState: $sharedCoordinateState)
                case .shared:
                    Text("Shared Coordinate Ready")
                }
            }
            Spacer()
        }
        .padding()
        .onAppear() {
            print(">>> App appeared")
            appModel.peerManager.start()
            sharedCoordinateState = .prepare
        }
        .onChange(of: scenePhase) { oldScenePhase, newScenePhase in
            if oldScenePhase == .inactive && newScenePhase == .active {
                print(">>> Scene became active")
                appModel.peerManager = PeerManager(
                    sendExchangeDataWrapper: appModel.sendExchangeDataWrapper,
                    receiveExchangeDataWrapper: appModel.receiveExchangeDataWrapper,
                    mcPeerIDUUIDWrapper: appModel.mcPeerIDUUIDWrapper
                )
                appModel.peerManager.start()
            }
            if newScenePhase == .background {
                print("<<< Scene went to background")
                sharedCoordinateState = .prepare
                appModel.mcPeerIDUUIDWrapper.standby.removeAll()
                appModel.peerManager.stop()
            }
        }
        .onReceive(timer) { _ in
            // 5秒後にImmersive Spaceを開く
            if  !isStartImmersiveSpace {
                let elapsedTime = Date().timeIntervalSince(startTime)
                if elapsedTime >= 6 {
                    isStartImmersiveSpace = true
                }
            } else {
                // timerを停止
                timer.upstream.connect().cancel()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(AppModel())
}
