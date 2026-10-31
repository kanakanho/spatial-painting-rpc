//
//  StrokeMeshBuilderTests.swift
//  spatial-painting-rpcTests
//

import Testing
import simd
@testable import spatial_painting_rpc

struct StrokeMeshBuilderTests {
    private let points: [SIMD3<Float>] = [
        SIMD3<Float>(0, 0, 0),
        SIMD3<Float>(0.01, 0, 0),
        SIMD3<Float>(0.02, 0, 0),
        SIMD3<Float>(0.03, 0, 0)
    ]
    private let pointsPerRing = 4

    @Test func testVertexAndIndexCounts() {
        let data = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: 0.01, pointsPerRing: pointsPerRing)

        #expect(data.positions.count == points.count * pointsPerRing)
        #expect(data.normals.count == points.count * pointsPerRing)
        #expect(data.triangles.count == (points.count - 1) * pointsPerRing * 6)
    }

    @Test func testTriangleIndicesAreInRange() {
        let data = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: 0.01, pointsPerRing: pointsPerRing)

        #expect(data.triangles.allSatisfy { Int($0) < data.positions.count })
    }

    @Test func testBothEndsHaveZeroRadius() {
        let data = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: 0.01, pointsPerRing: pointsPerRing)

        let firstRing = data.positions[0..<pointsPerRing]
        let lastRing = data.positions[(data.positions.count - pointsPerRing)...]

        #expect(firstRing.allSatisfy { distance($0, .zero) < 1E-6 })
        #expect(lastRing.allSatisfy { distance($0, points[3] - points[0]) < 1E-6 })
    }

    @Test func testInnerRingHasRadius() {
        let maxRadius: Float = 0.01
        let data = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: maxRadius, pointsPerRing: pointsPerRing)

        let secondRing = data.positions[pointsPerRing..<(pointsPerRing * 2)]

        #expect(secondRing.allSatisfy { abs(distance($0, points[1] - points[0]) - maxRadius) < 1E-6 })
    }

    @Test func testNormalsAreUnitLength() {
        let data = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: 0.01, pointsPerRing: pointsPerRing)

        #expect(data.normals.allSatisfy { abs(length($0) - 1) < 1E-5 })
    }

    @Test func testEmptyPoints() {
        let data = StrokeMeshBuilder.makeMeshData(points: [], maxRadius: 0.01, pointsPerRing: pointsPerRing)

        #expect(data.positions.isEmpty)
        #expect(data.normals.isEmpty)
        #expect(data.triangles.isEmpty)
    }
}
