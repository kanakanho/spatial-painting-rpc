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
    
    var body: some View {
        VStack {
            Button("File Manager") {
                openWindow(id: "ExternalStroke")
            }
            .padding(.horizontal)
            
            ToggleImmersiveSpaceButton()
                .environmentObject(appModel)
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
            sharedCoordinateState = .prepare
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(AppModel())
}
