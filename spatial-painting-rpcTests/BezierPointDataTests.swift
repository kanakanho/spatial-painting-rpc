//
//  BezierPointDataTests.swift
//  spatial-painting-rpcTests
//

import Foundation
import Testing
@testable import spatial_painting_rpc

struct BezierPointDataTests {
    private func makePoint(
        end: SIMD3<Float>? = nil,
        startControl: SIMD3<Float>? = nil,
        endControl: SIMD3<Float>? = nil
    ) -> BezierPointData {
        BezierPointData(uuid: UUID(), strokeId: UUID(), end: end, startControl: startControl, endControl: endControl)
    }

    @Test func testAddEndToEmptyPoint() {
        var point = makePoint()

        point.add(point: [1, 2, 3], pn: .end)

        #expect(point.end == [1, 2, 3])
    }

    @Test func testAddControlIsIgnoredBeforeEnd() {
        var point = makePoint()

        point.add(point: [1, 0, 0], pn: .endControl)
        point.add(point: [1, 0, 0], pn: .startControl)

        #expect(point.end == nil)
        #expect(point.startControl == nil)
        #expect(point.endControl == nil)
    }

    @Test func testMovingEndMovesBothHandles() {
        var point = makePoint(end: [0, 0, 0], startControl: [-1, 0, 0], endControl: [1, 0, 0])

        point.add(point: [1, 1, 0], pn: .end)

        #expect(point.end == [1, 1, 0])
        #expect(point.startControl == [0, 1, 0])
        #expect(point.endControl == [2, 1, 0])
    }

    @Test func testMovingEndControlMirrorsStartControl() {
        var point = makePoint(end: [1, 0, 0], startControl: [0, 0, 0], endControl: [2, 0, 0])

        point.add(point: [1, 2, 0], pn: .endControl)

        #expect(point.endControl == [1, 2, 0])
        #expect(point.startControl == [1, -2, 0])
    }

    @Test func testMovingStartControlMirrorsEndControl() {
        var point = makePoint(end: [1, 0, 0], startControl: [0, 0, 0], endControl: [2, 0, 0])

        point.add(point: [1, 2, 0], pn: .startControl)

        #expect(point.startControl == [1, 2, 0])
        #expect(point.endControl == [1, -2, 0])
    }

    @Test func testBeziersOrder() {
        let first = makePoint(end: [0, 0, 0], endControl: [1, 0, 0])
        let second = makePoint(end: [3, 0, 0], startControl: [2, 0, 0])

        #expect([first, second].beziers == [[[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0]]])
    }

    @Test func testBeziersSkipIncompleteSegment() {
        let first = makePoint(end: [0, 0, 0])
        let second = makePoint(end: [3, 0, 0], startControl: [2, 0, 0])

        #expect([first, second].beziers.isEmpty)
        #expect([first].beziers.isEmpty)
    }
}
