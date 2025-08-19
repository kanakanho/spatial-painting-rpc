/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 An extension of the entity class, to include a model component.
 */

import RealityKit
import UIKit

/// The extension of the `Entity` class to have a model component variable.
extension Entity {
    var model: ModelComponent? {
        get { components[ModelComponent.self] }
        set { components[ModelComponent.self] = newValue }
    }
}

// added by nagao 2025/3/22
extension ModelEntity {
    class func createFingertip(name: String, color: UIColor) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.01),
            materials: [SimpleMaterial(color: color, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.01),
            mass: 0.0
        )
        
        entity.name = name
        entity.components.set(PhysicsBodyComponent(mode: .kinematic))
        entity.components.set(OpacityComponent(opacity: 1.0))
        
        return entity
    }
}

// MARK: — Entity 拡張
extension Entity {
    /// StrokeComponent を持っているかどうか
    var hasStrokeComponent: Bool {
        components.contains { $0 is StrokeComponent }
    }
}
