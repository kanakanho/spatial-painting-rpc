//
//  BezierControlPointFactory.swift
//  spatial-painting-rpc
//

import Foundation
import RealityKit
import simd

struct BezierStrokeControlComponent: Component {
    let bezierStrokeId: UUID
    let bezierPointId: UUID
    let controlType: BezierPointType

    init(bezierStrokeId: UUID, bezierPointId: UUID, controlType: BezierPointType) {
        self.bezierStrokeId = bezierStrokeId
        self.bezierPointId = bezierPointId
        self.controlType = controlType
    }
}

/// ベジェの制御点を操作するための Entity 群を生成する
@MainActor
enum BezierControlPointFactory {
    private static let controlEntitySize: Float = 0.001
    private static let controlEntityMaterial = UnlitMaterial(color: .blue)

    /// 制御点の Entity 群を生成する
    ///
    /// - Parameters:
    ///   - data: 制御点のデータ
    ///   - endPoint: アンカーのプロトタイプ
    ///   - handle: ハンドルのプロトタイプ
    /// - Returns: `BezierPointComponent` を持つ親の Entity
    static func make(data: BezierPointData, endPoint: Entity, handle: Entity) -> Entity {
        let root = Entity()
        root.components.set(BezierPointComponent(pointId: data.uuid))

        let lineEntity = ModelEntity(mesh: .generateBox(size: controlEntitySize), materials: [controlEntityMaterial])
        lineEntity.components.set(BezierControlLineComponent())

        let endEntity: Entity = endPoint.clone(recursive: true)
        let startHandleEntity: Entity = handle.clone(recursive: true)
        let endHandleEntity: Entity = handle.clone(recursive: true)

        setControl(endEntity, data: data, controlType: .end)
        setControl(startHandleEntity, data: data, controlType: .startControl)
        setControl(endHandleEntity, data: data, controlType: .endControl)

        root.addChild(endEntity)
        root.addChild(lineEntity)
        root.addChild(startHandleEntity)
        root.addChild(endHandleEntity)

        sync(root, with: data)
        return root
    }

    /// 制御点の Entity 群の位置をデータに合わせる
    static func sync(_ root: Entity, with data: BezierPointData) {
        for child: Entity in root.children {
            if let control: BezierStrokeControlComponent = child.components[BezierStrokeControlComponent.self] {
                if let position: SIMD3<Float> = position(of: control.controlType, in: data) {
                    child.setPosition(position, relativeTo: nil)
                }
            } else if child.components.has(BezierControlLineComponent.self) {
                syncLine(child, with: data)
            }
        }
    }

    private static func setControl(_ entity: Entity, data: BezierPointData, controlType: BezierPointType) {
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.components.set(BezierStrokeControlComponent(bezierStrokeId: data.strokeId, bezierPointId: data.uuid, controlType: controlType))
    }

    private static func position(of controlType: BezierPointType, in data: BezierPointData) -> SIMD3<Float>? {
        switch controlType {
        case .end:
            return data.end
        case .startControl:
            return data.startControl
        case .endControl:
            return data.endControl
        }
    }

    // 補助用のオブジェクト
    private static func syncLine(_ lineEntity: Entity, with data: BezierPointData) {
        guard let end: SIMD3<Float> = data.end,
              let startControl: SIMD3<Float> = data.startControl,
              let endControl: SIMD3<Float> = data.endControl else { return }

        // 2点間の距離を計算
        let length: Float = simd_distance(end, endControl) * 2.0

        // 距離がほぼ0の場合は、スケールを0にして表示しない（NaNエラーを回避）
        guard length > .ulpOfOne else {
            lineEntity.isEnabled = false
            return
        }
        lineEntity.isEnabled = true

        // 1. Position: 2点の中間点を設定
        let centerPos: SIMD3<Float> = end

        // 2. Orientation: startからcontrol1へ向かう方向を計算し、
        //    BoxのZ軸がその方向を向くような回転を生成
        let direction: SIMD3<Float> = normalize(startControl - end)
        let orientation: simd_quatf = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)

        // 3. Scale: Boxの元のサイズを考慮し、
        //    Z軸方向のみを長さ(length)に合わせて引き伸ばす
        let scale: SIMD3<Float> = SIMD3<Float>(1, 1, length / controlEntitySize)

        // Transformをまとめて更新
        lineEntity.transform = Transform(scale: scale, rotation: orientation, translation: centerPos)
    }
}
