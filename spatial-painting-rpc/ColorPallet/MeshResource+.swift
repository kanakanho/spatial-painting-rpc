//
//  MeshResource+.swift
//  sample
//
//  Created by blueken on 2025/09/25.
//

import RealityKit
import Foundation

extension MeshResource {
    static func generateBox(vertices: [SIMD3<Float>], indices: [UInt32]) -> MeshResource {
        var meshDescriptor = MeshDescriptor(name: "CustomBox")
        meshDescriptor.positions = MeshBuffers.Positions(vertices)
        meshDescriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [meshDescriptor])
    }
    
    static func generateBox(corner: BoundingBoxCube) throws -> MeshResource {
        // 8個の頂点からなる立方体のメッシュを生成
        let vertices: [SIMD3<Float>] = [
            corner.corners[.minXMinYMinZ]!,
            corner.corners[.maxXMinYMinZ]!,
            corner.corners[.minXMaxYMinZ]!,
            corner.corners[.maxXMaxYMinZ]!,
            corner.corners[.minXMinYMaxZ]!,
            corner.corners[.maxXMinYMaxZ]!,
            corner.corners[.minXMaxYMaxZ]!,
            corner.corners[.maxXMaxYMaxZ]!
        ]
        let indices: [UInt32] = [
            0, 1, 2, 2, 1, 3,
            4, 5, 6, 6, 5, 7,
            0, 1, 4, 4, 1, 5,
            2, 3, 6, 6, 3, 7,
            0, 2, 4, 4, 2, 6,
            1, 3, 5, 5, 3, 7
        ]
        var meshDescriptor = MeshDescriptor(name: "CustomBox")
        meshDescriptor.positions = MeshBuffers.Positions(vertices)
        meshDescriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [meshDescriptor]) {
            return mesh
        } else {
            throw NSError(domain: "MeshGenerationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate mesh from descriptor"])
        }
    }
    
    static func generateBox(corner: BoundingBoxCube) -> MeshDescriptor {
        // 8個の頂点からなる立方体のメッシュを生成
        let vertices: [SIMD3<Float>] = [
            corner.corners[.minXMinYMinZ]!,
            corner.corners[.maxXMinYMinZ]!,
            corner.corners[.minXMaxYMinZ]!,
            corner.corners[.maxXMaxYMinZ]!,
            corner.corners[.minXMinYMaxZ]!,
            corner.corners[.maxXMinYMaxZ]!,
            corner.corners[.minXMaxYMaxZ]!,
            corner.corners[.maxXMaxYMaxZ]!
        ]
        let indices: [UInt32] = [
            0, 1, 2, 2, 1, 3,
            4, 5, 6, 6, 5, 7,
            0, 1, 4, 4, 1, 5,
            2, 3, 6, 6, 3, 7,
            0, 2, 4, 4, 2, 6,
            1, 3, 5, 5, 3, 7
        ]
        var meshDescriptor = MeshDescriptor(name: "CustomBox")
        meshDescriptor.positions = MeshBuffers.Positions(vertices)
        meshDescriptor.primitives = .triangles(indices)
        return meshDescriptor
    }
}
