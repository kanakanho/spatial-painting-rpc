# Spatial Painting RPC - アーキテクチャドキュメント

このディレクトリには、Spatial Painting RPCアプリケーションの全体像、アーキテクチャ、各コンポーネントの詳細なドキュメントが含まれています。

## ドキュメント構成

1. [アプリケーション概要](./01-application-overview.md) - アプリケーションの全体像と基本概念
2. [アーキテクチャ概要](./02-architecture-overview.md) - システム全体のアーキテクチャ
3. [コアモデル](./03-core-models.md) - AppModel、RPCModel、ViewModelの詳細
4. [RPCシステム](./04-rpc-system.md) - RPC通信システムの詳細
5. [ペイントシステム](./05-painting-system.md) - 3Dペイント機能の詳細
6. [ビューレイヤー](./06-view-layer.md) - UI コンポーネントとビューの詳細
7. [ネットワーク通信](./07-network-communication.md) - MultipeerConnectivityとピア管理
8. [座標変換システム](./08-coordinate-transformation.md) - デバイス間座標系の同期システム

## 開発者向けクイックガイド

### アプリケーションの基本概念
- **空間ペイント**: ARKit/RealityKitを使用した3D空間でのペイント機能
- **マルチピア対応**: MultipeerConnectivityによるリアルタイム協調作業
- **RPCアーキテクチャ**: 型安全なRPCシステムによる状態同期
- **座標変換**: 異なるデバイス間での座標系の自動調整

### 主要コンポーネント
- **AppModel**: アプリケーション全体の状態管理
- **RPCModel**: RPC通信とリクエスト処理
- **ViewModel**: AR/VR シーンの管理
- **PeerManager**: ネットワーク通信の管理
- **PaintingCanvas**: 3Dペイントキャンバス
- **CoordinateTransforms**: 座標変換システム

詳細については、各ドキュメントを参照してください。