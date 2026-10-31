//
//  StrokeSystems.swift
//  spatial-painting-rpc
//

import Foundation
import RealityKit
import UIKit

/// `StrokeMeshDirty` が付いたストロークのメッシュを再生成する
///
/// - Note: 1 フレームに複数の点が届いても、メッシュの生成は 1 回で済む
struct StrokeMeshSystem: System {
    private static let query: EntityQuery = EntityQuery(
        where: .has(StrokeComponent.self) && .has(StrokeStyleComponent.self) && .has(StrokeMeshDirty.self)
    )

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let entities: [Entity] = Array(context.entities(matching: Self.query, updatingSystemWhen: .rendering))

        for entity: Entity in entities {
            entity.components.remove(StrokeMeshDirty.self)

            guard let strokeComponent: StrokeComponent = entity.components[StrokeComponent.self],
                  let style: StrokeStyleComponent = entity.components[StrokeStyleComponent.self],
                  let meshEntity: Entity = entity.children.first(where: { $0.components.has(StrokeMeshComponent.self) }) else {
                continue
            }

            updateMesh(of: meshEntity, points: strokeComponent.geometry.points, style: style)
        }
    }

    /// Update the mesh with the points of the stroke if it already exists,
    /// or create a new one with the given mesh data.
    @MainActor
    private func updateMesh(of meshEntity: Entity, points: [SIMD3<Float>], style: StrokeStyleComponent) {
        /// The position, normals, and triangle indices that the points generate.
        let meshData: StrokeMeshData = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: style.maxRadius)

        /// The `MeshResource.Contents` instance.
        let contents: MeshResource.Contents = StrokeMeshBuilder.makeContents(meshData)

        // Replace the mesh with `contents` if there is a mesh component on the stroke.
        if let mesh: MeshResource = meshEntity.model?.mesh {
            do {
                try mesh.replace(with: contents)
                // マテリアルを更新 added by nagao 2025/11/21
                meshEntity.model?.materials = [style.makeMaterial()]
            } catch {
                print("Error replacing mesh: \(error.localizedDescription)")
            }
        } else {
            /// The new mesh that generates with `content`.
            guard let mesh: MeshResource = try? MeshResource.generate(from: contents) else {
                print("Error generating mesh")
                return
            }

            // Set the model component to the new mesh, and assign a simple material.
            meshEntity.components.set(ModelComponent(
                mesh: mesh,
                materials: [style.makeMaterial()]
            ))
        }
    }
}

/// `StrokeColliderDirty` が付いたストロークの消しゴム用コライダーを作り直す
///
/// - Note: コライダーはストロークの子なので、ストロークと一緒に削除される。
///   点ごとにプロトタイプを複製すると 1 フレームに数十 ms かかるので、
///   プロトタイプの判定の設定を引き継いだ 1 つの Entity に、点の数だけ形状を並べる
struct StrokeColliderSystem: System {
    /// コライダーを配置する点の間隔
    private static let pointInterval: Int = 5
    
    /// プロトタイプの形状に掛けるスケール。複製方式で設定していた値と同じ
    private static let prototypeScale: Float = 0.0025
    
    /// プロトタイプに形状がないときの箱の一辺（m）
    private static let defaultBoxSize: Float = 0.025
    
    private static let query: EntityQuery = EntityQuery(
        where: .has(StrokeComponent.self) && .has(StrokeColliderDirty.self)
    )
    
    init(scene: RealityKit.Scene) {}
    
    func update(context: SceneUpdateContext) {
        let entities: [Entity] = Array(context.entities(matching: Self.query, updatingSystemWhen: .rendering))
        
        for entity: Entity in entities {
            entity.components.remove(StrokeColliderDirty.self)
            
            guard let strokeComponent: StrokeComponent = entity.components[StrokeComponent.self],
                  let assets: StrokeAssetsComponent = entity.parent?.components[StrokeAssetsComponent.self] else {
                continue
            }
            
            removeColliders(from: entity)
            if let collider: Entity = Self.makeCollider(strokeId: strokeComponent.id, points: strokeComponent.geometry.points, prototype: assets.eraser) {
                entity.addChild(collider)
            }
        }
    }
    
    @MainActor
    private func removeColliders(from entity: Entity) {
        let colliders: [Entity] = entity.children.filter { $0.components.has(StrokeColliderComponent.self) }
        for collider: Entity in colliders {
            collider.removeFromParent()
        }
    }
    
    /// ストロークを消しゴムで選択するためのコライダーを、点列に沿って形状を並べて作る
    ///
    /// - Note: 判定の設定（mode、filter）とジェスチャーの対象であることは、プロトタイプの
    ///   `CollisionComponent` と `InputTargetComponent` から引き継ぐ。形状はプロトタイプと同じ大きさの箱にする
    /// - Parameters:
    ///   - strokeId: ストロークの UUID
    ///   - points: ストローク root のローカル座標の点列
    ///   - prototype: Reality Composer Pro で作ったコライダーのプロトタイプ
    /// - Returns: 点がなければ nil
    @MainActor
    static func makeCollider(strokeId: UUID, points: [SIMD3<Float>], prototype: Entity) -> Entity? {
        let boxSize: Float = boxSize(of: prototype)
        let shapes: [ShapeResource] = stride(from: 0, to: points.count, by: pointInterval).map { (index: Int) -> ShapeResource in
            return ShapeResource.generateBox(size: SIMD3<Float>(repeating: boxSize)).offsetBy(translation: points[index])
        }
        guard !shapes.isEmpty else { return nil }
        
        let collider = Entity()
        collider.name = "clear"
        if var collision: CollisionComponent = prototype.components[CollisionComponent.self] {
            collision.shapes = shapes
            collider.components.set(collision)
        }
        if let inputTarget: InputTargetComponent = prototype.components[InputTargetComponent.self] {
            collider.components.set(inputTarget)
        }
        collider.components.set(StrokeColliderComponent(strokeId: strokeId))
        return collider
    }
    
    /// プロトタイプの形状にスケールを掛けた箱の一辺
    @MainActor
    private static func boxSize(of prototype: Entity) -> Float {
        guard let extents: SIMD3<Float> = prototype.components[CollisionComponent.self]?.shapes.first?.bounds.extents else {
            return defaultBoxSize
        }
        return extents.x * prototypeScale
    }
}
