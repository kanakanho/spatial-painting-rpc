//
//  StrokeSystems.swift
//  spatial-painting-rpc
//

import RealityKit

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
