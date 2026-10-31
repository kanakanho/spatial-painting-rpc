//
//  StrokeEntityTests.swift
//  spatial-painting-rpcTests
//

import Foundation
import RealityKit
import Testing
@testable import spatial_painting_rpc

@MainActor
struct StrokeEntityTests {
    private let strokeId = UUID()
    private let pointId = UUID()
    private let secondPointId = UUID()

    private func makeData() -> BezierStrokeData {
        BezierStrokeData(
            uuid: strokeId,
            points: [[0, 0, 0], [3, 0, 0]],
            color: .hsba([0.5, 0.5, 0.5, 1]),
            maxRadius: 0.02,
            bezierPoints: [
                BezierPointData(uuid: pointId, strokeId: strokeId, end: [0, 0, 0], startControl: [-1, 0, 0], endControl: [1, 0, 0]),
                BezierPointData(uuid: secondPointId, strokeId: strokeId, end: [3, 0, 0], startControl: [2, 0, 0], endControl: [4, 0, 0])
            ]
        )
    }

    private func controlPointEntities(of stroke: BezierStroke) -> [Entity] {
        stroke.root.children.filter { $0.components.has(BezierPointComponent.self) }
    }

    @Test func testDataRoundTrip() {
        let data: BezierStrokeData = BezierStroke(data: makeData()).data

        #expect(data.uuid == strokeId)
        #expect(data.points == [[0, 0, 0], [3, 0, 0]])
        #expect(data.maxRadius == 0.02)
        #expect(data.bezierPoints.map(\.uuid) == makeData().bezierPoints.map(\.uuid))
    }

    @Test func testWrapperSharesGeometryWithEntity() throws {
        let stroke = BezierStroke(data: makeData())

        let wrapper = try #require(BezierStroke(entity: stroke.root))
        wrapper.points.append([9, 9, 9])

        #expect(wrapper.uuid == strokeId)
        #expect(wrapper.geometry === stroke.geometry)
        #expect(stroke.points.last == [9, 9, 9])
    }

    @Test func testWrapperRequiresStrokeComponent() {
        #expect(BezierStroke(entity: Entity()) == nil)
    }

    @Test func testUpdateMeshMarksDirtyOnlyWithPoints() {
        let empty = BezierStroke(uuid: UUID())
        empty.updateMesh()
        #expect(!empty.root.components.has(StrokeMeshDirty.self))

        let stroke = BezierStroke(data: makeData())
        stroke.updateMesh()
        #expect(stroke.root.components.has(StrokeMeshDirty.self))
    }

    @Test func testCanvasStrokesAreDerivedFromEntityTree() throws {
        let canvas = PaintingCanvas()

        canvas.addBezierStroke(BezierStroke(data: makeData()))

        let stroke = try #require(canvas.strokes.first)
        #expect(canvas.strokes.count == 1)
        #expect(stroke.uuid == strokeId)

        canvas.reset()
        #expect(canvas.strokes.isEmpty)
    }

    @Test func testAddedStrokeHasHiddenControlPoints() throws {
        let canvas = PaintingCanvas()

        canvas.addBezierStroke(BezierStroke(data: makeData()))

        let stroke = try #require(canvas.strokes.first)
        let entities: [Entity] = controlPointEntities(of: stroke)
        #expect(entities.count == 2)
        #expect(entities.allSatisfy { !$0.isEnabled })
        #expect(stroke.root.components.has(StrokeColliderDirty.self))
    }

    @Test func testMovingControlPointKeepsEntityAndSyncsPosition() throws {
        let canvas = PaintingCanvas()
        canvas.addBezierStroke(BezierStroke(data: makeData()))
        let stroke = try #require(canvas.strokes.first)
        let pointEntity = try #require(controlPointEntities(of: stroke).first)

        canvas.moveControlPoint(strokeId: strokeId, controlPointId: pointId, controlType: .end, newPosition: [1, 1, 0])

        #expect(controlPointEntities(of: stroke).first === pointEntity)
        #expect(stroke.bezierPoints[0].end == [1, 1, 0])

        let endEntity = try #require(pointEntity.children.first { (entity: Entity) -> Bool in
            return entity.components[BezierStrokeControlComponent.self]?.controlType == .end
        })
        #expect(endEntity.position(relativeTo: nil) == [1, 1, 0])
    }
}
