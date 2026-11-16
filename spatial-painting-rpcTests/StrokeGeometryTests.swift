//
//  StrokeGeometryTests.swift
//  spatial-painting-rpcTests
//

import Foundation
import Testing
@testable import spatial_painting_rpc

@MainActor
struct StrokeGeometryTests {
    private let strokeId = UUID()

    private func makeBezierPoints() -> [BezierPointData] {
        [
            BezierPointData(uuid: UUID(), strokeId: strokeId, end: [0, 0, 0], endControl: [1, 0, 0]),
            BezierPointData(uuid: UUID(), strokeId: strokeId, end: [3, 0, 0], startControl: [2, 0, 0])
        ]
    }

    @Test func testResampleWithoutBezierKeepsPoints() {
        let geometry = StrokeGeometry(points: [[0, 0, 0], [1, 0, 0]])

        geometry.resamplePoints()

        #expect(geometry.points == [[0, 0, 0], [1, 0, 0]])
    }

    @Test func testResampleDuplicatesLastPoint() throws {
        let geometry = StrokeGeometry(points: [[9, 9, 9]], bezierPoints: makeBezierPoints())

        geometry.resamplePoints()

        let last = try #require(geometry.points.last)
        #expect(geometry.points.count > 2)
        #expect(geometry.points[geometry.points.count - 2] == last)
        #expect(geometry.points.first == [0, 0, 0])
    }

    @Test func testResampleIsRepeatable() {
        let geometry = StrokeGeometry(bezierPoints: makeBezierPoints())

        geometry.resamplePoints()
        let first = geometry.points
        geometry.resamplePoints()

        #expect(geometry.points == first)
    }
}

struct BezierSegmentConversionTests {
    private let strokeId = UUID()

    @Test func testSegmentsBecomePointsWithMirroredHandles() {
        let segments: [[SIMD3<Float>]] = [
            [[0, 0, 0], [1, 0, 0], [2, 1, 0], [3, 0, 0]],
            [[3, 0, 0], [4, -1, 0], [5, 1, 0], [6, 0, 0]],
            [[6, 0, 0], [7, -1, 0], [8, 1, 0], [9, 0, 0]]
        ]

        let points = segments.toBezierPointData(strokeId: strokeId)

        // 始点 + セグメントごとの終点
        #expect(points.count == segments.count + 1)
        #expect(points.allSatisfy { $0.strokeId == strokeId })

        #expect(points[0].end == [0, 0, 0])
        #expect(points[0].endControl == [1, 0, 0])
        #expect(points[0].startControl == [-1, 0, 0])

        #expect(points[1].end == [3, 0, 0])
        #expect(points[1].startControl == [2, 1, 0])
        #expect(points[1].endControl == [4, -1, 0])
    }

    @Test func testTooFewSegmentsBecomeEmpty() {
        let segments: [[SIMD3<Float>]] = [
            [[0, 0, 0], [1, 0, 0], [2, 1, 0], [3, 0, 0]],
            [[3, 0, 0], [4, -1, 0], [5, 1, 0], [6, 0, 0]]
        ]

        #expect(segments.toBezierPointData(strokeId: strokeId).isEmpty)
    }
}
