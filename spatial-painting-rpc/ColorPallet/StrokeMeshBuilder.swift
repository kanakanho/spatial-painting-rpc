//
//  StrokeMeshBuilder.swift
//  spatial-painting-rpc
//

import RealityKit
import simd

/// ストロークのメッシュの頂点データ
struct StrokeMeshData {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var triangles: [UInt32]
}

/// ストロークの点列からメッシュを生成する
///
/// - Note: Entity に依存しないため、メインスレッド以外やテストからも呼び出せる
enum StrokeMeshBuilder {
    /// Generate the mesh data with the given points.
    static func makeMeshData(points: [SIMD3<Float>], maxRadius: Float, pointsPerRing: Int = 4) -> StrokeMeshData {
        /// The array to store vertex positions.
        var positions: [SIMD3<Float>] = []

        /// The array to store normal vectors.
        var normals: [SIMD3<Float>] = []

        /// The array to store triangle indices.
        var triangles: [UInt32] = []

        // Iterates through the points to create a path for the mesh.
        for pointIdx in 0..<points.count {
            /// The radius and direction for the current point.
            let (radius, direction) = calculateRadiusAndDirection(points: points, maxRadius: maxRadius, at: pointIdx)

            /// The x and y axes for the current point.
            let (xAxis, yAxis) = calculateAxes(direction: direction)

            // Generate points around the current stroke point.
            for point in 0..<pointsPerRing {
                /// The position and normal for the current point in the ring.
                let (position, normal) = calculatePositionAndNormal(
                    points: points, pointsPerRing: pointsPerRing, pointI: pointIdx, point: point, radius: radius, xAxis: xAxis, yAxis: yAxis
                )

                // Attach the position to the positions collection.
                positions.append(position)

                // Attach the normal to the normals collection.
                normals.append(normal)

                // Generate a mesh between each point.
                if pointIdx + 1 < points.count {
                    appendTriangles(pointsPerRing: pointsPerRing, pointIdx: pointIdx, point: point, triangles: &triangles)
                }
            }
        }

        return StrokeMeshData(positions: positions, normals: normals, triangles: triangles)
    }

    /// Create the `MeshResource.Contents` instance from the mesh data.
    static func makeContents(_ data: StrokeMeshData) -> MeshResource.Contents {
        /// The `MeshResource.Contents` instance.
        var contents = MeshResource.Contents()

        // Create and assign an instance to `contents`.
        contents.instances = [MeshResource.Instance(id: "main", model: "model")]

        // Create the part for the model, and set the vertex positions, triangle indices, and normals.
        var part = MeshResource.Part(id: "part", materialIndex: 0)
        part.positions = MeshBuffer(data.positions)
        part.triangleIndices = MeshBuffer(data.triangles)
        part.normals = MeshBuffer(data.normals)

        // Create and assign a model that consists of the `part`.
        contents.models = [MeshResource.Model(id: "model", parts: [part])]
        return contents
    }

    // MARK: Helper functions

    /// Calculate the radius and direction from a given point index.
    private static func calculateRadiusAndDirection(points: [SIMD3<Float>], maxRadius: Float, at index: Int) -> (Float, SIMD3<Float>) {
        // End the stroke if there are no points.
        if index == 0 || (index + 1 == points.count) {
            // For the first and last points, use zero radius and default direction.
            return (0, SIMD3<Float>(1, 0, 0))
        } else {
            /// The difference between the current point and the previous point.
            let diff = points[index] - points[index - 1]

            /// The radius calculated from the difference.
            let radius = maxRadius * powf(clamp(Float(maxRadius / length(diff)), min: Float(0), max: Float(1)), 0.3)

            return (radius, normalize(diff))
        }
    }

    /// Calculate the x and y axes with the given direction.
    private static func calculateAxes(direction: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        /// The cross product of the direction and the y-axis that normalizes.
        let xAxis = normalize(cross(direction, SIMD3<Float>(0, 1, 0)))

        /// The cross product of the direction and `xAxis` value that normalizes.
        let yAxis = normalize(cross(direction, xAxis))

        return (xAxis, yAxis)
    }

    /// Calculate the position and normal for a point in the ring around a stroke point.
    private static func calculatePositionAndNormal(
        points: [SIMD3<Float>], pointsPerRing: Int, pointI: Int, point: Int, radius: Float, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
            /// The angle is the product of two times pi, then divide the total points per ring.
            let angle: Float = 2 * .pi * Float(point) / Float(pointsPerRing)

            /// The current normal value from the angle.
            let normal: SIMD3<Float> = cos(angle) * xAxis + sin(angle) * yAxis

            /// The location of the current point with its distance from the center point.
            let position: SIMD3<Float> = (points[pointI] - points[0]) + radius * normal

            return (position, normal)
        }

    /// Add triangle indices for the current point in the mesh.
    private static func appendTriangles(pointsPerRing: Int, pointIdx: Int, point: Int, triangles: inout [UInt32]) {
        let first: UInt32 = UInt32(pointsPerRing * (pointIdx) + (point) % pointsPerRing)
        let second: UInt32 = UInt32(pointsPerRing * (pointIdx + 1) + (point) % pointsPerRing)
        let third: UInt32 = UInt32(pointsPerRing * (pointIdx) + (point + 1) % pointsPerRing)
        let fourth: UInt32 = UInt32(pointsPerRing * (pointIdx + 1) + (point + 1) % pointsPerRing)
        let quadIndices: [UInt32] = [first, second, third, fourth]

        // Add the contents of the fourth, first, and third entry from the
        // `quadIndices` array to the `triangles` collection.
        triangles.append(contentsOf: [quadIndices[3], quadIndices[0], quadIndices[2]])

        // Add the contents of the fourth, second, and first entry from the
        // `quadIndices` array to the `trinagles` collection.
        triangles.append(contentsOf: [quadIndices[3], quadIndices[1], quadIndices[0]])
    }
}
