//
//  UndoRedoUsageExample.swift
//  spatial-painting-rpc
//
//  Undo/Redo機能の使用例
//
//  このファイルは使用例を示すためのドキュメントであり、実際のコードには含まれません
//

import Foundation
import SwiftUI

/*
 # Undo/Redo機能の使用方法
 
 ## 概要
 このアプリケーションには、Canvas上での操作をUndo/Redoできる機能が実装されています。
 以下の操作が対象となります：
 
 - ストロークの色変更 (setStrokeColor)
 - ストロークの線幅変更 (changeFingerLineWidth)
 - ストロークの確定 (finishStroke)
 - ストロークの削除 (removeStroke)
 - 全ストロークの削除 (removeAllStroke)
 - ベジェ制御点の操作 (finishControlPoint)
 - ストロークの再出現 (restoreStroke)
 
 ## 自動的に除外される操作
 以下の操作は、描画を確定させないため自動的に履歴から除外されます：
 
 - addStrokePoint (ストロークポイントの追加中)
 - addBezierStrokePoints (ベジェポイントの追加中)
 - moveControlPoint (制御点の移動中)
 - finishControlPoint (制御点の編集確定) ※完全なUndoが困難なため除外
 
 ## 基本的な使用方法
 
 ### 1. Undo/Redoマネージャーへのアクセス
 ```swift
 // RPCModelからUndoRedoManagerにアクセス
 let undoRedoManager = appModel.rpcModel.undoRedoManager
 
 // Undo/Redoが可能かチェック
 if undoRedoManager.canUndo {
     print("Undo可能")
 }
 
 if undoRedoManager.canRedo {
     print("Redo可能")
 }
 ```
 
 ### 2. Undo操作の実行
 ```swift
 // Undoを実行
 let success = appModel.rpcModel.performUndo()
 if success {
     print("Undoが実行されました")
 } else {
     print("Undo履歴がありません")
 }
 ```
 
 ### 3. Redo操作の実行
 ```swift
 // Redoを実行
 let success = appModel.rpcModel.performRedo()
 if success {
     print("Redoが実行されました")
 } else {
     print("Redo履歴がありません")
 }
 ```
 
 ### 4. アクションの記録と送信（推奨方法）
 ```swift
 // 色変更を記録して送信
 _ = appModel.rpcModel.sendAndRecordColorChange(
     userId: appModel.mcPeerIDUUIDWrapper.myId,
     newColorName: "red"
 )
 
 // 線幅変更を記録して送信
 _ = appModel.rpcModel.sendAndRecordLineWidthChange(
     userId: appModel.mcPeerIDUUIDWrapper.myId,
     newToolName: "large"
 )
 
 // ストローク削除を記録して送信
 _ = appModel.rpcModel.sendAndRecordStrokeRemoval(strokeId: strokeId)
 
 // 全ストローク削除を記録して送信
 _ = appModel.rpcModel.sendAndRecordAllStrokesRemoval()
 ```
 
 ### 5. ストローク確定時のアクション記録
 ```swift
 // ストロークを確定する際、strokeIdを使って記録
 let strokeId = UUID() // 実際のストロークID
 _ = appModel.rpcModel.sendAndRecordStrokeFinish(
     userId: appModel.mcPeerIDUUIDWrapper.myId,
     strokeId: strokeId
 )
 ```
 
 ### 6. 手動でのアクション記録（上級者向け）
 ```swift
 // 既存のsendRequest呼び出しにアクション記録を追加する場合
 
 // 1. 現在の状態を保存
 let oldColorName = appModel.rpcModel.painting.getCurrentColorName()
 
 // 2. リクエストを送信
 _ = appModel.rpcModel.sendRequest(
     RequestSchema(
         peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
         method: .paintingEntity(.setStrokeColor),
         param: .paintingEntity(.setStrokeColor(
             SetStrokeColorParam(userId: userId, strokeColorName: "blue")
         ))
     )
 )
 
 // 3. アクションを記録
 appModel.rpcModel.recordColorChange(
     userId: userId,
     newColorName: "blue",
     oldColorName: oldColorName
 )
 ```
 
 ## UIでの実装例
 
 ### SwiftUIでのUndo/Redoボタン
 ```swift
 struct UndoRedoButtons: View {
     @EnvironmentObject var appModel: AppModel
     
     var body: some View {
         HStack {
             Button("Undo") {
                 _ = appModel.rpcModel.performUndo()
             }
             .disabled(!appModel.rpcModel.undoRedoManager.canUndo)
             
             Button("Redo") {
                 _ = appModel.rpcModel.performRedo()
             }
             .disabled(!appModel.rpcModel.undoRedoManager.canRedo)
         }
     }
 }
 ```
 
 ### キーボードショートカット対応
 ```swift
 .keyboardShortcut("z", modifiers: .command)  // Undo
 .keyboardShortcut("z", modifiers: [.command, .shift])  // Redo
 ```
 
 ## 注意事項
 
 1. **履歴の最大数**: デフォルトで100個のアクションが記録されます
 2. **Undo後の新規アクション**: Undoした後に新しいアクションを実行すると、Redo履歴は破棄されます
 3. **RPC同期**: Undo/Redo操作は他のピアには自動的に同期されません（各端末で独立して管理）
 4. **除外メソッド**: setStrokePoint等の中間操作は自動的に履歴から除外されます
 
 ## トラブルシューティング
 
 ### Undoが動作しない場合
 1. アクションが正しく記録されているか確認
 2. 除外メソッドに該当していないか確認
 3. undoRedoManager.getHistoryInfo()で履歴を確認
 
 ### メモリ使用量が気になる場合
 ```swift
 // UndoRedoManagerの最大サイズを変更（初期化時）
 self.undoRedoManager = UndoRedoManager(maxSize: 50)
 ```
 
 ### すべての履歴をクリア
 ```swift
 appModel.rpcModel.undoRedoManager.clear()
 ```
 
 ## デバッグ情報の取得
 ```swift
 let (total, current, canUndo, canRedo) = appModel.rpcModel.undoRedoManager.getHistoryInfo()
 print("履歴数: \(total), 現在位置: \(current)")
 print("Undo可能: \(canUndo), Redo可能: \(canRedo)")
 ```
*/
