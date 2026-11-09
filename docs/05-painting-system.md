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
│  │ - Stroke / Painter の Entity と Component          │  │
│  │ - StrokeGeometry による形状データの管理            │  │
│  │ - System によるメッシュとコライダーの生成          │  │
│  │ - 制御点の選択と強調表示                            │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## ストロークの ECS 構成

ストロークと描画の状態は、RealityKit の Entity と Component で管理します。`PaintingCanvas` は Entity ツリーを操作する入口で、ストロークの配列は持ちません。

### Entity の構成

```
Canvas root（StrokeAssetsComponent, ControlPointSelectionComponent）
├─ 衝突ボックス × 6
├─ Stroke root（StrokeComponent, StrokeStyleComponent, StrokeRootComponent）× n
│  ├─ Mesh（StrokeMeshComponent, ModelComponent）
│  ├─ Point root（BezierPointComponent）× n
│  │  ├─ end / startHandle / endHandle（BezierStrokeControlComponent）
│  │  └─ line（BezierControlLineComponent）
│  └─ Collider（StrokeColliderComponent）
├─ tmpRoot
│  └─ boundingBoxEntity（StrokeGroupComponent）
│     └─ 一時ストロークの Stroke root × n
└─ paintersRoot
   └─ Painter（PainterComponent, BrushComponent, DraftStrokeComponent）× ユーザー数
```

`PaintingCanvas.strokes` と `tmpStrokes` は、参照のたびに Entity ツリーから導出します。データ源は Entity ツリーだけです。

### Component

| Component | 持たせる Entity | 役割 |
|---|---|---|
| `StrokeComponent` | Stroke root | ID と `StrokeGeometry` への参照 |
| `StrokeStyleComponent` | Stroke root | 色、太さ、カリング |
| `StrokeRootComponent` | Stroke root | ストロークの UUID |
| `StrokeMeshComponent` | Mesh | メッシュを持つ子 Entity の目印 |
| `StrokeColliderComponent` | Collider | 消しゴムと選択の当たり判定 |
| `BezierPointComponent` | Point root | 制御点の ID |
| `BezierStrokeControlComponent` | end / handle | 操作対象の制御点 |
| `BezierControlLineComponent` | line | ハンドルを結ぶ線の目印 |
| `StrokeGroupComponent` | `boundingBoxEntity` | 編集モードで選択した元のストローク |
| `PainterComponent` | Painter | ユーザー ID |
| `BrushComponent` | Painter | ユーザーの色と太さ |
| `DraftStrokeComponent` | Painter | 描画中のストロークと飛びの判定 |
| `ControlPointSelectionComponent` | Canvas root | 選択中の制御点と操作の基準位置 |
| `SelectedControlPointComponent` | end / handle | 選択中の目印 |
| `StrokeAssetsComponent` | Canvas root | 複製元のプロトタイプ。System へ依存を渡す手段 |

### StrokeGeometry

`points` と `bezierPoints` の実体は `StrokeGeometry` クラスに置き、`StrokeComponent` は参照だけを持ちます。

点列を Component の値で持つと、取り出して変更するたびに配列全体がコピーされます。クラスに置くと、その場で追記できます。`StrokeGeometry` はストロークごとに持つので、寿命は Entity に従います。

`points` は描画中は入力で、ベジェ化のあとは `bezierPoints` からの派生データです。再サンプリングは `resamplePoints()` にまとめています。

- `BezierStroke.points` の `append` は配列全体をコピーするので、点の追加は `geometry.points` へ直接行う
- `geometry` が共有されるので、Stroke の Entity は `clone` しない

### System と Dirty タグ

| System | タグ | 処理 |
|---|---|---|
| `StrokeMeshSystem` | `StrokeMeshDirty` | `StrokeMeshBuilder` でメッシュを生成し、マテリアルを更新する |
| `StrokeColliderSystem` | `StrokeColliderDirty` | コライダーを作り直す。1 つの Entity に、点 5 個ごとに箱の形状を並べる |
| `ControlPointHighlightSystem` | `ControlPointAppearanceDirty` | 選択状態に合わせて制御点の見た目を更新する |

更新が必要な Entity に Dirty タグを付けると、次のフレームで System が 1 回だけ処理します。1 フレームに複数の点が届いても、メッシュの生成は 1 回で済みます。

### 消しゴム用コライダー

コライダーはストロークごとに 1 つの Entity で、点 5 個ごとに一辺 2.5 cm の箱の形状を並べた `CollisionComponent` を持ちます。

判定の設定（mode、group、mask）とジェスチャーの対象であることは、Reality Composer Pro の `collider` から `CollisionComponent` と `InputTargetComponent` を複製して引き継ぎます。以前は点ごとにプロトタイプの Entity を複製していましたが、1 フレームに数十 ms かかりフレーム落ちの原因になっていたので、この方式に変えました。

点が重なっている区間では、指が触れている間に `CollisionEvents.Began` が届くのは 1 回だけです。消しゴムと選択は最初の Began で処理するので、動作は変わりません。

### 同期処理のまま残すもの

次の処理は System に移しません。

| 処理 | 理由 |
|---|---|
| `points` と `bezierPoints` の更新、再サンプリング | 直後に `finishControlPoint` や `transferData` が読む。RPC の順序も保つ |
| メッシュの子 Entity の Transform の設定 | `addTmpStrokes` が直後に親を付け替える |
| 制御点の Entity の位置の同期 | ジェスチャーの終了時に位置を読む |
| Painter の更新 | `addStrokePoint`、`addBezierStrokePoints`、`finishStroke` は順序に意味がある |
| 入力処理 | System にしても描画の利点がなく、遅延と点の間隔の変化が生じる |

System は Scene の中の Entity しか処理しません。ImmersiveSpace を閉じている間の Dirty タグは残り、次に開いたときに処理されます。

### BezierStroke

`BezierStroke` は Stroke の Entity を操作するための薄いラッパーです。独自の状態を持たないので、同一性は `uuid` で比較します。入力処理と RPC の送信が利用しています。

## PaintingCanvas

### 主要メソッド

| メソッド | 処理 |
|---|---|
| `addPoint(_:_:userId:)` | ユーザーの描画中のストロークに点を追加する |
| `addBezierStrokePoints(userId:bezierPoints:)` | 描画中のストロークにベジェの制御点を設定する |
| `individualPoints2Bezier(userId:)` | 描画中のストロークをベジェ化する |
| `finishStroke(_:)` | 描画中のストロークを確定する。8 点未満なら削除する |
| `setActiveColor(userId:color:)` / `setMaxRadius(userId:radius:)` | ユーザーの筆を設定する |
| `addBezierStrokes(_:)` | 外部のストロークを追加する（RPC 経由） |
| `addTmpStrokes(_:)` | 一時ストロークをグループに追加する |
| `confirmTmpStrokes()` | 一時ストロークを確定し、新しいストロークを返す |
| `addMovingStroke(_:)` / `confirmMovingStrokes()` | 編集モードの選択と確定 |
| `selectControlPoint(_:)` / `clearControlPointSelection()` | 制御点の選択 |

### 描画の判定

`DraftStrokeComponent.step` が次の点の扱いを決めます。

1. 最初の点は無視する
2. 前の点から 0.1 m 以上離れていたら、手の位置が飛んだとみなし、描画中のストロークを手放す
3. それ以外はストロークに追加する

### 物理演算統合

キャンバスは 6 つの衝突ボックスで構成され、3D 空間全体をカバーします。ボックスの生成は `addCanvasBoxes()` にまとめています。

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