//
//  PaintingCanvasTmpStrokeTests.swift
//  spatial-painting-rpcTests
//

import Foundation
import RealityKit
import Testing
import UIKit
@testable import spatial_painting_rpc

@MainActor
struct PaintingCanvasTmpStrokeTests {
    /// x 軸に平行な直線のストロークを作る
    private func makeStroke(y: Float = 2) -> BezierStroke {
        let points: [SIMD3<Float>] = (0...20).map { (index: Int) -> SIMD3<Float> in
            return SIMD3<Float>(Float(index) * 0.05, y, 3)
        }
        return BezierStroke(uuid: UUID(), points: points, color: .red, maxRadius: 0.02)
    }

    /// 編集モードでストロークに触れたときの処理
    private func selectForMoving(_ stroke: BezierStroke, on canvas: PaintingCanvas) {
        canvas.addMovingStroke(stroke)
    }

    private func isClose(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, tolerance: Float = 1E-3) -> Bool {
        length(lhs - rhs) < tolerance
    }

    @Test func testBoundingBoxEnclosesPoints() throws {
        let boundingBox = try #require(PaintingCanvas.BoundingBoxCube(enclosing: [[0, 1, 2], [3, -1, 1], [1, 0, 5]]))
        
        #expect(boundingBox.corners[.minXMinYMinZ] == [0, -1, 1])
        #expect(boundingBox.corners[.maxXMaxYMaxZ] == [3, 1, 5])
        #expect(boundingBox.center == [1.5, 0, 3])
    }
    
    @Test func testBoundingBoxRequiresPoints() {
        #expect(PaintingCanvas.BoundingBoxCube(enclosing: []) == nil)
    }
    
    @Test func testAddTmpStrokesCentersGroupOnBoundingBox() {
        let canvas = PaintingCanvas()
        let stroke: BezierStroke = makeStroke()

        canvas.addTmpStrokes([stroke])

        #expect(canvas.tmpStrokes.count == 1)
        #expect(canvas.tmpStrokes.first?.uuid == stroke.uuid)
        #expect(canvas.boundingBoxEntity.parent === canvas.tmpRoot)
        #expect(isClose(canvas.boundingBoxEntity.position(relativeTo: nil), [0.5, 2, 3]))
    }

    @Test func testTmpStrokesStayAtOriginalWorldPosition() throws {
        let canvas = PaintingCanvas()

        canvas.addTmpStrokes([makeStroke()])

        let tmpStroke = try #require(canvas.tmpStrokes.first)
        #expect(isClose(tmpStroke.root.position(relativeTo: nil), .zero))
    }

    @Test func testAddTmpStrokesWithEmptyInputDoesNothing() {
        let canvas = PaintingCanvas()

        canvas.addTmpStrokes([])

        #expect(canvas.tmpStrokes.isEmpty)
        #expect(canvas.boundingBoxEntity.parent == nil)
    }

    @Test func testConfirmCreatesNewStrokeWithGroupTransform() throws {
        let canvas = PaintingCanvas()
        let stroke: BezierStroke = makeStroke()
        canvas.addTmpStrokes([stroke])

        canvas.boundingBoxEntity.position += [1, 0, 0]
        canvas.confirmTmpStrokes()

        let confirmed = try #require(canvas.strokes.first)
        let first = try #require(confirmed.points.first)
        let last = try #require(confirmed.points.last)
        #expect(canvas.strokes.count == 1)
        #expect(confirmed.uuid != stroke.uuid)
        #expect(confirmed.activeColor == .red)
        #expect(confirmed.maxRadius == 0.02)
        #expect(isClose(first, [1, 2, 3], tolerance: 1E-2))
        #expect(isClose(last, [2, 2, 3], tolerance: 1E-2))
    }

    @Test func testConfirmWithoutTmpStrokesDoesNothing() {
        let canvas = PaintingCanvas()

        #expect(canvas.confirmTmpStrokes().isEmpty)
        #expect(canvas.strokes.isEmpty)
    }

    @Test func testConfirmReturnsStrokesOnCanvas() {
        let canvas = PaintingCanvas()
        canvas.addTmpStrokes([makeStroke()])

        let confirmed: [BezierStroke] = canvas.confirmTmpStrokes()

        #expect(confirmed.map(\.uuid) == canvas.strokes.map(\.uuid))
    }

    @Test func testConfirmMovingStrokesRequiresSelection() {
        let canvas = PaintingCanvas()
        canvas.addTmpStrokes([makeStroke()])

        #expect(canvas.confirmMovingStrokes().isEmpty)
        #expect(canvas.strokes.isEmpty)
    }

    @Test func testConfirmMovingStrokesClearsSelection() {
        let canvas = PaintingCanvas()
        selectForMoving(makeStroke(), on: canvas)

        #expect(canvas.confirmMovingStrokes().count == 1)
        #expect(canvas.strokes.count == 1)
        #expect(canvas.confirmMovingStrokes().isEmpty)
    }

    @Test func testClearRemovesGroupAndResetsTransform() {
        let canvas = PaintingCanvas()
        canvas.addTmpStrokes([makeStroke()])

        canvas.clearTmpStrokes()

        #expect(canvas.tmpStrokes.isEmpty)
        #expect(canvas.boundingBoxEntity.parent == nil)
        #expect(canvas.boundingBoxEntity.transform.matrix == .identity)
    }

    @Test func testMovingSelectionAccumulates() {
        let canvas = PaintingCanvas()

        selectForMoving(makeStroke(), on: canvas)
        selectForMoving(makeStroke(y: 3), on: canvas)

        #expect(canvas.tmpStrokes.count == 2)
    }

    @Test func testMovingSelectionSurvivesClearAndRemovedSource() {
        let canvas = PaintingCanvas()
        let first: BezierStroke = makeStroke()
        canvas.root.addChild(first.root)
        selectForMoving(first, on: canvas)

        // パレットが非表示なら元のストロークは削除される
        first.root.removeFromParent()
        canvas.clearTmpStrokes()
        selectForMoving(makeStroke(y: 3), on: canvas)

        #expect(canvas.tmpStrokes.count == 2)
    }

    @Test func testColorAndWidthChangeRequiresMovingSelection() throws {
        let canvas = PaintingCanvas()
        canvas.addTmpStrokes([makeStroke()])

        canvas.changeColorOfMovingStrokes(.blue)
        canvas.changeLineWidthOfMovingStrokes(0.03)

        let loaded = try #require(canvas.tmpStrokes.first)
        #expect(loaded.activeColor == .red)
        #expect(loaded.maxRadius == 0.02)
    }

    @Test func testColorAndWidthChangeAppliesToMovingSelection() throws {
        let canvas = PaintingCanvas()
        selectForMoving(makeStroke(), on: canvas)

        canvas.changeColorOfMovingStrokes(.blue)
        canvas.changeLineWidthOfMovingStrokes(0.03)

        let moving = try #require(canvas.tmpStrokes.first)
        #expect(moving.activeColor == .blue)
        #expect(moving.maxRadius == 0.03)
    }

    @Test func testPointsOfTmpStrokeStayInGroupAfterGroupMoves() throws {
        let canvas = PaintingCanvas()
        canvas.addTmpStrokes([makeStroke()])
        let tmpStroke = try #require(canvas.tmpStrokes.first)
        let points: [SIMD3<Float>] = tmpStroke.points

        canvas.boundingBoxEntity.position += [1, 0, 0]

        #expect(tmpStroke.points == points)
    }
}
