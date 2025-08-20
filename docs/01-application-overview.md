# 1. アプリケーション概要

## 概要
Spatial Painting RPCは、Apple Vision Pro向けに開発された協調型3Dペイントアプリケーションです。複数のユーザーが同じ3D空間で同時にペイント作業を行うことができ、リアルタイムで作品を共有できます。

## 主要機能

### 1. 3D空間ペイント
- **ハンドトラッキング**: 指先の動きを追跡して3D空間にペイント
- **リアルタイム描画**: 指の動きに合わせてリアルタイムでストロークを生成
- **色・ツール選択**: 様々な色とブラシサイズの選択が可能
- **物理シミュレーション**: RealityKitによる物理演算を活用

### 2. マルチユーザー協調機能
- **ピアツーピア通信**: MultipeerConnectivityによる直接通信
- **リアルタイム同期**: 全ユーザーのペイント動作を同期
- **座標系統合**: 異なるデバイス間での座標系を自動調整
- **状態共有**: ペイントの状態、色、ツール設定を共有

### 3. 座標変換システム
- **自動キャリブレーション**: デバイス間の座標系を自動で調整
- **アフィン変換**: 数学的な変換行列による正確な座標変換
- **ホスト・クライアント方式**: 一つのデバイスがホストとなり座標系を統合

## 技術スタック

### フレームワーク
- **SwiftUI**: ユーザーインターフェース構築
- **RealityKit**: 3Dレンダリングと物理シミュレーション
- **ARKit**: 空間認識とハンドトラッキング
- **MultipeerConnectivity**: デバイス間通信

### アーキテクチャパターン
- **MVVM**: Model-View-ViewModel パターン
- **RPC**: Remote Procedure Call による通信
- **Observer Pattern**: 状態変更の監視と通知

## ユーザー体験の流れ

### 1. アプリケーション起動
1. アプリ起動後、3秒待機してImmersive Spaceを有効化
2. 近くのデバイスを自動的に検索・接続

### 2. 座標系設定
1. "Start Sharing" ボタンでマルチユーザーモードに移行
2. 座標変換マトリックスの準備プロセスを実行
3. ホスト・クライアント方式で座標系を統合

### 3. 協調ペイント
1. 統合された座標系内でペイント開始
2. 全ユーザーのストロークがリアルタイムで同期
3. 色やツールの変更も即座に反映

## アプリケーションの状態管理

### 主要な状態
- **SharedCoordinateState**: 座標共有の状態管理
  - `.prepare`: 準備段階
  - `.sharing`: 座標設定中
  - `.shared`: 座標共有完了

- **TransformationMatrixPreparationState**: 座標変換の状態
  - `.initial`: 初期状態
  - `.selecting`: ピア選択中
  - `.getTransformMatrixHost/Client`: 変換行列取得中
  - `.confirm`: 確認中
  - `.prepared`: 準備完了

## ファイル構成

```
spatial-painting-rpc/
├── spatial_painting_rpcApp.swift          # アプリエントリーポイント
├── AppModel.swift                         # アプリケーション状態管理
├── ContentView.swift                      # メインUI
├── ImmersiveView.swift                    # AR/VRビュー
├── ViewModel.swift                        # シーン管理
├── RPCModel.swift                         # RPC通信管理
├── PeerManager.swift                      # ネットワーク管理
├── RPCUtil/                              # RPC関連ユーティリティ
├── ColorPallet/                          # ペイント機能
└── TransformationMatrixPreparationView/  # 座標変換UI
```

この構造により、協調的な3Dペイント体験を実現し、複数のユーザーが同じ空間で創作活動を楽しむことができます。