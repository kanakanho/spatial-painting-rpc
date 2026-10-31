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


@MainActor
@Observable
class BezierStroke {
    var uuid: UUID
    
    var activeColor: SimpleMaterial.Color = SimpleMaterial.Color.red
    
    func setActiveColor(color: SimpleMaterial.Color) {
        activeColor = color
    }
    
    /// ベジェ編集中など、線の内側を見せるために表面をカリングするかどうか
    var isFaceCullingEnabled: Bool = false
    
    /// 現在の色とカリング設定を反映したマテリアルを生成する
    func makeMaterial() -> SimpleMaterial {
        var material = SimpleMaterial(color: activeColor, roughness: 1.0, isMetallic: false)
        if isFaceCullingEnabled {
            material.faceCulling = .front
        }
        return material
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
        self.updateMesh(false)
    }
    
    /// Update the mesh with the points of the stroke if it already exists,
    /// or create a new one with the given mesh data.
    func updateMesh(_ flag: Bool = true) {
        if flag {
            if !bezierPoints.beziers.isEmpty {
                points = beziers2Points(beziers: bezierPoints.beziers, resolution: 16)
            }
        }

        /// The starting point where the stroke mesh begins.
        guard let center = points.first,
              let last = points.last else { return }

        if flag {
            /// 最後の点を追加
            if !bezierPoints.beziers.isEmpty {
                points.append(last)
            }
        }

        /// The position, normals, and triangle indices that the points generate.
        let meshData = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: maxRadius)
        
        /// The `MeshResource.Contents` instance.
        let contents = StrokeMeshBuilder.makeContents(meshData)
        
        // Replace the mesh with `contents` if there is a mesh component on the stroke.
        if let mesh = stroke.model?.mesh {
            do {
                try mesh.replace(with: contents)
                // マテリアルを更新 added by nagao 2025/11/21
                stroke.model?.materials = [makeMaterial()]
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
                materials: [makeMaterial()]
            ))
        }
        
        if flag {
            // Set the stroke's transform and position.
            stroke.setTransformMatrix(.identity, relativeTo: nil)
            stroke.setPosition(center, relativeTo: nil)
        }
    }
    
    func updateMeshEnableFaceCulling() {
        isFaceCullingEnabled = true
        if !bezierPoints.beziers.isEmpty {
            points = beziers2Points(beziers: bezierPoints.beziers, resolution: 8)
        }

        /// The starting point where the stroke mesh begins.
        guard let center = points.first,
              let last = points.last else { return }
        
        
        /// 最後の点を追加
        if !bezierPoints.beziers.isEmpty {
            points.append(last)
        }
        
        /// The position, normals, and triangle indices that the points generate.
        let meshData = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: maxRadius)
        
        /// The `MeshResource.Contents` instance.
        let contents = StrokeMeshBuilder.makeContents(meshData)
        
        /// The new mesh that generates with `content`.
        guard let mesh = try? MeshResource.generate(from: contents) else {
            print("Error generating mesh")
            return
        }
        
        // Set the model component to the new mesh, and assign a simple material.
        stroke.components.set(ModelComponent(
            mesh: mesh,
            materials: [makeMaterial()]
        ))
        
        // Set the stroke's transform and position.
        stroke.setTransformMatrix(.identity, relativeTo: nil)
        stroke.setPosition(center, relativeTo: nil)
    }
    
    func updateMeshDisableFaceCulling() {
        isFaceCullingEnabled = false
        if !bezierPoints.beziers.isEmpty {
            points = beziers2Points(beziers: bezierPoints.beziers, resolution: 8)
        }

        /// The starting point where the stroke mesh begins.
        guard let center = points.first,
              let last = points.last else { return }
        
        
        /// 最後の点を追加
        if !bezierPoints.beziers.isEmpty {
            points.append(last)
        }
        
        /// The position, normals, and triangle indices that the points generate.
        let meshData = StrokeMeshBuilder.makeMeshData(points: points, maxRadius: maxRadius)
        
        /// The `MeshResource.Contents` instance.
        let contents = StrokeMeshBuilder.makeContents(meshData)
        
        /// The new mesh that generates with `content`.
        guard let mesh = try? MeshResource.generate(from: contents) else {
            print("Error generating mesh")
            return
        }
        
        // Set the model component to the new mesh, and assign a simple material.
        stroke.components.set(ModelComponent(
            mesh: mesh,
            materials: [makeMaterial()]
        ))
        
        // Set the stroke's transform and position.
        stroke.setTransformMatrix(.identity, relativeTo: nil)
        stroke.setPosition(center, relativeTo: nil)
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
    
    /// 通信・ファイル保存用のデータから生成する
    convenience init(data: BezierStrokeData) {
        self.init(uuid: data.uuid, points: data.points, color: data.color.uiColor, maxRadius: data.maxRadius)
        self.bezierPoints = data.bezierPoints.map { BezierPoint(data: $0) }
    }
    
    /// 通信・ファイル保存用のデータ
    var data: BezierStrokeData {
        BezierStrokeData(
            uuid: uuid,
            points: points,
            color: .init(activeColor),
            maxRadius: maxRadius,
            bezierPoints: bezierPoints.map(\.data)
        )
    }
    
    /// 座標変換を適用した送信用のデータ
    ///
    /// - Note: `points` には root の transform とアフィン変換を、`bezierPoints` にはアフィン変換のみを適用する
    /// - Parameter affine: 送信先の座標系へのアフィン行列
    func transferData(affine: simd_float4x4) -> BezierStrokeData {
        let rootMatrix = root.transformMatrix(relativeTo: nil)
        var data = self.data
        data.points = points.map { matmul4x4_4x1(affine, rootMatrix * SIMD4<Float>($0, 1.0)) }
        data.bezierPoints = data.bezierPoints.map { $0.applying(affine) }
        return data
    }
}

extension BezierStrokeData.ColorComponents {
    init(_ color: UIColor) {
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        self = .hsba(SIMD4<Float>(Float(hue), Float(saturation), Float(brightness), Float(alpha)))
    }
    
    var uiColor: UIColor {
        switch self {
        case .hsba(let c):
            return UIColor(hue: CGFloat(c.x), saturation: CGFloat(c.y), brightness: CGFloat(c.z), alpha: CGFloat(c.w))
        case .rgba(let c):
            return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(c.w))
        }
    }
}
