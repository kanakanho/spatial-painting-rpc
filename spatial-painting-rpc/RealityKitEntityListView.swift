//
//  RealityKitEntityListView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2026/03/07.
//

import SwiftUI
import RealityKit

struct EntityInfo: Identifiable, Hashable {
    let id: UInt64
    let name: String
    let isEnabled: Bool
    let components: [String]
    let childrenCount: Int
    let children: [EntityInfo]
    
    init(entity: Entity) {
        self.id = entity.id
        self.name = entity.name.isEmpty ? "\(type(of: entity))" : entity.name
        self.isEnabled = entity.isEnabled
        self.components = entity.components.map { String(describing: type(of: $0)) }
        self.childrenCount = entity.children.count
        self.children = entity.children.map { EntityInfo(entity: $0) }
    }
}

struct RealityKitEntityListView: View {
    @EnvironmentObject private var appModel: AppModel
    
    @State private var entityInfo: EntityInfo?
    @State private var isToggleOn: Bool = true
    
    var body: some View {
        NavigationStack {
            VStack {
                // トグルを画面の上部に追加
                Toggle("常に表示", isOn: $isToggleOn)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                List {
                    if let info = entityInfo {
                        EntityRow(entityInfo: info, isExpanded: isToggleOn)
                    } else {
                        Text("エンティティを読み込み中...")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Entity Debugger")
        }
        .onChange(of: appModel.rpcModel.painting.paintingCanvas.strokes.count, initial: true) { _,_  in
            entityInfo = EntityInfo(entity: appModel.rpcModel.painting.paintingCanvas.root)
        }
    }
}

struct EntityRow: View {
    let entityInfo: EntityInfo
    let forceExpanded: Bool
    @State private var localIsExpanded: Bool
    
    init(entityInfo: EntityInfo, isExpanded: Bool) {
        self.entityInfo = entityInfo
        self.forceExpanded = isExpanded
        self._localIsExpanded = State(initialValue: isExpanded && entityInfo.isEnabled && !entityInfo.children.isEmpty)
    }
    
    var body: some View {
        DisclosureGroup(isExpanded: $localIsExpanded) {
            if entityInfo.children.isEmpty {
                Text("No children")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entityInfo.children) { child in
                    EntityRow(entityInfo: child, isExpanded: forceExpanded)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entityInfo.name)
                    .font(.headline)
                
                if !entityInfo.components.isEmpty {
                    Text("📦 \(entityInfo.components.joined(separator: ", "))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
                
                Text("Children: \(entityInfo.childrenCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: forceExpanded) { oldValue, newValue in
            localIsExpanded = newValue
        }
    }
}


#Preview {
    RealityKitEntityListView()
        .environmentObject(AppModel())
}
