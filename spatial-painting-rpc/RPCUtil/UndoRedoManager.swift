//
//  UndoRedoManager.swift
//  spatial-painting-rpc
//
//  Created for undo/redo functionality
//

import Foundation

/// Undo/Redoアクションを表す構造体
struct UndoRedoAction: Codable {
    /// アクションの一意なID
    let id: UUID
    /// Redo時に実行するメソッド
    let redoMethod: Method
    /// Redo時に渡すパラメータ
    let redoParam: Param
    /// Undo時に実行するメソッド
    let undoMethod: Method
    /// Undo時に渡すパラメータ
    let undoParam: Param
    
    init(id: UUID = UUID(), redoMethod: Method, redoParam: Param, undoMethod: Method, undoParam: Param) {
        self.id = id
        self.redoMethod = redoMethod
        self.redoParam = redoParam
        self.undoMethod = undoMethod
        self.undoParam = undoParam
    }
}

/// Undo/Redoを管理するクラス
@MainActor
class UndoRedoManager: ObservableObject {
    /// アクションの履歴を保持する配列（固定長キューとして使用）
    @Published private(set) var actions: [UndoRedoAction] = []
    
    /// 現在のインデックス（次にUndoする位置を指す）
    @Published private(set) var currentIndex: Int = 0
    
    /// キューの最大長
    let maxSize: Int
    
    /// Undo可能かどうか
    var canUndo: Bool {
        return currentIndex > 0
    }
    
    /// Redo可能かどうか
    var canRedo: Bool {
        return currentIndex < actions.count
    }
    
    /// 特定のメソッドを除外するかどうかを判定するクロージャ
    private let shouldExcludeMethod: ((Method) -> Bool)?
    
    init(maxSize: Int = 100, shouldExcludeMethod: ((Method) -> Bool)? = nil) {
        self.maxSize = maxSize
        self.shouldExcludeMethod = shouldExcludeMethod
    }
    
    /// 新しいアクションを追加
    /// - Parameter action: 追加するアクション
    func addAction(_ action: UndoRedoAction) {
        // 除外すべきメソッドの場合は追加しない
        if let shouldExclude = shouldExcludeMethod, shouldExclude(action.redoMethod) {
            return
        }
        
        // currentIndex以降のアクションを破棄（Undo後に新しいアクションが追加された場合）
        if currentIndex < actions.count {
            actions.removeSubrange(currentIndex...)
        }
        
        // 新しいアクションを追加
        actions.append(action)
        
        // キューの最大長を超えた場合、古いアクションを削除
        if actions.count > maxSize {
            actions.removeFirst()
            // 削除すると全インデックスが1つずつ前にシフトするが、
            // 最後にcurrentIndex = actions.countを設定するため、
            // 相対的な位置関係は保たれる
        }
        
        // currentIndexは常にactions.countと同じになる
        currentIndex = actions.count
    }
    
    /// Undoを実行して、実行すべきアクションを返す
    /// - Returns: Undo実行用のRequestSchema、またはnil
    func undo() -> UndoRedoAction? {
        guard canUndo else { return nil }
        
        currentIndex -= 1
        return actions[currentIndex]
    }
    
    /// Redoを実行して、実行すべきアクションを返す
    /// - Returns: Redo実行用のRequestSchema、またはnil
    func redo() -> UndoRedoAction? {
        guard canRedo else { return nil }
        
        let action = actions[currentIndex]
        currentIndex += 1
        return action
    }
    
    /// すべてのアクションをクリア
    func clear() {
        actions.removeAll()
        currentIndex = 0
    }
    
    /// 現在の履歴の状態を取得（デバッグ用）
    func getHistoryInfo() -> (total: Int, current: Int, canUndo: Bool, canRedo: Bool) {
        return (actions.count, currentIndex, canUndo, canRedo)
    }
}

/// Undo/Redoのヘルパー拡張
extension UndoRedoManager {
    /// PaintingEntityのメソッドに対するデフォルトの除外判定
    static func defaultPaintingMethodExclusionCheck(method: Method) -> Bool {
        switch method {
        case .paintingEntity(let paintingMethod):
            switch paintingMethod {
            case .addStrokePoint, .addBezierStrokePoints, .moveControlPoint:
                // これらのメソッドは描画を確定させないため除外
                return true
            case .finishControlPoint:
                // コントロールポイントの編集は複雑で、完全なUndoを実装するのが困難なため除外
                // 将来的には編集開始時のストローク状態を保存する実装を追加することで対応可能
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
