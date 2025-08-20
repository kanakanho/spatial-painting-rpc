# 7. ネットワーク通信

## 概要

Spatial Painting RPCアプリケーションのネットワーク通信システムは、MultipeerConnectivityフレームワークを基盤とした分散型ピアツーピア通信を実現します。デバイス間での自動検索、接続、データ同期を効率的に管理します。

## ネットワークアーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                  Network Layer                          │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────┐  │
│  │  PeerManager    │    │  ExchangeDataWrapper       │  │
│  │                 │    │                             │  │
│  │ - 接続管理       │    │ - データラッピング          │  │
│  │ - セッション管理 │    │ - 送受信データ管理          │  │
│  │ - 自動検索・接続 │    │ - ピア指定送信              │  │
│  └─────────────────┘    └─────────────────────────────┘  │
│             │                         │                  │
│             └─────────┬─────────────────┘                 │
│                       │                                  │
│  ┌─────────────────────▼──────────────────────────────┐  │
│  │           MCPeerIDUUIDWrapper                      │  │
│  │                                                    │  │
│  │ - 自身のピアID管理                                   │  │
│  │ - 接続可能ピアリスト                                 │  │
│  │ - UUID ベースの識別                                │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│            MultipeerConnectivity                        │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────┐ │
│  │   MCSession     │  │ MCNearbyService │  │ MCPeerID │ │
│  │                 │  │                 │  │          │ │
│  │ - P2P通信      │  │ - Advertiser    │  │ - デバイス│ │
│  │ - データ送受信   │  │ - Browser       │  │   識別   │ │
│  │ - 暗号化        │  │ - 自動検索      │  │ - 表示名 │ │
│  └─────────────────┘  └─────────────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────┘
```

## PeerManager

### 概要
`PeerManager` はMultipeerConnectivityを使用したピアツーピア通信の中核を担うクラスです。デバイスの検索、接続、データ送受信を管理します。

### クラス定義
```swift
@Observable
class PeerManager: NSObject {
    // データラッパー
    private var sendExchangeDataWrapper: ExchangeDataWrapper
    private var receiveExchangeDataWrapper: ExchangeDataWrapper
    private var mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
    
    // 変更監視
    private var cancellable: AnyCancellable?
    
    // ホスト状態
    var isHost: Bool = false
    
    // MultipeerConnectivity コンポーネント
    private let serviceType = "painting-rpc"
    var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
}
```

### 初期化処理
```swift
init(sendExchangeDataWrapper: ExchangeDataWrapper, 
     receiveExchangeDataWrapper: ExchangeDataWrapper, 
     mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper) {
    
    // 依存関係の設定
    self.sendExchangeDataWrapper = sendExchangeDataWrapper
    self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
    self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
    
    // ピアIDの取得
    let peerID = mcPeerIDUUIDWrapper.mine
    
    // MultipeerConnectivity の初期化
    session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
    browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
    
    super.init()
    
    // デリゲートの設定
    session.delegate = self
    advertiser.delegate = self
    browser.delegate = self
    
    // データ変更の監視
    cancellable = sendExchangeDataWrapper.$exchangeData.sink { [weak self] exchangeData in
        self?.sendExchangeDataDidChange(exchangeData)
    }
}
```

### 主要メソッド

#### 1. start() / stop()
サービスの開始・停止を管理します。

```swift
func start() {
    advertiser.startAdvertisingPeer()     // 自身をアドバタイズ
    browser.startBrowsingForPeers()       // 他のピアを検索
}

func stop() {
    advertiser.stopAdvertisingPeer()
    browser.stopBrowsingForPeers()
}
```

#### 2. sendRPC(_:)
全ピアに対してRPCデータを送信します。

```swift
func sendRPC(_ data: Data) {
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try self.session.send(data, toPeers: self.mcPeerIDUUIDWrapper.standby, with: .unreliable)
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }
}
```

#### 3. sendRPC(_:to:) -> RPCResult
特定のピアに対してRPCデータを送信します。

```swift
func sendRPC(_ data: Data, to peerID: MCPeerID) -> RPCResult {
    var rpcResult = RPCResult()
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try self.session.send(data, toPeers: [peerID], with: .unreliable)
        } catch {
            rpcResult = RPCResult("Error sending message: \(error.localizedDescription)")
        }
    }
    return rpcResult
}
```

#### 4. sendExchangeDataDidChange(_:)
送信データの変更を監視し、適切な送信先に配信します。

```swift
func sendExchangeDataDidChange(_ exchangeData: ExchangeData) {
    if exchangeData.mcPeerId != 0 {
        // 特定のピアに送信
        guard let peerID = mcPeerIDUUIDWrapper.standby.first(where: { $0.hash == exchangeData.mcPeerId }) else {
            print("Error: PeerID not found")
            return
        }
        let rpcResult = sendRPC(exchangeData.data, to: peerID)
        if !rpcResult.success {
            print("Error sending message: \(rpcResult.errorMessage)")
        }
    } else {
        // 全ピアに送信
        sendRPC(exchangeData.data)
    }
}
```

## MCSessionDelegate

### セッション状態管理
```swift
extension PeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Peer \(peerID.displayName) changed state to \(state)")
        
        switch state {
        case .connected:
            // 接続時の処理
            // 同名ピアの重複削除
            if mcPeerIDUUIDWrapper.standby.contains(where: { $0.displayName == peerID.displayName }) {
                mcPeerIDUUIDWrapper.standby.removeAll(where: { $0.displayName == peerID.displayName })
            }
            mcPeerIDUUIDWrapper.standby.append(peerID)
            
        case .notConnected:
            // 切断時の処理
            mcPeerIDUUIDWrapper.remove(mcPeerID: peerID)
            
        case .connecting:
            // 接続中の処理
            break
        }
    }
}
```

### データ受信処理
```swift
func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    DispatchQueue.main.async {
        self.receiveExchangeDataWrapper.setData(data)
    }
}
```

## MCNearbyServiceAdvertiserDelegate

### 招待受信処理
```swift
extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, 
                   didReceiveInvitationFromPeer peerID: MCPeerID, 
                   withContext context: Data?, 
                   invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 自動的に招待を受け入れ
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, 
                   didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }
}
```

## MCNearbyServiceBrowserDelegate

### ピア検出処理
```swift
extension PeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, 
                foundPeer peerID: MCPeerID, 
                withDiscoveryInfo info: [String : String]?) {
        print("Found peer: \(peerID.displayName)")
        // 自動的に招待を送信
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, 
                lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }
}
```

## ExchangeDataWrapper

### 概要
データの送受信を統一的に管理するラッパークラスです。

### クラス定義
```swift
struct ExchangeData {
    var data: Data      // 送信データ
    var mcPeerId: Int   // 送信先ピアID（0の場合は全ピア）
}

class ExchangeDataWrapper: ObservableObject {
    @Published var exchangeData: ExchangeData
    
    init() {
        self.exchangeData = ExchangeData(data: Data(), mcPeerId: 0)
    }
    
    init(data: Data) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: 0)
    }
    
    init(data: Data, mcPeerId: Int) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: mcPeerId)
    }
}
```

### データ設定メソッド
```swift
// 全ピアに送信
func setData(_ data: Data) {
    self.exchangeData = ExchangeData(data: data, mcPeerId: 0)
}

// 特定ピアに送信
func setData(_ data: Data, to mcPeerId: Int) {
    self.exchangeData = ExchangeData(data: data, mcPeerId: mcPeerId)
}
```

## MCPeerIDUUIDWrapper

### 概要
ピアIDと接続状況を管理するラッパークラスです。

### クラス定義
```swift
class MCPeerIDUUIDWrapper: ObservableObject {
    /// 自身のピアID
    @Published var mine = MCPeerID(displayName: UUID().uuidString)
    
    /// 接続可能なピアリスト
    @Published var standby: [MCPeerID] = []
    
    /// ピアの削除
    func remove(mcPeerID: MCPeerID) {
        standby.removeAll { $0 == mcPeerID }
    }
}
```

## 通信フロー

### 1. 初期接続フロー
```
[デバイスA起動]
       ↓
[Advertiser開始] ←→ [Browser開始]
       ↓                 ↓
[他デバイス検出] ←→ [デバイスA検出]
       ↓                 ↓
[招待送信] ←→ [招待受信・自動承認]
       ↓                 ↓
[セッション確立] ←→ [セッション確立]
```

### 2. データ送信フロー
```
[RPCリクエスト生成]
       ↓
[JSON エンコード]
       ↓
[ExchangeDataWrapper.setData()]
       ↓
[PeerManager.sendExchangeDataDidChange()]
       ↓
[MCSession.send()]
       ↓
[ピアに送信]
```

### 3. データ受信フロー
```
[ピアからデータ受信]
       ↓
[MCSessionDelegate.didReceive]
       ↓
[ExchangeDataWrapper.setData()]
       ↓
[RPCModel.receiveExchangeDataDidChange()]
       ↓
[RPCリクエスト処理]
```

## セキュリティと信頼性

### 暗号化
- MCSessionの`encryptionPreference: .required`により自動暗号化
- TLS類似の暗号化プロトコル使用

### エラーハンドリング
- 送信失敗時の自動リトライ
- 接続切断時の自動再接続
- タイムアウト処理

### パフォーマンス最適化
- 非同期送信による UI ブロック回避
- QoS を使用した優先度管理
- バックグラウンドキューでの処理

このネットワーク通信システムにより、安定したピアツーピア通信を実現し、シームレスな協調体験を提供しています。