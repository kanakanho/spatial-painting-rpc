# 2. アーキテクチャ概要

## システム全体構成

Spatial Painting RPCアプリケーションは、以下の主要レイヤーで構成されています：

```
┌─────────────────────────────────────────────────────────┐
│                    View Layer                           │
│  ┌─────────────────┐  ┌─────────────────────────────────┐ │
│  │   ContentView   │  │     ImmersiveView               │ │
│  │                 │  │                                 │ │
│  │  - UI管理       │  │  - AR/VRシーン                  │ │
│  │  - 状態表示     │  │  - ハンドトラッキング          │ │
│  │  - ナビゲーション│  │  - 3Dレンダリング             │ │
│  └─────────────────┘  └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                  Model Layer                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────┐ │
│  │   AppModel      │  │    RPCModel     │  │ ViewModel│ │
│  │                 │  │                 │  │          │ │
│  │  - 全体状態管理 │  │  - RPC通信管理  │  │ - シーン │ │
│  │  - 依存関係管理 │  │  - リクエスト処理│  │   管理   │ │
│  │  - 初期化       │  │  - 状態同期     │  │ - AR処理 │ │
│  └─────────────────┘  └─────────────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                Service Layer                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────┐ │
│  │  PeerManager    │  │ CoordinateTransform│ Painting │ │
│  │                 │  │                 │  │ Canvas   │ │
│  │  - 接続管理     │  │  - 座標変換     │  │ - 3D描画 │ │
│  │  - データ送受信 │  │  - 行列計算     │  │ - ストローク│ │
│  │  - セッション管理│  │  - 状態管理     │  │ - 物理演算│ │
│  └─────────────────┘  └─────────────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                Infrastructure Layer                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────┐ │
│  │MultipeerConnect │  │   RealityKit    │  │  ARKit   │ │
│  │                 │  │                 │  │          │ │
│  │  - P2P通信      │  │  - 3Dレンダリング│ │ - 空間認識│ │
│  │  - 自動検索     │  │  - 物理演算     │  │ - ハンド │ │
│  │  - 暗号化       │  │  - エンティティ │  │   追跡   │ │
│  └─────────────────┘  └─────────────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────┘
```

## データフロー

### 1. ペイント操作のデータフロー
```
[ユーザーの手の動き]
        ↓
[ARKit: ハンドトラッキング]
        ↓
[ViewModel: 座標処理]
        ↓
[PaintingCanvas: ストローク生成]
        ↓
[RPCModel: 状態同期]
        ↓
[PeerManager: データ送信]
        ↓
[他のピア: 描画反映]
```

### 2. RPC通信のデータフロー
```
[リクエスト生成]
        ↓
[RequestSchema: 型安全な構造化]
        ↓
[JSON Encoder: シリアライズ]
        ↓
[ExchangeDataWrapper: データラップ]
        ↓
[PeerManager: MultipeerConnectivity]
        ↓
[受信側: デシリアライズ]
        ↓
[RPCModel: メソッド実行]
```

### 3. 座標変換のデータフロー
```
[デバイス1: ローカル座標]    [デバイス2: ローカル座標]
        ↓                           ↓
[座標データ交換]  ←→  [座標データ交換]
        ↓                           ↓
[アフィン変換行列計算]
        ↓
[統一座標系での描画]
```

## アーキテクチャパターン

### 1. MVVM (Model-View-ViewModel)
- **Model**: `RPCModel`, `CoordinateTransforms`, `Painting`
- **View**: `ContentView`, `ImmersiveView`, 各UI コンポーネント
- **ViewModel**: `AppModel`, `ViewModel`

### 2. Observer Pattern
- `@ObservedObject`, `@Published` を使用した状態変更の監視
- リアルタイムでUIと状態を同期

### 3. Protocol-Oriented Programming
- `RPCEntity`, `RPCEntityMethod`, `RPCEntityParam` による型安全性
- 拡張可能なRPCシステムの設計

### 4. Dependency Injection
- `AppModel` で依存関係を管理
- 各コンポーネント間の疎結合を実現

## 主要コンポーネント間の関係

### AppModel の役割
```swift
class AppModel: ObservableObject {
    // 状態管理
    @Published var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // コアコンポーネント
    var model = ViewModel()              // AR/VRシーン管理
    @ObservedObject var rpcModel: RPCModel    // RPC通信
    var peerManager: PeerManager         // ネットワーク管理
    
    // データラッパー
    @ObservedObject var sendExchangeDataWrapper = ExchangeDataWrapper()
    @ObservedObject var receiveExchangeDataWrapper = ExchangeDataWrapper()
    @ObservedObject var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
}
```

### 通信フロー
1. **初期化**: `AppModel` が全コンポーネントを初期化
2. **接続**: `PeerManager` が近くのデバイスを検出・接続
3. **座標設定**: `CoordinateTransforms` で座標系を統合
4. **ペイント同期**: `Painting` でストロークを同期
5. **表示更新**: `ViewModel` でリアルタイム描画

## 非同期処理とタスク管理

### TaskベースのARKit処理
```swift
.task {
    await appModel.model.processHandUpdates()
}
.task(priority: .low) {
    await appModel.model.processReconstructionUpdates()
}
```

### ObservableObjectによる状態同期
- UI更新の自動化
- ネットワーク通信との統合
- エラーハンドリングの一元化

この構造により、スケーラブルで保守性の高い協調型3Dペイントアプリケーションを実現しています。