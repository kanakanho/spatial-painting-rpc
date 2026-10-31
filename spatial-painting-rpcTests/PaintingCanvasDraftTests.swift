//
//  PaintingCanvasDraftTests.swift
//  spatial-painting-rpcTests
//

import Foundation
import RealityKit
import Testing
import UIKit
@testable import spatial_painting_rpc

@MainActor
struct PaintingCanvasDraftTests {
    private let userId = UUID()
    private let otherUserId = UUID()

    /// 原点から十分に離れた位置に、ストロークの開始に必要な点を追加する
    ///
    /// - Note: 1 点目は無視され、2 点目は原点からの距離で飛びと判定されるので、3 点目からストロークが始まる
    private func startStroke(on canvas: PaintingCanvas, userId: UUID, strokeId: UUID = UUID(), x: Float = 1) {
        canvas.addPoint(strokeId, [x, 1, 0], userId: userId)
        canvas.addPoint(strokeId, [x, 1, 0.01], userId: userId)
        canvas.addPoint(strokeId, [x, 1, 0.02], userId: userId)
    }

    /// 描画中のストロークに点を追加する
    private func addPoints(to canvas: PaintingCanvas, userId: UUID, strokeId: UUID, count: Int, x: Float = 1) {
        for index: Int in 0..<count {
            canvas.addPoint(strokeId, [x, 1, 0.02 + Float(index + 1) * 0.01], userId: userId)
        }
    }

    @Test func testFirstTwoPointsDoNotStartStroke() {
        let canvas = PaintingCanvas()
        let strokeId = UUID()

        canvas.addPoint(strokeId, [1, 1, 0], userId: userId)
        #expect(canvas.strokes.isEmpty)

        canvas.addPoint(strokeId, [1, 1, 0.01], userId: userId)
        #expect(canvas.strokes.isEmpty)

        canvas.addPoint(strokeId, [1, 1, 0.02], userId: userId)
        #expect(canvas.strokes.count == 1)
        #expect(canvas.strokes.first?.uuid == strokeId)
    }

    @Test func testJumpReleasesStrokeAndNextPointStartsAnother() {
        let canvas = PaintingCanvas()
        let firstId = UUID()
        let secondId = UUID()
        startStroke(on: canvas, userId: userId, strokeId: firstId)

        canvas.addPoint(firstId, [3, 1, 0], userId: userId)
        #expect(canvas.strokes.count == 1)
        #expect(!canvas.isStrokeJump(userId: userId, to: [9, 9, 9]))

        canvas.addPoint(secondId, [3, 1, 0.01], userId: userId)

        #expect(canvas.strokes.map(\.uuid) == [firstId, secondId])
        #expect(canvas.strokes.first?.points.count == 1)
    }

    @Test func testIsStrokeJumpRequiresDraftStroke() {
        let canvas = PaintingCanvas()
        #expect(!canvas.isStrokeJump(userId: userId, to: [9, 9, 9]))

        startStroke(on: canvas, userId: userId)

        #expect(canvas.isStrokeJump(userId: userId, to: [9, 9, 9]))
        #expect(!canvas.isStrokeJump(userId: userId, to: [1, 1, 0.03]))
    }

    @Test func testFinishRemovesShortStroke() {
        let canvas = PaintingCanvas()
        let strokeId = UUID()
        startStroke(on: canvas, userId: userId, strokeId: strokeId)
        addPoints(to: canvas, userId: userId, strokeId: strokeId, count: 6)
        #expect(canvas.strokes.first?.points.count == 7)

        canvas.finishStroke(userId)

        #expect(canvas.strokes.isEmpty)
    }

    @Test func testFinishKeepsLongStrokeAndReleasesIt() {
        let canvas = PaintingCanvas()
        let strokeId = UUID()
        startStroke(on: canvas, userId: userId, strokeId: strokeId)
        addPoints(to: canvas, userId: userId, strokeId: strokeId, count: 7)
        #expect(canvas.strokes.first?.points.count == 8)

        canvas.finishStroke(userId)

        #expect(canvas.strokes.map(\.uuid) == [strokeId])
        #expect(!canvas.isStrokeJump(userId: userId, to: [9, 9, 9]))
    }

    @Test func testUsersDrawIndependently() {
        let canvas = PaintingCanvas()
        let strokeId = UUID()
        let otherStrokeId = UUID()
        canvas.setActiveColor(userId: userId, color: .red)
        canvas.setActiveColor(userId: otherUserId, color: .blue)
        canvas.setMaxRadius(userId: userId, radius: 0.02)
        canvas.setMaxRadius(userId: otherUserId, radius: 0.03)

        startStroke(on: canvas, userId: userId, strokeId: strokeId, x: 1)
        startStroke(on: canvas, userId: otherUserId, strokeId: otherStrokeId, x: 2)
        addPoints(to: canvas, userId: userId, strokeId: strokeId, count: 1, x: 1)

        let stroke: BezierStroke? = canvas.strokes.first { $0.uuid == strokeId }
        let otherStroke: BezierStroke? = canvas.strokes.first { $0.uuid == otherStrokeId }
        #expect(stroke?.points.count == 2)
        #expect(otherStroke?.points.count == 1)
        #expect(stroke?.activeColor == .red)
        #expect(otherStroke?.activeColor == .blue)
        #expect(stroke?.maxRadius == 0.02)
        #expect(otherStroke?.maxRadius == 0.03)
    }

    @Test func testDefaultBrushIsWhite() {
        let canvas = PaintingCanvas()

        startStroke(on: canvas, userId: userId)

        #expect(canvas.strokes.first?.activeColor == .white)
        #expect(canvas.strokes.first?.maxRadius == 1E-2)
    }

    @Test func testBrushChangeAppliesToNextStrokeOnly() {
        let canvas = PaintingCanvas()
        let strokeId = UUID()
        canvas.setActiveColor(userId: userId, color: .red)
        startStroke(on: canvas, userId: userId, strokeId: strokeId)

        canvas.setActiveColor(userId: userId, color: .blue)

        #expect(canvas.strokes.first?.activeColor == .red)
    }

    @Test func testBrushSurvivesReset() {
        let canvas = PaintingCanvas()
        canvas.setActiveColor(userId: userId, color: .red)
        canvas.setMaxRadius(userId: userId, radius: 0.02)

        canvas.reset()
        startStroke(on: canvas, userId: userId)

        #expect(canvas.strokes.first?.activeColor == .red)
        #expect(canvas.strokes.first?.maxRadius == 0.02)
    }

    @Test func testBezierPointsApplyToDraftStroke() {
        let canvas = PaintingCanvas()
        let strokeId = UUID()
        startStroke(on: canvas, userId: userId, strokeId: strokeId)

        canvas.addBezierStrokePoints(userId: userId, bezierPoints: [
            BezierPointData(uuid: UUID(), strokeId: strokeId, end: [1, 1, 0], endControl: [1, 1, 0.1])
        ])

        #expect(canvas.strokes.first?.bezierPoints.count == 1)
    }

    @Test func testIndividualPoints2BezierRequiresDraftStroke() {
        let canvas = PaintingCanvas()
        #expect(canvas.individualPoints2Bezier(userId: userId) == nil)

        startStroke(on: canvas, userId: userId)

        #expect(canvas.individualPoints2Bezier(userId: userId) != nil)
    }
}
