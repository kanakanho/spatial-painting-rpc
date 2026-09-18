//
//  ClosureComponent.swift
//  spatial-painting
//
//  Created by blueken on 2025/03/18.
//

import SwiftUI
import RealityKit

/// A component to attach to an entity that updates over time.
struct ClosureComponent: Component {
    /// The closure that takes the time interval since the last update.
    let closure: @MainActor (TimeInterval) -> Void

    // Initialize the component by assigning the closure and registering `ClosureSystem`.
    @MainActor
    init(closure: @escaping @MainActor (TimeInterval) -> Void) {
        self.closure = closure
        ClosureSystem.registerSystem()
    }
}

/// A system that updates the scene over the duration of the app's runtime.
struct ClosureSystem: System {
    /// The query to find entities that contain `ClosureComponent`.
    static let query = EntityQuery(where: .has(ClosureComponent.self))

    init(scene: RealityKit.Scene) {}

    /// Update entities with `ClosureComponent` at each render frame.
    func update(context: SceneUpdateContext) {
        // Iterate over all entities in the query.
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            /// The variable to ensure the entity has a `ClosureComponent`.
            guard let comp = entity.components[ClosureComponent.self] else { continue }
            // Execute the closure, and pass the delta time since the last update.
            comp.closure(context.deltaTime)
        }
    }
}
