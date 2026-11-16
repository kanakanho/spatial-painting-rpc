//
//  StrokeColliderTests.swift
//  spatial-painting-rpcTests
//

import Foundation
import RealityKit
import Testing
@testable import spatial_painting_rpc

@MainActor
struct StrokeColliderTests {
    private let strokeId = UUID()
    
    /// Reality Composer Pro の collider と同じ設定のプロトタイプ
    private func makePrototype() -> Entity {
        let prototype = Entity()
        var collision = CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(repeating: 10))], mode: .default)
        collision.filter = CollisionFilter(group: CollisionGroup(rawValue: 1), mask: .all)
        prototype.components.set(collision)
        prototype.components.set(InputTargetComponent())
        return prototype
    }
    
    private func makePoints(count: Int) -> [SIMD3<Float>] {
        (0..<count).map { SIMD3<Float>(Float($0) * 0.01, 0, 0) }
    }
    
    @Test func testOneEntityWithShapeEveryFivePoints() throws {
        let collider = try #require(StrokeColliderSystem.makeCollider(strokeId: strokeId, points: makePoints(count: 12), prototype: makePrototype()))
        
        #expect(collider.components[CollisionComponent.self]?.shapes.count == 3)
        #expect(collider.components[StrokeColliderComponent.self]?.strokeId == strokeId)
        #expect(collider.children.isEmpty)
    }
    
    @Test func testKeepsPrototypeCollisionSettingsAndInputTarget() throws {
        let collider = try #require(StrokeColliderSystem.makeCollider(strokeId: strokeId, points: makePoints(count: 5), prototype: makePrototype()))
        let collision = try #require(collider.components[CollisionComponent.self])
        
        #expect(collision.mode == .default)
        #expect(collision.filter.group == CollisionGroup(rawValue: 1))
        #expect(collision.filter.mask == .all)
        #expect(collider.components.has(InputTargetComponent.self))
    }
    
    @Test func testShapesUseScaledPrototypeSizeAtPoints() throws {
        let points: [SIMD3<Float>] = makePoints(count: 6)
        let collider = try #require(StrokeColliderSystem.makeCollider(strokeId: strokeId, points: points, prototype: makePrototype()))
        let shapes: [ShapeResource] = try #require(collider.components[CollisionComponent.self]?.shapes)
        
        for (shape, point) in zip(shapes, [points[0], points[5]]) {
            #expect(abs(shape.bounds.extents.x - 0.025) < 1E-5)
            #expect(length(shape.bounds.center - point) < 1E-5)
        }
    }
    
    @Test func testNoPointsMakesNoCollider() {
        #expect(StrokeColliderSystem.makeCollider(strokeId: strokeId, points: [], prototype: makePrototype()) == nil)
    }
    
    @Test func testPlaceholderPrototypeMakesColliderWithoutCollision() throws {
        let collider = try #require(StrokeColliderSystem.makeCollider(strokeId: strokeId, points: makePoints(count: 3), prototype: Entity()))
        
        #expect(!collider.components.has(CollisionComponent.self))
        #expect(collider.components.has(StrokeColliderComponent.self))
    }
}
