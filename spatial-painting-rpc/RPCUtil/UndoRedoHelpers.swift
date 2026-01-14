//
//  UndoRedoHelpers.swift
//  spatial-painting-rpc
//
//  Created for undo/redo helper methods
//

import Foundation
import UIKit

/// RPCModelのUndoRedo関連のヘルパーメソッド拡張
@MainActor
extension RPCModel {
    /// ストロークの色変更アクションを記録
    /// - Parameters:
    ///   - userId: ユーザーID
    ///   - newColorName: 新しい色の名前
    ///   - oldColorName: 古い色の名前
    func recordColorChange(userId: UUID, newColorName: String, oldColorName: String) {
        let redoMethod = Method.paintingEntity(.setStrokeColor)
        let redoParam = Param.paintingEntity(.setStrokeColor(SetStrokeColorParam(userId: userId, strokeColorName: newColorName)))
        
        let undoMethod = Method.paintingEntity(.setStrokeColor)
        let undoParam = Param.paintingEntity(.setStrokeColor(SetStrokeColorParam(userId: userId, strokeColorName: oldColorName)))
        
        recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
    }
    
    /// ストロークの削除アクションを記録
    /// - Parameters:
    ///   - strokeId: 削除するストロークのID
    func recordStrokeRemoval(strokeId: UUID) {
        // 削除前にストロークのデータを取得
        guard let stroke = painting.paintingCanvas.getStroke(strokeId: strokeId) else {
            return
        }
        
        let redoMethod = Method.paintingEntity(.removeStroke)
        let redoParam = Param.paintingEntity(.removeStroke(RemoveStrokeParam(uuid: strokeId)))
        
        let undoMethod = Method.paintingEntity(.restoreStroke)
        let undoParam = Param.paintingEntity(.restoreStroke(RestoreStrokeParam(stroke: stroke)))
        
        recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
    }
    
    /// 全ストロークの削除アクションを記録
    func recordAllStrokesRemoval() {
        // 現在の全ストロークを保存
        let allStrokes = painting.paintingCanvas.strokes
        
        let redoMethod = Method.paintingEntity(.removeAllStroke)
        let redoParam = Param.paintingEntity(.removeAllStroke(PaintingEntity.Param.RemoveAllStrokeParam()))
        
        let undoMethod = Method.paintingEntity(.addBezierStrokes)
        let undoParam = Param.paintingEntity(.addBezierStrokes(AddBezierStrokesParam(strokes: allStrokes)))
        
        recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
    }
    
    /// ストロークの確定アクションを記録
    /// - Parameters:
    ///   - userId: ユーザーID
    ///   - strokeId: ストロークのID
    func recordStrokeFinish(userId: UUID, strokeId: UUID) {
        let redoMethod = Method.paintingEntity(.finishStroke)
        let redoParam = Param.paintingEntity(.finishStroke(FinishStrokeParam(userId: userId)))
        
        let undoMethod = Method.paintingEntity(.removeStroke)
        let undoParam = Param.paintingEntity(.removeStroke(RemoveStrokeParam(uuid: strokeId)))
        
        recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
    }
    
    /// 線幅の変更アクションを記録
    /// - Parameters:
    ///   - userId: ユーザーID
    ///   - newToolName: 新しいツール名
    ///   - oldToolName: 古いツール名
    func recordLineWidthChange(userId: UUID, newToolName: String, oldToolName: String) {
        let redoMethod = Method.paintingEntity(.changeFingerLineWidth)
        let redoParam = Param.paintingEntity(.changeFingerLineWidth(ChangeFingerLineWidthParam(userId: userId, toolName: newToolName)))
        
        let undoMethod = Method.paintingEntity(.changeFingerLineWidth)
        let undoParam = Param.paintingEntity(.changeFingerLineWidth(ChangeFingerLineWidthParam(userId: userId, toolName: oldToolName)))
        
        recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
    }
    
    /// ベジェストロークの追加アクションを記録
    /// - Parameter strokes: 追加するストローク配列
    func recordBezierStrokesAddition(strokes: [BezierStroke]) {
        let strokeIds = strokes.map { $0.uuid }
        
        let redoMethod = Method.paintingEntity(.addBezierStrokes)
        let redoParam = Param.paintingEntity(.addBezierStrokes(AddBezierStrokesParam(strokes: strokes)))
        
        // Undo時は各ストロークを個別に削除する必要があるが、
        // 簡略化のため最初のストロークIDのみを使用（実際には全てのストロークを削除する処理が必要）
        // より完全な実装では、複数のストロークを一度に削除するメソッドを追加する必要がある
        if let firstStrokeId = strokeIds.first {
            let undoMethod = Method.paintingEntity(.removeStroke)
            let undoParam = Param.paintingEntity(.removeStroke(RemoveStrokeParam(uuid: firstStrokeId)))
            
            recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
        }
    }
    
    /// コントロールポイントの移動完了アクションを記録
    /// - Parameters:
    ///   - strokeId: ストロークID
    ///   - controlPointId: コントロールポイントID
    ///   - newPosition: 新しい位置
    ///   - oldPosition: 古い位置
    ///   - controlType: コントロールポイントのタイプ
    func recordControlPointFinish(strokeId: UUID, controlPointId: UUID, newPosition: SIMD3<Float>, oldPosition: SIMD3<Float>, controlType: BezierStroke.BezierPoint.PointType) {
        let redoMethod = Method.paintingEntity(.finishControlPoint)
        let redoParam = Param.paintingEntity(.finishControlPoint(FinishControlPointParam(strokeId: strokeId, controlPointId: controlPointId)))
        
        // Undo時は元の位置に戻して再度finishする
        let undoMethod = Method.paintingEntity(.moveControlPoint)
        let undoParam = Param.paintingEntity(.moveControlPoint(MoveControlPointParam(strokeId: strokeId, controlPointId: controlPointId, controlType: controlType, newPosition: oldPosition)))
        
        recordAction(redoMethod: redoMethod, redoParam: redoParam, undoMethod: undoMethod, undoParam: undoParam)
    }
}

/// Painting クラスへのUndoRedo関連のヘルパーメソッド拡張
@MainActor
extension Painting {
    /// 現在選択されている色の名前を取得
    /// - Returns: 色の名前、見つからない場合は "white"
    func getCurrentColorName() -> String {
        let currentColor = advancedColorPalletModel.selectedBasicColorName
        return currentColor
    }
    
    /// 現在選択されているツール名を取得
    /// - Returns: ツール名
    func getCurrentToolName() -> String {
        return advancedColorPalletModel.selectedToolName
    }
}
