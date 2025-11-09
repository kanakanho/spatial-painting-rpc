//
//  BezierStroke.swift
//  sample
//
//  Created by blueken on 2025/09/30.
//

import Foundation
import SwiftUI
import RealityKit
import simd

struct StrokeComponent: Component {
    var uuid: UUID
    
    init(_ uuid: UUID) {
        self.uuid = uuid
    }
}

struct StrokeRootComponent: Component {
    var uuid: UUID
    
    init(_ uuid: UUID) {
        self.uuid = uuid
    }
}


@Observable
class BezierStroke: Codable {
    var uuid: UUID
    
    var activeColor: SimpleMaterial.Color = SimpleMaterial.Color.red
    
    func setActiveColor(color: SimpleMaterial.Color) {
        activeColor = color
    }
    
    /// The stroke that represents the stroke.
    var root = Entity()
    var stroke = Entity()
    
    /// The collection of points in 3D space that represent the stroke.
    var points: [SIMD3<Float>] = []
    
    /// The maximum radius of the stroke.
    var maxRadius: Float = 1E-2
    
    func setMaxRadius(radius: Float) {
        maxRadius = radius
    }
    
    var tmpBezier: BezierPoint
    
    var bezierPoints: [BezierPoint] = []
    
    /// 元の maxRadius を保持するプロパティを追加（初期値 1E-2）
    var originalMaxRadius: Float {
        return 1E-2
    }
    
    /// The number of points in each ring of the mesh.
    let pointsPerRing = 4
    
    init(uuid: UUID, originalMaxRadius: Float = 1E-2) {
        self.uuid = uuid
        self.maxRadius = originalMaxRadius
        self.tmpBezier = BezierPoint(strokeId: uuid)
        stroke.components.set(StrokeComponent(uuid))
        root.components.set(StrokeRootComponent(uuid))
        root.addChild(stroke)
    }
    
    //修正 by nagao 2025/7/15
    func updateMaxRadiusAndRemesh(scaleFactor: Float) {
        //self.maxRadius = self.originalMaxRadius * scaleFactor
        let scaled = self.originalMaxRadius * scaleFactor
        let radiusCap: Float   = 3.0 * self.originalMaxRadius // 上限
        let radiusFloor: Float = 0.3 * self.originalMaxRadius // 下限
        self.maxRadius = min(max(scaled, radiusFloor), radiusCap)
        //print("Stroke maxRadius: \(self.maxRadius)")
        self.updateMesh()
    }
    
    /// Update the mesh with the points of the stroke if it already exists,
    /// or create a new one with the given mesh data.
    func updateMesh() {
        if !bezierPoints.beziers.isEmpty {
            points = beziers2Points(beziers: bezierPoints.beziers, resolution: 16)
        }

        /// The starting point where the stroke mesh begins.
        guard let center = points.first,
              let last = points.last else { return }
        
        
        /// 最後の点を追加
        if !bezierPoints.beziers.isEmpty {
            points.append(last)
        }
        
        /// The position, normals, and triangle indices that the points generate.
        let (positions, normals, triangles) = generateMeshData()
        
        /// The `MeshResource.Contents` instance.
        var contents = MeshResource.Contents()
        
        // Create and assign an instance to `contents`.
        contents.instances = [MeshResource.Instance(id: "main", model: "model")]
        
        // Create the part for the model, and set the vertex positions, triangle indices, and normals.
        var part = MeshResource.Part(id: "part", materialIndex: 0)
        part.positions = MeshBuffer(positions)
        part.triangleIndices = MeshBuffer(triangles)
        part.normals = MeshBuffer(normals)
        
        // Create and assign a model that consists of the `part`.
        contents.models = [MeshResource.Model(id: "model", parts: [part])]
        
        // Replace the mesh with `contents` if there is a mesh component on the stroke.
        if let mesh = stroke.model?.mesh {
            do {
                try mesh.replace(with: contents)
            } catch {
                print("Error replacing mesh: \(error.localizedDescription)")
            }
        } else {
            /// The new mesh that generates with `content`.
            guard let mesh = try? MeshResource.generate(from: contents) else {
                print("Error generating mesh")
                return
            }
            
            // Set the model component to the new mesh, and assign a simple material.
            stroke.components.set(ModelComponent(
                mesh: mesh,
                materials: [SimpleMaterial(color: activeColor, roughness: 1.0, isMetallic: false)]
            ))
        }
        
        // Set the stroke's transform and position.
        stroke.setTransformMatrix(.identity, relativeTo: nil)
        stroke.setPosition(center, relativeTo: nil)
    }
            
    func points2MeshContents(poitns: [SIMD3<Float>]) -> MeshResource.Contents {
        /// The position, normals, and triangle indices that the points generate.
        let (positions, normals, triangles) = generateMeshData()
        
        /// The `MeshResource.Contents` instance.
        var contents = MeshResource.Contents()
        
        // Create and assign an instance to `contents`.
        contents.instances = [MeshResource.Instance(id: "main", model: "model")]
        
        // Create the part for the model, and set the vertex positions, triangle indices, and normals.
        var part = MeshResource.Part(id: "part", materialIndex: 0)
        part.positions = MeshBuffer(positions)
        part.triangleIndices = MeshBuffer(triangles)
        part.normals = MeshBuffer(normals)
        
        // Create and assign a model that consists of the `part`.
        contents.models = [MeshResource.Model(id: "model", parts: [part])]
        return contents
    }
    
    ///
    func finishRemesh() {
        bezierPoints = points2Beziers(strokeId: uuid, points: points)
        updateMesh()
    }
    
    // MARK: Helper functions
    
    /// Generate the mesh data with the current points.
    private func generateMeshData() -> ([SIMD3<Float>], [SIMD3<Float>], [UInt32]) {
        /// The array to store vertex positions.
        var positions: [SIMD3<Float>] = []
        
        /// The array to store normal vectors.
        var normals: [SIMD3<Float>] = []
        
        /// The array to store triangle indices.
        var triangles: [UInt32] = []
        
        // Iterates through the points to create a path for the mesh.
        for pointIdx in 0..<points.count {
            /// The radius and direction for the current point.
            let (radius, direction) = calculateRadiusAndDirection(at: pointIdx)
            
            /// The x and y axes for the current point.
            let (xAxis, yAxis) = calculateAxes(direction: direction)
            
            // Generate points around the current stroke point.
            for point in 0..<pointsPerRing {
                /// The position and normal for the current point in the ring.
                let (position, normal) = calculatePositionAndNormal(pointI: pointIdx, point: point, radius: radius, xAxis: xAxis, yAxis: yAxis)
                
                // Attach the position to the positions collection.
                positions.append(position)
                
                // Attach the normal to the normals collection.
                normals.append(normal)
                
                // Generate a mesh between each point.
                if pointIdx + 1 < points.count {
                    appendTriangles(pointIdx: pointIdx, point: point, triangles: &triangles)
                }
            }
        }
        
        return (positions, normals, triangles)
    }
    
    /// Calculate the radius and direction from a given point index.
    private func calculateRadiusAndDirection(at index: Int) -> (Float, SIMD3<Float>) {
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
    private func calculateAxes(direction: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        /// The cross product of the direction and the y-axis that normalizes.
        let xAxis = normalize(cross(direction, SIMD3<Float>(0, 1, 0)))
        
        /// The cross product of the direction and `xAxis` value that normalizes.
        let yAxis = normalize(cross(direction, xAxis))
        
        return (xAxis, yAxis)
    }
    
    /// Calculate the position and normal for a point in the ring around a stroke point.
    private func calculatePositionAndNormal(
        pointI: Int, point: Int, radius: Float, xAxis: SIMD3<Float>, yAxis: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
            /// The angle is the product of two times pi, then divide the total points per ring.
            let angle = 2 * .pi * Float(point) / Float(pointsPerRing)
            
            /// The current normal value from the angle.
            let normal = cos(angle) * xAxis + sin(angle) * yAxis
            
            /// The location of the current point with its distance from the center point.
            let position = (points[pointI] - points[0]) + radius * normal
            
            return (position, normal)
        }
    
    /// Add triangle indices for the current point in the mesh.
    private func appendTriangles(pointIdx: Int, point: Int, triangles: inout [UInt32]) {
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
    
    enum CodingKeys: String, CodingKey {
        case points
        case activeColor
        case maxRadius
    }
    
    // pointを変更しない
    public init(uuid: UUID, points: [SIMD3<Float>] = [], color: SimpleMaterial.Color = .white, maxRadius: Float = 1E-2) {
        self.uuid = uuid
        self.tmpBezier = BezierPoint(strokeId: uuid)
        self.points = points
        self.activeColor = color
        self.maxRadius = maxRadius
        stroke.components.set(StrokeComponent(uuid))
        root.components.set(StrokeRootComponent(uuid))
        root.addChild(stroke)
    }
    
    public init(uuid: UUID, points: [SIMD3<Float>] = [], color: CGColor = .init(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0), maxRadius: Float = 1E-2) {
        self.uuid = uuid
        self.tmpBezier = BezierPoint(strokeId: uuid)
        self.points = points
        self.activeColor = .init(cgColor: color)
        self.maxRadius = maxRadius
        stroke.components.set(StrokeComponent(uuid))
        root.components.set(StrokeRootComponent(uuid))
        root.addChild(stroke)
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pointArrays = try container.decode([[Float]].self, forKey: .points)
        self.points = pointArrays.map { SIMD3<Float>($0) }
        
        // maxRadius の有無を確認
        let hasMaxRadius = container.contains(.maxRadius)
        let colorArray = try container.decode([Float].self, forKey: .activeColor)
        guard colorArray.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: .activeColor, in: container, debugDescription: "Color array must have 4 elements")
        }
        
        if hasMaxRadius {
            // HSVA（Hue, Saturation, Value, Alpha）
            self.activeColor = .init(hue: CGFloat(colorArray[0]), saturation: CGFloat(colorArray[1]), brightness: CGFloat(colorArray[2]), alpha: CGFloat(colorArray[3]))
        } else {
            // RGBA（Red, Green, Blue, Alpha）
            self.activeColor = .init(red: CGFloat(colorArray[0]), green: CGFloat(colorArray[1]), blue: CGFloat(colorArray[2]), alpha: CGFloat(colorArray[3]))
        }
        
        self.maxRadius = try container.decodeIfPresent(Float.self, forKey: .maxRadius) ?? 1E-2
        let uuid = UUID()
        self.uuid = uuid
        self.tmpBezier = BezierPoint(strokeId: uuid)
        stroke.components.set(StrokeComponent(uuid))
        root.components.set(StrokeRootComponent(uuid))
        root.addChild(stroke)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let pointArrays = points.map { [$0.x, $0.y, $0.z] }
        try container.encode(pointArrays, forKey: .points)
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        activeColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        try container.encode([hue, saturation, brightness, alpha], forKey: .activeColor)
        try container.encode(maxRadius, forKey: .maxRadius)
    }
}

