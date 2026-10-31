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

struct StrokeRootComponent: Component {
    var uuid: UUID
    
    init(_ uuid: UUID) {
        self.uuid = uuid
    }
}


/// ストロークの Entity の操作をまとめたラッパー
///
/// - Note: データの実体は `StrokeGeometry` と Component にある。
///   Phase 3 までの移行措置で、呼び出し元が Component を直接扱うようになったら削除する
@MainActor
final class BezierStroke {
    let uuid: UUID
    
    /// The stroke that represents the stroke.
    let root: Entity
    let stroke: Entity
    
    let geometry: StrokeGeometry
    
    var activeColor: SimpleMaterial.Color {
        get { style.color }
        set { style.color = newValue }
    }
    
    func setActiveColor(color: SimpleMaterial.Color) {
        activeColor = color
    }
    
    /// ベジェ編集中など、線の内側を見せるために表面をカリングするかどうか
    var isFaceCullingEnabled: Bool {
        get { style.isFaceCullingEnabled }
        set { style.isFaceCullingEnabled = newValue }
    }
    
    /// The collection of points in 3D space that represent the stroke.
    var points: [SIMD3<Float>] {
        get { geometry.points }
        set { geometry.points = newValue }
    }
    
    /// The maximum radius of the stroke.
    var maxRadius: Float {
        get { style.maxRadius }
        set { style.maxRadius = newValue }
    }
    
    func setMaxRadius(radius: Float) {
        maxRadius = radius
    }
    
    var bezierPoints: [BezierPointData] {
        get { geometry.bezierPoints }
        set { geometry.bezierPoints = newValue }
    }
    
    /// 元の maxRadius を保持するプロパティを追加（初期値 1E-2）
    var originalMaxRadius: Float {
        return 1E-2
    }
    
    private var style: StrokeStyleComponent {
        get { root.components[StrokeStyleComponent.self]! }
        set { root.components.set(newValue) }
    }
    
    init(uuid: UUID, points: [SIMD3<Float>], color: SimpleMaterial.Color, maxRadius: Float) {
        self.uuid = uuid
        self.root = Entity()
        self.stroke = Entity()
        self.geometry = StrokeGeometry(points: points)
        stroke.components.set(StrokeMeshComponent())
        root.components.set(StrokeComponent(id: uuid, geometry: geometry))
        root.components.set(StrokeStyleComponent(color: color, maxRadius: maxRadius))
        root.components.set(StrokeRootComponent(uuid))
        root.addChild(stroke)
    }
    
    convenience init(uuid: UUID, originalMaxRadius: Float = 1E-2) {
        self.init(uuid: uuid, points: [], color: .red, maxRadius: originalMaxRadius)
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
    
    /// メッシュの再生成を `StrokeMeshSystem` に依頼する
    ///
    /// - Note: `flag` が true のときは `points` の再サンプリングとメッシュの Transform の設定まで同期的に行う。
    ///   呼び出し元が直後に `points` を読んだり、親を付け替えたりするため
    func updateMesh(_ flag: Bool = true) {
        if flag {
            geometry.resamplePoints()
        }

        /// The starting point where the stroke mesh begins.
        guard let center = points.first else { return }

        root.components.set(StrokeMeshDirty())

        if flag {
            // Set the stroke's transform and position.
            stroke.setTransformMatrix(.identity, relativeTo: nil)
            stroke.setPosition(center, relativeTo: nil)
        }
    }
    
    /// 制御点の Entity 群
    private var controlPointEntities: [Entity] {
        root.children.filter { (entity: Entity) -> Bool in
            return entity.components.has(BezierPointComponent.self)
        }
    }
    
    /// 制御点の Entity 群の表示を切り替える
    func setControlPointsEnabled(_ isEnabled: Bool) {
        for entity: Entity in controlPointEntities {
            entity.isEnabled = isEnabled
        }
    }
    
    /// `bezierPoints` から制御点の Entity 群を作り直す
    ///
    /// - Note: 作り直すと選択中の Entity が失われるので、編集中は `moveControlPoint` を使う
    func rebuildControlPoints(endPoint: Entity, handle: Entity) {
        for entity: Entity in controlPointEntities {
            entity.removeFromParent()
        }
        for point: BezierPointData in bezierPoints {
            let entity: Entity = BezierControlPointFactory.make(data: point, endPoint: endPoint, handle: handle)
            entity.isEnabled = false
            root.addChild(entity)
        }
    }
    
    /// 制御点を移動して Entity の位置を同期する
    func moveControlPoint(pointId: UUID, to position: SIMD3<Float>, pn: BezierPointType) {
        guard let index: Int = bezierPoints.firstIndex(where: { $0.uuid == pointId }) else { return }
        
        geometry.bezierPoints[index].add(point: position, pn: pn)
        
        let entity: Entity? = controlPointEntities.first { (entity: Entity) -> Bool in
            return entity.components[BezierPointComponent.self]?.pointId == pointId
        }
        if let entity: Entity {
            BezierControlPointFactory.sync(entity, with: geometry.bezierPoints[index])
        }
    }
    
    /// ベジェ編集中など、線の内側を見せるためのカリングを切り替える
    func setFaceCulling(_ isEnabled: Bool) {
        isFaceCullingEnabled = isEnabled
        updateMesh()
    }
    
    /// 通信・ファイル保存用のデータから生成する
    convenience init(data: BezierStrokeData) {
        self.init(uuid: data.uuid, points: data.points, color: data.color.uiColor, maxRadius: data.maxRadius)
        self.bezierPoints = data.bezierPoints
    }
    
    /// 通信・ファイル保存用のデータ
    var data: BezierStrokeData {
        BezierStrokeData(
            uuid: uuid,
            points: points,
            color: .init(activeColor),
            maxRadius: maxRadius,
            bezierPoints: bezierPoints
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
