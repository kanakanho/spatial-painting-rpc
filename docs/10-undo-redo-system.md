# Undo/Redo機能の実装

## 概要

このドキュメントは、spatial-painting-rpcアプリケーションに実装されたUndo/Redo機能について説明します。

## 実装されたファイル

### 1. UndoRedoManager.swift
Undo/Redoの履歴を管理する中核となるクラスです。

**主な機能:**
- 固定長キューによるアクション履歴の管理
- 現在のインデックス管理によるUndo/Redo制御
- 選択的メソッド除外機能
- 型安全なRPCEntity統合

**主要メソッド:**
- `addAction(_:)` - 新しいアクションを履歴に追加
- `undo()` - Undo操作を実行し、実行すべきアクションを返す
- `redo()` - Redo操作を実行し、実行すべきアクションを返す
- `clear()` - すべての履歴をクリア
- `getHistoryInfo()` - 履歴の状態を取得（デバッグ用）

### 2. UndoRedoHelpers.swift
Undo/Redo機能を簡単に使用するためのヘルパーメソッド集です。

**主な機能:**
- アクションの記録と送信を一度に行うヘルパーメソッド
- 現在の状態を取得するヘルパーメソッド

**提供されるメソッド:**
- `sendAndRecordColorChange(userId:newColorName:)` - 色変更を記録して送信
- `sendAndRecordLineWidthChange(userId:newToolName:)` - 線幅変更を記録して送信
- `sendAndRecordStrokeRemoval(strokeId:)` - ストローク削除を記録して送信
- `sendAndRecordAllStrokesRemoval()` - 全ストローク削除を記録して送信
- `sendAndRecordStrokeFinish(userId:strokeId:)` - ストローク確定を記録して送信

### 3. PaintingEntity.swift（更新）
新しいメソッドとパラメータを追加：

**追加されたメソッド:**
- `restoreStroke` - 削除されたストロークを復元

**追加されたパラメータ:**
- `RestoreStrokeParam` - ストローク復元のパラメータ

### 4. PaintingCanvas.swift（更新）
Undo/Redo用のヘルパーメソッドを追加：

**追加されたメソッド:**
- `getStroke(strokeId:)` - 特定のストロークを取得
- `getActiveColor(userId:)` - ユーザーの現在の色を取得
- `getMaxRadius(userId:)` - ユーザーの現在の線幅を取得

### 5. RPCModel.swift（更新）
UndoRedoManagerの統合と関連メソッドの追加：

**追加されたプロパティ:**
- `undoRedoManager` - Undo/Redoマネージャーのインスタンス

**追加されたメソッド:**
- `performUndo()` - Undo操作を実行
- `performRedo()` - Redo操作を実行
- `recordAction(...)` - アクションを履歴に記録

## アーキテクチャ

### UndoRedoAction構造
```swift
struct UndoRedoAction {
    let id: UUID
    let redoMethod: Method      // Redo時に実行するメソッド
    let redoParam: Param        // Redo時のパラメータ
    let undoMethod: Method      // Undo時に実行するメソッド
    let undoParam: Param        // Undo時のパラメータ
}
```

### 動作フロー

#### 通常の操作時
```
[ユーザー操作]
    ↓
[現在の状態を保存]
    ↓
[操作を実行（sendRequest）]
    ↓
[UndoRedoActionを作成]
    ↓
[UndoRedoManagerに追加]
```

#### Undo実行時
```
[performUndo呼び出し]
    ↓
[UndoRedoManager.undo()]
    ↓
[UndoRedoActionを取得]
    ↓
[undoMethodとundoParamでRequestSchema作成]
    ↓
[sendRequestで実行]
```

#### Redo実行時
```
[performRedo呼び出し]
    ↓
[UndoRedoManager.redo()]
    ↓
[UndoRedoActionを取得]
    ↓
[redoMethodとredoParamでRequestSchema作成]
    ↓
[sendRequestで実行]
```

## 対応操作一覧

### Undo/Redo対象の操作
以下の操作は自動的に履歴に記録されます（除外設定がある場合を除く）：

1. **setStrokeColor** - ストロークの色変更
2. **changeFingerLineWidth** - ストロークの線幅変更
3. **finishStroke** - ストロークの確定
4. **removeStroke** - 特定のストロークの削除
5. **removeAllStroke** - 全ストロークの削除
6. **finishControlPoint** - ベジェ制御点の操作完了
7. **addBezierStrokes** - ベジェストロークの追加

### 自動的に除外される操作
以下の操作は描画を確定させないため、デフォルトで履歴から除外されます：

1. **addStrokePoint** - ストロークポイントの追加中
2. **addBezierStrokePoints** - ベジェポイントの追加中
3. **moveControlPoint** - 制御点の移動中
4. **finishControlPoint** - 制御点の編集確定（完全なUndoが困難なため除外）

この除外は`UndoRedoManager.defaultPaintingMethodExclusionCheck`メソッドで定義されています。

**注意**: `finishControlPoint`は、一連の`moveControlPoint`操作の後に実行される確定操作です。
完全なUndoを実現するには、編集開始前のストローク全体の状態を保存する必要があり、
実装が複雑になるため、現在のバージョンでは除外されています。

## 使用例

### 基本的な使用方法

```swift
// Undoの実行
if appModel.rpcModel.undoRedoManager.canUndo {
    let success = appModel.rpcModel.performUndo()
}

// Redoの実行
if appModel.rpcModel.undoRedoManager.canRedo {
    let success = appModel.rpcModel.performRedo()
}
```

### アクションの記録と実行

```swift
// 色変更を記録して送信
_ = appModel.rpcModel.sendAndRecordColorChange(
    userId: myUserId,
    newColorName: "red"
)

// ストロークを削除（自動的に記録される）
_ = appModel.rpcModel.sendAndRecordStrokeRemoval(strokeId: strokeId)
```

## 設定とカスタマイズ

### 履歴サイズの変更

```swift
// 最大100個のアクションを保持（デフォルト）
self.undoRedoManager = UndoRedoManager(maxSize: 100)

// 最大50個に減らす
self.undoRedoManager = UndoRedoManager(maxSize: 50)
```

### カスタム除外ルールの設定

```swift
// カスタムの除外判定を設定
self.undoRedoManager = UndoRedoManager(
    maxSize: 100,
    shouldExcludeMethod: { method in
        // カスタムロジック
        switch method {
        case .paintingEntity(.addStrokePoint):
            return true
        default:
            return false
        }
    }
)
```

## 技術的な詳細

### 履歴管理の仕組み

UndoRedoManagerは固定長の配列をキューとして使用します：

```
actions: [Action1, Action2, Action3, Action4, Action5]
                                            ^
                                      currentIndex = 5
```

- `currentIndex`は次にUndoする位置を指します
- Undo実行時：`currentIndex`を減らし、その位置のアクションのundoメソッドを実行
- Redo実行時：`currentIndex`の位置のアクションのredoメソッドを実行し、`currentIndex`を増やす
- 新規アクション追加時：`currentIndex`以降のアクションを破棄

### Undo後の新規アクション

Undoを実行した後に新しいアクションを追加すると、Redo履歴は自動的に破棄されます：

```
初期状態:
actions: [A, B, C, D, E]
                    ^
              currentIndex = 5

2回Undo後:
actions: [A, B, C, D, E]
              ^
        currentIndex = 3

新規アクションF追加:
actions: [A, B, C, F]
                  ^
            currentIndex = 4
```

### 型安全性

Undo/Redoシステムは完全に型安全です：

- `Method`と`Param`は列挙型で定義
- コンパイル時に型チェックが行われる
- 実行時エラーのリスクが最小化

## パフォーマンス考慮事項

### メモリ使用量

- 各アクションは`Method`と`Param`を保持
- `maxSize`の設定により、メモリ使用量を制御可能
- デフォルトの100アクションは通常のユースケースに適切

### 実行効率

- Undo/Redoの実行は既存のRPCシステムを利用
- 追加のオーバーヘッドは最小限
- 履歴の検索は配列インデックスアクセスで高速

## 今後の拡張可能性

### 拡張可能なポイント

1. **グループ化されたアクション**: 複数の操作を1つのUndoアクションとして扱う
2. **永続化**: アクション履歴をディスクに保存
3. **ピア間同期**: Undo/Redoを他のピアと同期
4. **カスタムアクション**: 新しいRPCメソッドの追加時に自動対応

## トラブルシューティング

### よくある問題

**Q: Undoが動作しない**
- アクションが正しく記録されているか確認
- 除外メソッドに該当していないか確認
- `getHistoryInfo()`で履歴を確認

**Q: メモリ使用量が多い**
- `maxSize`を減らすことを検討
- 不要な履歴を`clear()`でクリア

**Q: 特定の操作をUndo対象にしたい/したくない**
- `shouldExcludeMethod`クロージャをカスタマイズ

## まとめ

このUndo/Redo実装は：

- ✅ 型安全で拡張可能
- ✅ RPCEntityシステムと完全に統合
- ✅ 選択的な操作除外をサポート
- ✅ 最小限のコード変更で既存機能に統合可能
- ✅ パフォーマンスへの影響が最小限

詳細な使用例は`docs/UndoRedoUsageExample.swift`を参照してください。
