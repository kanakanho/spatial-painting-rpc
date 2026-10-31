//
//  BezierPoint.swift
//  sample
//
//  Created by blueken on 2025/10/14.
//

import Foundation
import simd
import RealityKit

struct BezierStrokeControlComponent: Component {
    let bezierStrokeId: UUID
    let bezierPointId: UUID
    let controlType: BezierStroke.BezierPoint.PointType
    
    init(bezierStrokeId: UUID, bezierPointId: UUID, controlType: BezierStroke.BezierPoint.PointType) {
        self.bezierStrokeId = bezierStrokeId
        self.bezierPointId = bezierPointId
        self.controlType = controlType
    }
}

extension BezierStroke {
    @MainActor
    final class BezierPoint {
        enum PointType: CaseIterable, Codable, Sendable {
            case end
            case startControl
            case endControl
            
            func next() -> PointType {
                switch self {
                case .end:
                    return .endControl
                case .startControl:
                    return .end
                case .endControl:
                    return .end
                }
            }
        }
        
        static let endShapeSize: Float = 0.02
        static let endEntityMaterial: SimpleMaterial = .init(color: .init(white: 1.0, alpha: 0.5), isMetallic: true)
        
        static let controlEntitySize: Float = 0.001
        static let controlEntityMaterial = UnlitMaterial(color: .blue)
        
        static let handleEntityBoxSize: Float = 0.01
        static let handleEntityMaterial = UnlitMaterial(color: .blue)
        
        public var uuid: UUID = UUID()
        public let strokeId: UUID
        
        public var root: Entity = Entity()
        var controlEntity: ModelEntity
        var endEntity: Entity
        var startHandleEntity: Entity
        var endHandleEntity: Entity

        public var end: SIMD3<Float>?
        public var startControl: SIMD3<Float>?
        public var endControl: SIMD3<Float>?
        
        public let endID: UUID = UUID()
        public let startControlID: UUID = UUID()
        public let endControlID: UUID = UUID()
        
        func setEntities(bezierEndPoint: Entity, bezierHandle: Entity) {
            self.endEntity.removeFromParent()
            self.startHandleEntity.removeFromParent()
            self.endHandleEntity.removeFromParent()

            self.endEntity = bezierEndPoint
            self.endHandleEntity = bezierHandle.clone(recursive: true)
            self.startHandleEntity = bezierHandle.clone(recursive: true)
            
            self.endEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            self.startHandleEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            self.endHandleEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            
            self.endEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .end))
            self.startHandleEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .startControl))
            self.endHandleEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .endControl))
            
            self.root.addChild(self.endEntity)
            self.root.addChild(self.startHandleEntity)
            self.root.addChild(self.endHandleEntity)
        }
        
        init(strokeId: UUID, pointId: UUID, bezierEndPoint: Entity, bezierHandle: Entity) {
            self.strokeId = strokeId
            self.uuid = pointId
            
            controlEntity = ModelEntity(mesh: .generateBox(size: Self.controlEntitySize), materials: [Self.controlEntityMaterial])
            
            endEntity = bezierEndPoint
            startHandleEntity = bezierHandle.clone(recursive: true)
            endHandleEntity = bezierHandle.clone(recursive: true)
            
            endEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            startHandleEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            endHandleEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            
            endEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .end))
            startHandleEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .startControl))
            endHandleEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .endControl))
            
            root.addChild(endEntity)
            root.addChild(controlEntity)
            root.addChild(startHandleEntity)
            root.addChild(endHandleEntity)
        }

        init(strokeId: UUID, pointId: UUID = UUID()) {
            self.strokeId = strokeId
            self.uuid = pointId
            
            controlEntity = ModelEntity(mesh: .generateBox(size: Self.controlEntitySize), materials: [Self.controlEntityMaterial])
            
            endEntity = ModelEntity()
            endHandleEntity = ModelEntity()
            startHandleEntity = ModelEntity()
            
            endEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            startHandleEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            endHandleEntity.components.set(InputTargetComponent(allowedInputTypes: .all))
            
            endEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .end))
            startHandleEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .startControl))
            endHandleEntity.components.set(BezierStrokeControlComponent(bezierStrokeId: strokeId, bezierPointId: uuid, controlType: .endControl))
            
            root.addChild(endEntity)
            root.addChild(controlEntity)
            root.addChild(startHandleEntity)
            root.addChild(endHandleEntity)
        }

        /// 次に追加されるべき点の種類を追跡する
        var nextPointType: PointType = .end
        
        /// 4つの点がすべて設定されているかどうか
        public var isComplete: Bool {
            startControl != nil && endControl != nil
        }
        
        public func getPosition(of pointType: PointType) -> SIMD3<Float>? {
            switch pointType {
            case .end:
                return end
            case .startControl:
                return startControl
            case .endControl:
                return endControl
            }
        }
        
        /// 設定済みの点を正しい順序で配列として返す
        public var list: [SIMD3<Float>] {
            // compactMapでnilを除外し、存在する点だけを順序通りに返す
            [end, endControl].compactMap { $0 }
        }
        
        /// 点をシーケンスの次の位置に設定する
        /// - Parameter point: 追加する点の座標
        public func add(point: SIMD3<Float>, pn: PointType) {
            var data = self.data
            data.add(point: point, pn: pn)
            end = data.end
            startControl = data.startControl
            endControl = data.endControl
            remesh()
        }
        
        public func updateEndPointMesh() {
            guard let end = end else { return }
            
            endEntity.setPosition(end, relativeTo: nil)
        }
        
        // 補助用のオブジェクト
        public func updateDrawingControlPointMesh() {
            guard let end = end else { return }
            
            guard let startControl = startControl, let endControl = endControl else { return }
            
            // 2点間の距離を計算
            let length: Float = simd_distance(end, endControl) * 2.0
            
            // 距離がほぼ0の場合は、スケールを0にして表示しない（NaNエラーを回避）
            guard length > .ulpOfOne else {
                controlEntity.isEnabled = false
                return
            }
            controlEntity.isEnabled = true
            
            // 1. Position: 2点の中間点を設定
            let centerPos: SIMD3<Float> = end
            
            // 2. Orientation: startからcontrol1へ向かう方向を計算し、
            //    BoxのZ軸がその方向を向くような回転を生成
            let direction: SIMD3<Float> = normalize(startControl - end)
            let orientation: simd_quatf = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)
            
            // 3. Scale: Boxの元のサイズ（0.01）を考慮し、
            //    Z軸方向のみを長さ(length)に合わせて引き伸ばす
            let scale: SIMD3<Float> = SIMD3<Float>(1, 1, length / BezierStroke.BezierPoint.controlEntitySize)
            
            // Transformをまとめて更新
            controlEntity.transform = Transform(scale: scale, rotation: orientation, translation: centerPos)
            
            // ハンドル（線の両端の2点）
            startHandleEntity.setPosition(startControl, relativeTo: nil)
            endHandleEntity.setPosition(endControl, relativeTo: nil)
        }
        
        public func remesh() {
            updateEndPointMesh()
            updateDrawingControlPointMesh()
        }
        
        /// 通信・ファイル保存用のデータから生成する
        convenience init(data: BezierPointData) {
            self.init(strokeId: data.strokeId, pointId: data.uuid)
            self.end = data.end
            self.startControl = data.startControl
            self.endControl = data.endControl
            self.remesh()
        }
        
        /// 通信・ファイル保存用のデータ
        var data: BezierPointData {
            BezierPointData(uuid: uuid, strokeId: strokeId, end: end, startControl: startControl, endControl: endControl)
        }
    }
}

@MainActor
extension [BezierStroke.BezierPoint] {
    var beziers: [[SIMD3<Float>]] {
        map(\.data).beziers
    }
    
    func add(pointId: UUID, point: SIMD3<Float>, pn: BezierStroke.BezierPoint.PointType) {
        if let index = self.firstIndex(where: { $0.uuid == pointId }) {
            self[index].add(point: point, pn: pn)
        }
    }
    
    func getPoint(by pointId: UUID) -> BezierStroke.BezierPoint? {
        if let index = self.firstIndex(where: { $0.uuid == pointId }) {
            return self[index]
        }
        return nil
    }
    
    /// アフィン変換を適用した送信用のデータ
    func transferData(affine: simd_float4x4) -> [BezierPointData] {
        return self.map { $0.data.applying(affine) }
    }
}

extension [[SIMD3<Float>]] {
    /// ベジェのデータを `BezierStroke.BezierPoint` に変換する
    /// [firstPoint, ctrl1, ctrl2, lastPoint]
    @MainActor
    func toBezierStrokeBezierPoint(strokeId: UUID, bezierEndPoint: Entity, bezierHandle: Entity) -> [BezierStroke.BezierPoint] {
        // 4点ない場合は消す
        if self.count < 3 {
            return []
        }
        
        var bezierPoints: [BezierStroke.BezierPoint] = []
        
        guard let end = self.first?[0],
              let endControl = self.first?[1] else { return [] }
        
        let startPoint: BezierStroke.BezierPoint = BezierStroke.BezierPoint(strokeId: strokeId, pointId: UUID(), bezierEndPoint: bezierEndPoint.clone(recursive: true), bezierHandle: bezierHandle.clone(recursive: true))
        startPoint.add(point: end, pn: .end)
        startPoint.add(point: endControl, pn: .endControl)
        
        bezierPoints.append(startPoint)
        
        for points in self {
            let tmpBezierPoint = BezierStroke.BezierPoint(strokeId: strokeId, pointId: UUID(), bezierEndPoint: bezierEndPoint.clone(recursive: true), bezierHandle: bezierHandle.clone(recursive: true))
            tmpBezierPoint.add(point: points[3], pn: .end)
            tmpBezierPoint.add(point: points[2], pn: .startControl)
            
            bezierPoints.append(tmpBezierPoint)
        }
        return bezierPoints
    }
}
