# 3. コアモデル

## AppModel

### 概要
`AppModel` はアプリケーション全体の状態を管理するメインクラスです。全てのコンポーネントの依存関係を管理し、アプリケーションのライフサイクルを制御します。

### クラス定義
```swift
@MainActor
class AppModel: ObservableObject {
    // Immersive Spaceの管理
    let immersiveSpaceID = "ImmersiveSpace"
    @Published var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // コアコンポーネント
    var model = ViewModel()
    @ObservedObject var rpcModel: RPCModel
    var peerManager: PeerManager
    
    // データ交換ラッパー
    @ObservedObject var sendExchangeDataWrapper = ExchangeDataWrapper()
    @ObservedObject var receiveExchangeDataWrapper = ExchangeDataWrapper()
    @ObservedObject var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
    
    // ファイル管理
    var externalStrokeFileWapper: ExternalStrokeFileWapper = ExternalStrokeFileWapper()
}
```

### 主要プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `immersiveSpaceID` | String | Immersive Spaceの識別子 |
| `immersiveSpaceState` | ImmersiveSpaceState | Immersive Spaceの状態（closed/inTransition/open） |
| `model` | ViewModel | AR/VRシーンの管理 |
| `rpcModel` | RPCModel | RPC通信の管理 |
| `peerManager` | PeerManager | ネットワーク接続の管理 |
| `sendExchangeDataWrapper` | ExchangeDataWrapper | 送信データのラッパー |
| `receiveExchangeDataWrapper` | ExchangeDataWrapper | 受信データのラッパー |
| `mcPeerIDUUIDWrapper` | MCPeerIDUUIDWrapper | ピアIDの管理 |

### 初期化フロー
1. データ交換ラッパーの作成
2. RPCModelの初期化（ラッパーを注入）
3. PeerManagerの初期化（ラッパーを注入）
4. 依存関係の確立

---

## RPCModel

### 概要
`RPCModel` はRPC（Remote Procedure Call）通信を管理し、ピア間での状態同期を実現します。型安全なリクエスト・レスポンス処理を提供します。

### クラス定義
```swift
@MainActor
class RPCModel: ObservableObject {
    // データ管理
    private var sendExchangeDataWrapper = ExchangeDataWrapper()
    private var receiveExchangeDataWrapper = ExchangeDataWrapper()
    var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
    
    // JSON処理
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    
    // 主要エンティティ
    @Published var coordinateTransforms = CoordinateTransforms()
    @Published var painting = Painting()
    
    // 変更監視
    private var cancellable: AnyCancellable?
}
```

### 主要メソッド

#### 1. sendRequest(_:) -> RPCResult
すべてのピアに対してRPCリクエストを送信します。

```swift
func sendRequest(_ request: RequestSchema) -> RPCResult
```

**対応するRPCメソッド:**
- 座標変換: `requestTransform`, `setTransform`, `setState`
- ペイント: `finishStroke`, `setStrokeColor`, `removeAllStroke`, `removeStroke`, `changeFingerLineWidth`

#### 2. sendRequest(_:mcPeerId:) -> RPCResult
特定のピアに対してRPCリクエストを送信します。

```swift
func sendRequest(_ request: RequestSchema, mcPeerId: Int) -> RPCResult
```

#### 3. receiveRequest(_:) -> RPCResult
受信したRPCリクエストを処理します。

```swift
func receiveRequest(_ request: RequestSchema) -> RPCResult
```

### RPCエンティティ管理

#### CoordinateTransforms
```swift
@Published var coordinateTransforms = CoordinateTransforms()
```
- 座標変換の状態管理
- アフィン変換行列の計算
- ピア間での座標系統合

#### Painting
```swift
@Published var painting = Painting()
```
- 3Dペイント機能の管理
- ストロークの同期
- 色・ツール設定の共有

---

## ViewModel

### 概要
`ViewModel` はAR/VRシーンの管理を担当し、ハンドトラッキング、空間認識、3Dレンダリングを制御します。

### クラス定義
```swift
@Observable
@MainActor
class ViewModel {
    // カラーパレット管理
    var colorPalletModel: AdvancedColorPalletModel = AdvancedColorPalletModel()
    
    // ARKit セッション
    var session = ARKitSession()
    var handTracking = HandTrackingProvider()
    var sceneReconstruction = SceneReconstructionProvider()
    
    // エンティティ管理
    private var meshEntities = [UUID: ModelEntity]()
    var contentEntity = Entity()
    var leftHandEntity = Entity()
    var rightHandEntity = Entity()
    
    // ハンドトラッキング状態
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    var latestLeftIndexFingerCoordinates: simd_float4x4 = .init()
    
    // 操作ロック
    enum OperationLock { case none, right, left }
    var entitiyOperationLock = OperationLock.none
    
    // 物理マテリアル
    let material = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.0)
}
```

### 主要プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `colorPalletModel` | AdvancedColorPalletModel | カラーパレットとツール管理 |
| `session` | ARKitSession | ARKitセッション |
| `handTracking` | HandTrackingProvider | ハンドトラッキング機能 |
| `sceneReconstruction` | SceneReconstructionProvider | 空間認識機能 |
| `meshEntities` | [UUID: ModelEntity] | 空間メッシュエンティティの管理 |
| `contentEntity` | Entity | メインコンテンツエンティティ |
| `latestHandTracking` | HandsUpdates | 最新のハンドトラッキングデータ |
| `entitiyOperationLock` | OperationLock | エンティティ操作のロック状態 |

### 主要メソッド

#### 1. processHandUpdates()
ハンドトラッキングの更新を処理します。

```swift
func processHandUpdates() async
```

#### 2. processReconstructionUpdates()
空間再構築の更新を処理します。

```swift
func processReconstructionUpdates() async
```

#### 3. showFingerTipSpheres() / dismissFingerTipSpheres()
指先のガイド球の表示・非表示を制御します。

```swift
func showFingerTipSpheres()
func dismissFingerTipSpheres()
```

---

## モデル間の連携

### 依存関係の流れ
```
AppModel
  ├── ViewModel (AR/VRシーン管理)
  ├── RPCModel (通信・状態管理)
  │   ├── CoordinateTransforms (座標変換)
  │   └── Painting (ペイント機能)
  └── PeerManager (ネットワーク管理)
```

### データバインディング
- `@ObservedObject` と `@Published` による双方向データバインディング
- リアルタイムな状態同期
- 型安全なデータ交換

### エラーハンドリング
- `RPCResult` による統一されたエラー管理
- 各レイヤーでのエラー伝播
- ユーザーフレンドリーなエラー表示

この3つのコアモデルが連携することで、スケーラブルで保守性の高いアーキテクチャを実現しています。