# 5. ペイントシステム

## 概要

Spatial Painting RPCのペイントシステムは、3D空間でのリアルタイム描画を実現し、複数のユーザー間でペイント操作を同期します。RealityKitベースの3Dレンダリングと物理シミュレーションを活用しています。

## システム構成

```
┌──────────────────────────────────────────────────────────┐
│                  Painting System                         │
├──────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────┐  │
│  │  PaintingCanvas │    │ AdvancedColorPalletModel   │  │
│  │                 │    │                             │  │
│  │ - 3Dキャンバス   │    │ - カラーパレット            │  │
│  │ - ストローク管理 │    │ - ツール管理                │  │
│  │ - メッシュ生成   │    │ - UI エンティティ           │  │
│  │ - 物理演算      │    │ - 色・サイズ設定            │  │
│  └─────────────────┘    └─────────────────────────────┘  │
│             │                         │                  │
│             └─────────┬─────────────────┘                 │
│                       │                                  │
│  ┌─────────────────────▼──────────────────────────────┐  │
│  │              Stroke Management                     │  │
│  │                                                    │  │
│  │ - Stroke オブジェクト                              │  │
│  │ - StrokePoint 管理                                 │  │
│  │ - リアルタイムメッシュ生成                          │  │
│  │ - 物理コンポーネント統合                            │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## PaintingCanvas

### 概要
`PaintingCanvas` は3D空間でのペイント機能の中核を担うクラスです。ストロークの管理、メッシュ生成、物理演算を統合的に処理します。

### クラス定義
```swift
class PaintingCanvas {
    // メインエンティティ
    let root = Entity()                    // ルートエンティティ
    let tmpRoot = Entity()                 // 一時的なルート
    
    // ストローク管理
    var strokes: [Stroke] = []             // 確定済みストローク
    var tmpStrokes: [Stroke] = []          // 一時ストローク
    var currentStroke: Stroke?             // 現在のストローク
    
    // バウンディングボックス
    var tmpBoundingBoxEntity: Entity = Entity()
    var tmpBoundingBox: BoundingBoxCube = BoundingBoxCube()
    var boundingBoxEntity: ModelEntity = ModelEntity()
    var boundingBoxCenter: SIMD3<Float> = .zero
    
    // 消しゴム機能
    var eraserEntity: Entity = Entity()
    
    // 描画設定
    var activeColor = SimpleMaterial.Color.white
    var maxRadius: Float = 1E-2
    var currentPosition: SIMD3<Float> = .zero
    var isFirstStroke = true
    
    // 衝突検出用ボックス
    let big: Float = 1E2      // 正方向の距離
    let small: Float = 1E-2   // 負方向の距離
}
```

### 主要メソッド

#### 1. addStrokePoint(_:_:)
新しいストロークポイントを追加します。

```swift
func addStrokePoint(_ position: SIMD3<Float>, radius: Float)
```

**処理フロー:**
1. 現在のストロークが存在しない場合、新しいストロークを作成
2. ストロークポイントを追加
3. リアルタイムでメッシュを更新

#### 2. finishStroke()
現在のストロークを完了します。

```swift
func finishStroke()
```

**処理フロー:**
1. 現在のストロークを確定済みリストに移動
2. 一時的なエンティティをクリーンアップ
3. 最終的なメッシュを生成

#### 3. setActiveColor(_:)
アクティブな描画色を設定します。

```swift
func setActiveColor(color: UIColor)
```

#### 4. setMaxRadius(_:)
描画の最大半径（線の太さ）を設定します。

```swift
func setMaxRadius(radius: Float)
```

#### 5. addStrokes(_:)
外部から複数のストロークを一括追加します（RPC経由）。

```swift
func addStrokes(_ strokes: [Stroke])
```

### 物理演算統合
キャンバスは6つの衝突ボックスで構成され、3D空間全体をカバーします。

```swift
// 初期化時に衝突ボックスを設定
root.addChild(addBox(size: [big, big, small], position: [0, 0, -0.5 * big]))  // 前後
root.addChild(addBox(size: [big, big, small], position: [0, 0, +0.5 * big]))
root.addChild(addBox(size: [big, small, big], position: [0, -0.5 * big, 0]))  // 上下
root.addChild(addBox(size: [big, small, big], position: [0, +0.5 * big, 0]))
root.addChild(addBox(size: [small, big, big], position: [-0.5 * big, 0, 0]))  // 左右
root.addChild(addBox(size: [small, big, big], position: [+0.5 * big, 0, 0]))
```

## Stroke クラス

### 概要
`Stroke` は個々のペイントストロークを表現するクラスです。ストロークポイントの管理とメッシュ生成を担当します。

### クラス定義
```swift
class Stroke {
    // 識別子
    var id = UUID()
    
    // ストロークポイント
    var strokePoints: [StrokePoint] = []
    
    // 描画設定
    var color: UIColor = .white
    var radius: Float = 1E-2
    
    // RealityKit エンティティ
    var entity: ModelEntity?
    
    // 状態管理
    var isFinished: Bool = false
}
```

### StrokePoint
```swift
struct StrokePoint {
    let position: SIMD3<Float>     // 3D座標
    let radius: Float              // その点での半径
    let timestamp: Date            // タイムスタンプ
}
```

## AdvancedColorPalletModel

### 概要
カラーパレットとツール選択のUIを管理するクラスです。3D空間に配置されたインタラクティブなパレットを提供します。

### クラス定義
```swift
@MainActor
class AdvancedColorPalletModel: ObservableObject {
    // UI エンティティ
    @Published var colorPalletEntity: Entity = Entity()
    
    // 色管理
    @Published var selectedBasicColorName: String = "white"
    var colorDictionary: [String: UIColor] = [:]
    var colorBalls: ModelEntityCollection<String> = ModelEntityCollection()
    
    // ツール管理
    @Published var selectedToolName: String = "middle"
    var toolBalls: ModelEntityCollection<String> = ModelEntityCollection()
    
    // アニメーション
    @Published var isColorPalletActive: Bool = false
    @Published var isToolPalletActive: Bool = false
}
```

### 色定義
```swift
// 基本色の定義
private let basicColors: [(String, UIColor)] = [
    ("red", .red),
    ("blue", .blue),
    ("green", .green),
    ("yellow", .yellow),
    ("purple", .purple),
    ("orange", .orange),
    ("white", .white),
    ("black", .black)
]
```

### ツール定義
```swift
// ブラシサイズの定義
private let tools: [(String, Float)] = [
    ("small", 0.005),
    ("middle", 0.01),
    ("large", 0.02)
]
```

### 主要メソッド

#### 1. setActiveColor(_:)
アクティブな色を設定し、UIを更新します。

```swift
func setActiveColor(color: UIColor)
```

#### 2. colorPalletEntityActive() / colorPalletEntityDisable()
カラーパレットの表示・非表示を制御します。

```swift
func colorPalletEntityActive()
func colorPalletEntityDisable()
```

#### 3. showColorPallet() / hideColorPallet()
カラーパレット全体の表示状態を制御します。

```swift
func showColorPallet()
func hideColorPallet()
```

## Painting クラス（RPCEntity）

### 概要
`Painting` はRPCシステムと統合されたペイント機能の管理クラスです。他のピアからのペイント操作を受信・処理します。

### クラス定義
```swift
@MainActor
class Painting: ObservableObject {
    @Published var paintingCanvas = PaintingCanvas()
    @Published var advancedColorPalletModel = AdvancedColorPalletModel()
}
```

### RPCメソッド実装

#### 1. setStrokeColor(_:)
色の変更をピア間で同期します。

```swift
func setStrokeColor(param: SetStrokeColorParam) {
    if let color: UIColor = advancedColorPalletModel.colorDictionary[param.strokeColorName] {
        advancedColorPalletModel.colorPalletEntityDisable()
        advancedColorPalletModel.setActiveColor(color: color)
        paintingCanvas.setActiveColor(color: color)
    }
    // UI更新ロジック...
}
```

#### 2. addStrokePoint(_:)
ストロークポイントの追加を処理します。

```swift
func addStrokePoint(param: AddStrokePointParam) {
    paintingCanvas.addStrokePoint(param.point, radius: param.radius)
}
```

#### 3. finishStroke()
ストロークの完了を処理します。

```swift
func finishStroke() {
    paintingCanvas.finishStroke()
}
```

#### 4. changeFingerLineWidth(_:)
線幅の変更を処理します。

```swift
func changeFingerLineWidth(param: ChangeFingerLineWidthParam) {
    if let lineWidth = advancedColorPalletModel.toolBalls.get(withID: param.toolName)?.lineWidth {
        advancedColorPalletModel.colorPalletEntityDisable()
        paintingCanvas.setMaxRadius(radius: Float(lineWidth))
    }
}
```

## リアルタイム同期

### ペイント操作の同期フロー
```
[ユーザーの描画動作]
        ↓
[ハンドトラッキング検出]
        ↓
[PaintingCanvas.addStrokePoint()]
        ↓
[RPC: AddStrokePointParam]
        ↓
[他ピアに送信]
        ↓
[他ピアで描画反映]
```

### 色・ツール変更の同期
```
[カラーパレット操作]
        ↓
[setStrokeColor() ローカル実行]
        ↓
[RPC: SetStrokeColorParam]
        ↓
[全ピアに送信]
        ↓
[全ピアでUI更新]
```

## パフォーマンス最適化

### 1. メッシュ生成の最適化
- リアルタイムでの軽量メッシュ生成
- バッチ処理による効率化

### 2. ネットワーク最適化
- 差分データのみ送信
- 圧縮アルゴリズムの活用

### 3. メモリ管理
- 古いストロークの自動削除
- エンティティプールの活用

このペイントシステムにより、スムーズで応答性の高い協調的な3Dペイント体験を実現しています。