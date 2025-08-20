# 9. クラス関係図とシステム概要

## 全体システム図

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Spatial Painting RPC                                 │
│                        Vision Pro AR/VR 協調ペイントアプリ                       │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────────┐
│                               Application Layer                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│  spatial_painting_rpcApp                                                       │
│  ├── WindowGroup (ContentView)                                                 │
│  ├── WindowGroup (ExternalStrokeView)                                          │
│  └── ImmersiveSpace (ImmersiveView)                                            │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                Model Layer                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   AppModel      │  │    RPCModel     │  │   ViewModel     │  │ PeerManager  │ │
│  │                 │  │                 │  │                 │  │              │ │
│  │ • 全体状態管理   │  │ • RPC通信管理   │  │ • AR/VRシーン   │  │ • ネットワーク│ │
│  │ • 依存関係管理   │  │ • リクエスト処理 │  │ • ハンドトラッキング│  │   管理      │ │
│  │ • ライフサイクル │  │ • 状態同期      │  │ • 空間認識      │  │ • ピア接続   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Business Logic Layer                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐  ┌─────────────────────────────────────┐ │
│  │        CoordinateTransforms         │  │            Painting                 │ │
│  │                                     │  │                                     │ │
│  │ • 座標変換管理                       │  │ • 3Dペイント機能                     │ │
│  │ • アフィン変換行列計算               │  │ • ストローク管理                     │ │
│  │ • ピア間座標同期                     │  │ • カラーパレット                     │ │
│  │ • 状態管理                          │  │ • リアルタイム描画                   │ │
│  └─────────────────────────────────────┘  └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────────┐
│                             Infrastructure Layer                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │MultipeerConnect │  │   RealityKit    │  │    ARKit     │  │   ExchangeData   │ │
│  │                 │  │                 │  │              │  │                  │ │
│  │ • P2P通信       │  │ • 3Dレンダリング │  │ • 空間認識   │  │ • データラッピング│ │
│  │ • 自動検索      │  │ • 物理演算      │  │ • ハンド追跡 │  │ • ピア管理       │ │
│  │ • 暗号化        │  │ • エンティティ   │  │ • セッション │  │ • JSON処理       │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘  └──────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 主要クラス関係図

### コアモデルの関係
```
AppModel (中央制御)
├── model: ViewModel
├── rpcModel: RPCModel
├── peerManager: PeerManager
├── sendExchangeDataWrapper: ExchangeDataWrapper
├── receiveExchangeDataWrapper: ExchangeDataWrapper
├── mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
└── externalStrokeFileWapper: ExternalStrokeFileWapper

RPCModel (RPC通信管理)
├── coordinateTransforms: CoordinateTransforms
├── painting: Painting
├── sendExchangeDataWrapper: ExchangeDataWrapper (注入)
├── receiveExchangeDataWrapper: ExchangeDataWrapper (注入)
└── mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper (注入)

ViewModel (AR/VRシーン管理)
├── colorPalletModel: AdvancedColorPalletModel
├── session: ARKitSession
├── handTracking: HandTrackingProvider
├── sceneReconstruction: SceneReconstructionProvider
├── meshEntities: [UUID: ModelEntity]
├── contentEntity: Entity
├── leftHandEntity: Entity
└── rightHandEntity: Entity
```

### RPC システムの関係
```
RequestSchema
├── id: UUID
├── peerId: Int
├── method: Method
└── param: Param

Method (enum)
├── error(ErrorEntitiy.Method)
├── coordinateTransformEntity(CoordinateTransformEntity.Method)
└── paintingEntity(PaintingEntity.Method)

Param (enum)
├── error(ErrorEntitiy.Param)
├── coordinateTransformEntity(CoordinateTransformEntity.Param)
└── paintingEntity(PaintingEntity.Param)

CoordinateTransformEntity.Method
├── initMyPeer
├── initOtherPeer
├── resetPeer
├── requestTransform
├── setTransform
├── setATransform
├── setBTransform
├── clacAffineMatrix
└── setState

PaintingEntity.Method
├── setStrokeColor
├── removeAllStroke
├── removeStroke
├── addStrokePoint
├── addStrokes
├── finishStroke
└── changeFingerLineWidth
```

### ペイントシステムの関係
```
Painting
├── paintingCanvas: PaintingCanvas
└── advancedColorPalletModel: AdvancedColorPalletModel

PaintingCanvas
├── root: Entity
├── strokes: [Stroke]
├── tmpStrokes: [Stroke]
├── currentStroke: Stroke?
├── boundingBoxEntity: ModelEntity
├── eraserEntity: Entity
├── activeColor: SimpleMaterial.Color
└── maxRadius: Float

Stroke
├── id: UUID
├── strokePoints: [StrokePoint]
├── color: UIColor
├── radius: Float
├── entity: ModelEntity?
└── isFinished: Bool

AdvancedColorPalletModel
├── colorPalletEntity: Entity
├── selectedBasicColorName: String
├── colorDictionary: [String: UIColor]
├── colorBalls: ModelEntityCollection<String>
├── selectedToolName: String
├── toolBalls: ModelEntityCollection<String>
├── isColorPalletActive: Bool
└── isToolPalletActive: Bool
```

### ネットワーク通信の関係
```
PeerManager
├── sendExchangeDataWrapper: ExchangeDataWrapper (注入)
├── receiveExchangeDataWrapper: ExchangeDataWrapper (注入)
├── mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper (注入)
├── session: MCSession
├── advertiser: MCNearbyServiceAdvertiser
├── browser: MCNearbyServiceBrowser
└── isHost: Bool

ExchangeDataWrapper
└── exchangeData: ExchangeData
    ├── data: Data
    └── mcPeerId: Int

MCPeerIDUUIDWrapper
├── mine: MCPeerID
└── standby: [MCPeerID]
```

### 座標変換システムの関係
```
CoordinateTransforms
├── coordinateTransformEntity: CoordinateTransformEntity
├── requestTransform: Bool
├── matrixCount: Int
└── matrixCountLimit: Int

CoordinateTransformEntity
├── state: TransformationMatrixPreparationState
├── A: [[Float]]  (4x4行列)
├── B: [[Float]]  (4x4行列)
├── affineMatrixAtoB: simd_float4x4
├── isHost: Bool
├── myPeerId: Int
└── otherPeerId: Int

TransformationMatrixPreparationState (enum)
├── initial
├── selecting
├── getTransformMatrixHost
├── getTransformMatrixClient
├── confirm
└── prepared
```

## データフロー概要

### 1. アプリケーション初期化フロー
```
spatial_painting_rpcApp 起動
→ AppModel 初期化
→ 依存関係の注入 (ExchangeDataWrapper, MCPeerIDUUIDWrapper)
→ RPCModel 初期化 (注入された依存関係を使用)
→ PeerManager 初期化 (注入された依存関係を使用)
→ ViewModel 初期化
→ UI表示
```

### 2. ピア接続フロー
```
ContentView.onAppear()
→ PeerManager.start()
→ MCNearbyServiceAdvertiser.startAdvertisingPeer()
→ MCNearbyServiceBrowser.startBrowsingForPeers()
→ ピア検出・自動接続
→ MCPeerIDUUIDWrapper.standby に追加
```

### 3. 座標変換フロー
```
"Start Sharing" ボタン押下
→ TransformationMatrixPreparationView 表示
→ 状態遷移 (initial → selecting → ... → prepared)
→ 座標データ収集
→ アフィン変換行列計算
→ 統一座標系確立
```

### 4. ペイント同期フロー
```
ハンドトラッキング検出
→ PaintingCanvas.addStrokePoint()
→ RPC リクエスト生成 (AddStrokePointParam)
→ JSON エンコード
→ ExchangeDataWrapper.setData()
→ PeerManager 経由でピアに送信
→ 受信ピアで RPCModel.receiveRequest()
→ Painting.addStrokePoint() 実行
→ 全ピアで描画反映
```

### 5. エラーハンドリングフロー
```
RPC実行エラー発生
→ RPCResult(errorMessage) 生成
→ ErrorEntity.Method.error でエラー送信
→ 受信ピアでエラー表示
→ 必要に応じて状態リセット
```

## 設計パターンと原則

### 適用されている設計パターン

1. **MVVM (Model-View-ViewModel)**
   - Model: RPCModel, CoordinateTransforms, Painting
   - View: ContentView, ImmersiveView, その他UIコンポーネント
   - ViewModel: AppModel, ViewModel

2. **Observer Pattern**
   - @ObservedObject, @Published による状態監視
   - Combine フレームワークによる非同期データ流れ

3. **Dependency Injection**
   - AppModel での依存関係管理
   - コンストラクタ注入による疎結合

4. **Strategy Pattern**
   - RPCEntity による異なる処理戦略
   - プロトコル指向プログラミング

5. **State Pattern**
   - TransformationMatrixPreparationState による状態管理
   - 状態に応じたUIの動的切り替え

6. **Command Pattern**
   - RPC メソッドの抽象化
   - RequestSchema による統一的なコマンド表現

### アーキテクチャ原則

1. **単一責任の原則 (SRP)**
   - 各クラスが明確に定義された単一の責任を持つ

2. **開放閉鎖の原則 (OCP)**
   - RPCEntity プロトコルによる拡張可能性

3. **依存関係逆転の原則 (DIP)**
   - プロトコルベースの設計
   - 依存関係注入による柔軟性

4. **関心の分離 (SoC)**
   - ネットワーク、ペイント、座標変換の明確な分離

## パフォーマンス特性

### リアルタイム性能
- **ハンドトラッキング**: 60fps での追跡
- **ネットワーク通信**: 低遅延P2P通信
- **3Dレンダリング**: RealityKit による最適化

### スケーラビリティ
- **ピア数**: MultipeerConnectivity による制限内
- **ストローク数**: メモリ効率的な管理
- **座標精度**: Float精度での十分な精度

### 信頼性
- **エラーハンドリング**: 多層エラー処理
- **状態一貫性**: RPC による状態同期
- **復旧機能**: 自動再接続とリセット機能

この設計により、拡張性、保守性、性能のバランスが取れた協調型3Dペイントアプリケーションを実現しています。