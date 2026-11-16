//
//  DraftStrokeComponentTests.swift
//  spatial-painting-rpcTests
//

import RealityKit
import Testing
@testable import spatial_painting_rpc

@MainActor
struct DraftStrokeComponentTests {
    private let threshold: Float = 0.1
    
    @Test func testFirstPointIsIgnoredAndDoesNotMovePosition() {
        var draft = DraftStrokeComponent()
        
        #expect(draft.step(to: [1, 1, 1], jumpThreshold: threshold) == .ignored)
        
        #expect(draft.lastPosition == .zero)
        #expect(draft.hasReceivedFirstPoint)
    }
    
    @Test func testNearPointIsAcceptedAndUpdatesPosition() {
        var draft = DraftStrokeComponent(hasReceivedFirstPoint: true)
        
        #expect(draft.step(to: [0.05, 0, 0], jumpThreshold: threshold) == .accepted)
        
        #expect(draft.lastPosition == [0.05, 0, 0])
    }
    
    @Test func testFarPointReleasesStrokeAndUpdatesPosition() {
        var draft = DraftStrokeComponent(strokeEntity: Entity(), hasReceivedFirstPoint: true)
        
        #expect(draft.step(to: [1, 0, 0], jumpThreshold: threshold) == .jumped)
        
        #expect(draft.strokeEntity == nil)
        #expect(draft.lastPosition == [1, 0, 0])
    }
    
    @Test func testPointAtThresholdIsAccepted() {
        var draft = DraftStrokeComponent(hasReceivedFirstPoint: true)
        
        #expect(draft.step(to: [threshold, 0, 0], jumpThreshold: threshold) == .accepted)
    }
}
