//
//  spatial_painting_rpcApp.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI

@main
struct spatial_painting_rpcApp: App {
    @ObservedObject private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        
        WindowGroup("ExternalStroke", id: "ExternalStroke") {
            ExternalStrokeView()
                .environmentObject(appModel)
                .handlesExternalEvents(preferring: [], allowing: [])
        }
        .handlesExternalEvents(matching: ["targetContentIdentifier"])
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView(stylusManager: StylusManager(appModel: appModel))
                .environmentObject(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
