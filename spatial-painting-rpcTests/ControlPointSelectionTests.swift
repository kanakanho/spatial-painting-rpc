//
//  ControlPointSelectionTests.swift
//  spatial-painting-rpcTests
//

import RealityKit
import Testing
@testable import spatial_painting_rpc

@MainActor
struct ControlPointSelectionTests {
    @Test func testNothingIsSelectedInitially() {
        let canvas = PaintingCanvas()
        
        #expect(canvas.selectedControlPoint == nil)
    }
    
    @Test func testSelectRemembersEntityAndPosition() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        entity.position = [1, 2, 3]
        
        #expect(canvas.selectControlPoint(entity))
        
        #expect(canvas.selectedControlPoint === entity)
        #expect(canvas.selectedControlPointBasePosition == [1, 2, 3])
        #expect(entity.components.has(SelectedControlPointComponent.self))
    }
    
    @Test func testSelectingSameEntityReturnsFalseAndKeepsBasePosition() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        entity.position = [1, 2, 3]
        _ = canvas.selectControlPoint(entity)
        
        entity.position = [4, 5, 6]
        
        #expect(!canvas.selectControlPoint(entity))
        #expect(canvas.selectedControlPointBasePosition == [1, 2, 3])
    }
    
    @Test func testSwitchingSelectionMovesMarker() {
        let canvas = PaintingCanvas()
        let first = Entity()
        let second = Entity()
        _ = canvas.selectControlPoint(first)
        
        #expect(canvas.selectControlPoint(second))
        
        #expect(canvas.selectedControlPoint === second)
        #expect(!first.components.has(SelectedControlPointComponent.self))
        #expect(second.components.has(SelectedControlPointComponent.self))
    }
    
    @Test func testClearRemovesSelection() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        _ = canvas.selectControlPoint(entity)
        
        canvas.clearControlPointSelection()
        
        #expect(canvas.selectedControlPoint == nil)
        #expect(!entity.components.has(SelectedControlPointComponent.self))
    }
    
    @Test func testSelectAgainAfterClearSucceeds() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        _ = canvas.selectControlPoint(entity)
        canvas.clearControlPointSelection()
        
        #expect(canvas.selectControlPoint(entity))
    }
    
    @Test func testUpdateBasePositionUsesCurrentPosition() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        _ = canvas.selectControlPoint(entity)
        
        entity.position = [1, 2, 3]
        canvas.updateControlPointBasePosition()
        
        #expect(canvas.selectedControlPointBasePosition == [1, 2, 3])
    }
    
    @Test func testSwitchingSelectionMarksBothEntitiesForAppearanceUpdate() {
        let canvas = PaintingCanvas()
        let first = Entity()
        let second = Entity()
        _ = canvas.selectControlPoint(first)
        first.components.remove(ControlPointAppearanceDirty.self)
        
        _ = canvas.selectControlPoint(second)
        
        #expect(first.components.has(ControlPointAppearanceDirty.self))
        #expect(second.components.has(ControlPointAppearanceDirty.self))
    }
    
    @Test func testClearMarksEntityForAppearanceUpdate() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        _ = canvas.selectControlPoint(entity)
        entity.components.remove(ControlPointAppearanceDirty.self)
        
        canvas.clearControlPointSelection()
        
        #expect(entity.components.has(ControlPointAppearanceDirty.self))
    }
    
    @Test func testSelectionSurvivesReset() {
        let canvas = PaintingCanvas()
        let entity = Entity()
        _ = canvas.selectControlPoint(entity)
        
        canvas.reset()
        
        #expect(canvas.selectedControlPoint === entity)
    }
}
