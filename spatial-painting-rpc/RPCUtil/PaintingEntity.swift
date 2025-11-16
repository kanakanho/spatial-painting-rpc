//
//  PaintingCanvasEintity.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/21.
//

import Foundation
import RealityKit
import UIKit

@MainActor
class Painting:ObservableObject {
    @Published var paintingCanvas = PaintingCanvas()
    @Published var advancedColorPalletModel = AdvancedColorPalletModel()
    
    /// 色を選択する
    /// - Parameter strokeColorName: 色の名前
    func setStrokeColor(param: SetStrokeColorParam) {
        if let color: UIColor = advancedColorPalletModel.colorDictionary[param.strokeColorName] {
            paintingCanvas.setActiveColor(userId: param.userId, color: color)
        }
    }
    
    /// これまでに書いた全てのストロークを削除する
    func removeAllStroke() {
        paintingCanvas.reset()
    }
    
    /// 指定したUUIDを `StrokeComponent` に持つストロークを削除する
    func removeStroke(param: RemoveStrokeParam){
        paintingCanvas.removeStroke(strokeId: param.uuid)
    }
    
    /// ストロークを描く
    /// - Parameter point: 描く座標
    func addStrokePoint(param: AddStrokePointParam) {
        paintingCanvas.addPoint(param.uuid, param.point, userId: param.userId)
    }
    
    /// ストロークを終了する
    func finishStroke(param: FinishStrokeParam) {
        paintingCanvas.finishStroke(param.userId)
    }
    
    /// 複数のストロークを追加する
    func addStrokes(param: AddStrokesParam) {
        paintingCanvas.addStrokes(param.strokes)
    }
    
    /// 線の太さを変更する
    func changeFingerLineWidth(param: ChangeFingerLineWidthParam) {
        //print("Finger line width changed to: \(toolName)")
        if advancedColorPalletModel.selectedToolName == param.toolName {
            return
        }
        advancedColorPalletModel.selectedToolName = param.toolName
        if let lineWidth = advancedColorPalletModel.toolBalls.get(withID: param.toolName)?.lineWidth {
            paintingCanvas.setMaxRadius(userId: param.userId, radius: Float(lineWidth))
        }
    }
    
    /// ベジェのストロークを編集する
    func moveControlPoint(param: MoveControlPointParam) {
        paintingCanvas.moveControlPoint(
            strokeId: param.strokeId,
            controlPointId: param.controlPointId,
            controlType: param.controlType,
            newPosition: param.newPosition
        )
    }
    
    /// ベジェのストロークの編集を終える
    func finishControlPoint(param: FinishControlPointParam) {
        paintingCanvas.finishControlPoint(
            strokeId: param.strokeId,
            controlPointId: param.controlPointId
        )
    }
}

struct PaintingEntity: RPCEntity {
    enum Method: RPCEntityMethod {
        case setStrokeColor
        case removeAllStroke
        case removeStroke
        case addStrokePoint
        case addStrokes
        case finishStroke
        case changeFingerLineWidth
        case moveControlPoint
        case finishControlPoint
    }
    
    enum Param: RPCEntityParam {
        case setStrokeColor(SetStrokeColorParam)
        case removeAllStroke(RemoveAllStrokeParam)
        case removeStroke(RemoveStrokeParam)
        case addStrokePoint(AddStrokePointParam)
        case addStrokes(AddStrokesParam)
        case finishStroke(FinishStrokeParam)
        case changeFingerLineWidth(ChangeFingerLineWidthParam)
        case moveControlPoint(MoveControlPointParam)
        case finishControlPoint(FinishControlPointParam)
        
        struct SetStrokeColorParam: Codable {
            let userId: UUID
            let strokeColorName: String
        }
        
        struct RemoveAllStrokeParam: Codable {
        }
        
        struct RemoveStrokeParam: Codable {
            let uuid: UUID
        }
        
        struct AddStrokePointParam: Codable {
            let uuid: UUID
            let point: SIMD3<Float>
            let userId: UUID
        }
        
        struct AddStrokesParam: Codable {
            let strokes: [BezierStroke]
        }
        
        struct FinishStrokeParam: Codable {
            let userId: UUID
        }
        
        struct ChangeFingerLineWidthParam: Codable {
            let userId: UUID
            let toolName: String
        }
        
        struct MoveControlPointParam: Codable {
            let strokeId: UUID
            let controlPointId: UUID
            let controlType: BezierStroke.BezierPoint.PointType
            let newPosition: SIMD3<Float>
        }
        
        struct FinishControlPointParam: Codable {
            let strokeId: UUID
            let controlPointId: UUID
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .setStrokeColor(let param):
                try container.encode(param, forKey: .setStrokeColor)
            case .removeAllStroke(let param):
                try container.encode(param, forKey: .removeAllStroke)
            case .removeStroke(let param):
                try container.encode(param, forKey: .removeStroke)
            case .addStrokePoint(let param):
                try container.encode(param, forKey: .addStrokePoint)
            case .addStrokes(let param):
                try container.encode(param, forKey: .addStrokes)
            case .finishStroke(let param):
                try container.encode(param, forKey: .finishStroke)
            case .changeFingerLineWidth(let param):
                try container.encode(param, forKey: .changeFingerLineWidth)
            case .moveControlPoint(let param):
                try container.encode(param, forKey: .moveControlPoint)
            case .finishControlPoint(let param):
                try container.encode(param, forKey: .finishControlPoint)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let param = try? container.decode(SetStrokeColorParam.self, forKey: .setStrokeColor) {
                self = .setStrokeColor(param)
            } else if let param = try? container.decode(RemoveAllStrokeParam.self, forKey: .removeAllStroke) {
                self = .removeAllStroke(param)
            } else if let param = try? container.decode(RemoveStrokeParam.self, forKey: .removeStroke) {
                self = .removeStroke(param)
            } else if let param = try? container.decode(AddStrokePointParam.self, forKey: .addStrokePoint) {
                self = .addStrokePoint(param)
            } else if let param = try? container.decode(AddStrokesParam.self, forKey: .addStrokes) {
                self = .addStrokes(param)
            } else if let param = try? container.decode(FinishStrokeParam.self, forKey: .finishStroke) {
                self = .finishStroke(param)
            } else if let param = try? container.decode(ChangeFingerLineWidthParam.self, forKey: .changeFingerLineWidth) {
                self = .changeFingerLineWidth(param)
            } else if let param = try? container.decode(MoveControlPointParam.self, forKey: .moveControlPoint) {
                self = .moveControlPoint(param)
            } else if let param = try? container.decode(FinishControlPointParam.self, forKey: .finishControlPoint) {
                self = .finishControlPoint(param)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.setStrokeColor, in: container, debugDescription: "Invalid parameter type")
            }
        }
        
        internal enum CodingKeys: CodingKey {
            case setStrokeColor
            case removeAllStroke
            case removeStroke
            case addStrokePoint
            case addStrokes
            case finishStroke
            case changeFingerLineWidth
            case moveControlPoint
            case finishControlPoint
        }
    }
}

typealias SetStrokeColorParam = PaintingEntity.Param.SetStrokeColorParam
typealias RemoveAllStrokesParam = PaintingEntity.Param.RemoveAllStrokeParam
typealias RemoveStrokeParam = PaintingEntity.Param.RemoveStrokeParam
typealias AddStrokePointParam = PaintingEntity.Param.AddStrokePointParam
typealias AddStrokesParam = PaintingEntity.Param.AddStrokesParam
typealias FinishStrokeParam = PaintingEntity.Param.FinishStrokeParam
typealias ChangeFingerLineWidthParam = PaintingEntity.Param.ChangeFingerLineWidthParam
typealias MoveControlPointParam = PaintingEntity.Param.MoveControlPointParam
typealias FinishControlPointParam = PaintingEntity.Param.FinishControlPointParam
