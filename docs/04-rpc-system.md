# 4. RPCシステム

## 概要

Spatial Painting RPCアプリケーションのRPCシステムは、型安全で拡張可能な分散通信アーキテクチャを提供します。各デバイス間でリアルタイムに状態を同期し、協調的なペイント体験を実現します。

## RPC アーキテクチャ

### 基本構造
```
[Client Device]                    [Peer Device]
     │                                  │
     ▼                                  ▼
┌─────────────┐                  ┌─────────────┐
│ RequestSchema│                  │ RequestSchema│
└─────────────┘                  └─────────────┘
     │                                  │
     ▼                                  ▼
┌─────────────┐                  ┌─────────────┐
│ JSON Encode │                  │ JSON Decode │
└─────────────┘                  └─────────────┘
     │                                  │
     ▼                                  ▼
┌─────────────┐                  ┌─────────────┐
│PeerManager  │  ────────────→   │PeerManager  │
└─────────────┘   MultipeerConn  └─────────────┘
                                       │
                                       ▼
                               ┌─────────────┐
                               │ RPCModel    │
                               │.receiveReq  │
                               └─────────────┘
```

## 型システム

### Method 列挙型
すべてのRPCメソッドを型安全に定義します。

```swift
enum Method: Codable {
    case error(ErrorEntitiy.Method)
    case coordinateTransformEntity(CoordinateTransformEntity.Method)
    case paintingEntity(PaintingEntity.Method)
}
```

### Param 列挙型
メソッドに対応するパラメータを型安全に管理します。

```swift
enum Param: Codable {
    case error(ErrorEntitiy.Param)
    case coordinateTransformEntity(CoordinateTransformEntity.Param)
    case paintingEntity(PaintingEntity.Param)
}
```

### RequestSchema
RPC リクエストの構造を定義します。

```swift
struct RequestSchema: Codable {
    let id: UUID                    // 通信の一意なID
    let peerId: Int                // 通信元のピアID
    let method: Method             // RPCメソッド
    let param: Param               // メソッドの引数
}
```

## RPCEntity プロトコル

### 基底プロトコル
```swift
protocol RPCEntity: Codable {
    associatedtype Method: RPCEntityMethod
    associatedtype Param: RPCEntityParam
}

protocol RPCEntityMethod: Codable {}

protocol RPCEntityParam: Codable {
    func encode(to encoder: Encoder) throws
    init(from decoder: Decoder) throws
    associatedtype CodingKeys: CodingKey
}
```

## 具体的なエンティティ

### 1. CoordinateTransformEntity

#### メソッド定義
```swift
enum Method: RPCEntityMethod {
    case initMyPeer        // 自ピアの初期化
    case initOtherPeer     // 他ピアの初期化
    case resetPeer         // ピアのリセット
    case requestTransform  // 座標変換リクエスト
    case setTransform      // 座標変換設定
    case setATransform     // A行列設定
    case setBTransform     // B行列設定
    case clacAffineMatrix  // アフィン行列計算
    case setState          // 状態設定
}
```

#### パラメータ構造体
```swift
struct InitMyPeerParam: Codable {
    let peerId: Int
}

struct SetTransformParam: Codable {
    let peerId: Int
    let matrix: [[Float]]
}

struct SetStateParam: Codable {
    let state: TransformationMatrixPreparationState
}
```

### 2. PaintingEntity

#### メソッド定義
```swift
enum Method: RPCEntityMethod {
    case setStrokeColor           // 色設定
    case removeAllStroke          // 全ストローク削除
    case removeStroke             // 特定ストローク削除
    case addStrokePoint           // ストロークポイント追加
    case addStrokes               // ストローク追加
    case finishStroke             // ストローク終了
    case changeFingerLineWidth    // 線幅変更
}
```

#### パラメータ構造体
```swift
struct SetStrokeColorParam: Codable {
    let strokeColorName: String
}

struct AddStrokePointParam: Codable {
    let point: SIMD3<Float>
    let radius: Float
}

struct ChangeFingerLineWidthParam: Codable {
    let toolName: String
}
```

### 3. ErrorEntity

#### メソッド定義
```swift
enum Method: RPCEntityMethod {
    case error
}

struct ErrorParam: Codable {
    let errorMessage: String
}
```

## RPC実行フロー

### 1. 送信側（sendRequest）
```swift
func sendRequest(_ request: RequestSchema) -> RPCResult {
    // 1. ローカル実行
    var rpcResult = RPCResult()
    switch (request.method, request.param) {
    case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
        rpcResult = coordinateTransforms.setState(param: p)
    case let (.paintingEntity(.setStrokeColor), .paintingEntity(.setStrokeColor(p))):
        painting.setStrokeColor(param: p)
    // ... その他のケース
    }
    
    // 2. JSON エンコード
    guard let requestData = try? jsonEncoder.encode(request) else {
        return RPCResult("Failed to encode request")
    }
    
    // 3. データ送信
    sendExchangeDataWrapper.setData(requestData)
    return rpcResult
}
```

### 2. 受信側（receiveRequest）
```swift
func receiveRequest(_ request: RequestSchema) -> RPCResult {
    var rpcResult = RPCResult()
    switch (request.method, request.param) {
    case let (.paintingEntity(.addStrokePoint), .paintingEntity(.addStrokePoint(p))):
        painting.addStrokePoint(param: p)
    case let (.coordinateTransformEntity(.setTransform), .coordinateTransformEntity(.setTransform(p))):
        rpcResult = coordinateTransforms.setTransform(param: p)
    // ... その他のケース
    }
    
    if !rpcResult.success {
        return error(message: rpcResult.errorMessage, to: request.peerId)
    }
    return rpcResult
}
```

## エラーハンドリング

### RPCResult
```swift
struct RPCResult {
    let success: Bool
    let errorMessage: String
    
    // 成功時
    init() {
        self.success = true
        self.errorMessage = ""
    }
    
    // 失敗時
    init(_ errorMessage: String) {
        self.success = false
        self.errorMessage = errorMessage
    }
}
```

### エラー送信
```swift
func error(message: String, to peerId: Int) -> RPCResult {
    let request = RequestSchema(
        peerId: peerId,
        method: .error(.error),
        param: .error(ErrorParam(errorMessage: message))
    )
    guard let requestData = try? JSONEncoder().encode(request) else {
        return RPCResult("\"\(message)\" is not send Peer")
    }
    sendExchangeDataWrapper.setData(requestData, to: peerId)
    return RPCResult(message)
}
```

## データ同期パターン

### 1. ブロードキャスト型
全ピアに同じデータを送信
```swift
// 例: 色変更をすべてのピアに通知
let request = RequestSchema(
    peerId: mcPeerIDUUIDWrapper.mine.hash,
    method: .paintingEntity(.setStrokeColor),
    param: .paintingEntity(.setStrokeColor(SetStrokeColorParam(strokeColorName: "red")))
)
_ = rpcModel.sendRequest(request)
```

### 2. ユニキャスト型
特定のピアにのみデータを送信
```swift
// 例: 特定のピアに座標データを送信
let request = RequestSchema(
    peerId: targetPeerId,
    method: .coordinateTransformEntity(.setTransform),
    param: .coordinateTransformEntity(.setTransform(param))
)
_ = rpcModel.sendRequest(request, mcPeerId: targetPeerId)
```

### 3. 状態同期型
すべてのピアで状態を同期
```swift
// ローカル実行 + リモート送信
let request = RequestSchema(...)
let result = rpcModel.sendRequest(request)  // ローカル実行 + 送信
// 受信側では receiveRequest が自動実行
```

## リトライ機構と信頼性

### 概要
RPCシステムには、通信の信頼性を向上させるための自動リトライ機構が組み込まれています。送信されたリクエストはキューで管理され、acknowledgment（ack）を受信するまで追跡されます。

### RequestQueue
リクエストの再送管理を担うクラスです。

```swift
@MainActor
class RequestQueue: ObservableObject {
    /// タイムアウト時間（デフォルト: 5秒）
    static let defaultTimeout: TimeInterval = 5.0
    
    /// 最大リトライ回数（デフォルト: 3回）
    static let defaultMaxRetries: Int = 3
    
    /// リクエストをキューに追加
    func enqueue(_ request: RequestSchema)
    
    /// リクエストをキューから削除
    func dequeue(_ requestId: UUID)
    
    /// リトライコールバック
    var onRetry: ((RequestSchema) -> Void)?
}
```

### AcknowledgmentEntity
リクエストの成功を確認するためのエンティティです。

#### メソッド定義
```swift
enum Method: RPCEntityMethod {
    case ack
}
```

#### パラメータ構造体
```swift
struct AckParam: Codable {
    let requestId: UUID  // 確認するリクエストのID
}
```

### リトライフロー

```
[リクエスト送信]
      ↓
[キューに追加] ← タイムスタンプ記録
      ↓
[ピアに送信]
      ↓
[ack受信待機] ← タイマーで監視
      ↓
   タイムアウト？
      ↓
  Yes / No
   ↓     ↓
[再送]  [キューから削除]
```

### 送信側の処理
```swift
func sendRequest(_ request: RequestSchema) -> RPCResult {
    // ローカル実行
    var rpcResult = RPCResult()
    switch (request.method, request.param) {
        // ... メソッド実行
    }
    
    // リクエストを送信
    guard let requestData = try? jsonEncoder.encode(request) else {
        return RPCResult("Failed to encode request")
    }
    
    // キューに追加（リトライ管理開始）
    requestQueue.enqueue(request)
    
    sendExchangeDataWrapper.setData(requestData)
    return rpcResult
}
```

### 受信側の処理
```swift
func receiveRequest(_ request: RequestSchema) -> RPCResult {
    // acknowledgment の処理
    if case let (.acknowledgment(.ack), .acknowledgment(.ack(param))) = 
        (request.method, request.param) {
        // キューから削除
        requestQueue.dequeue(param.requestId)
        return RPCResult()
    }
    
    // 通常のリクエスト処理
    var rpcResult = RPCResult()
    switch (request.method, request.param) {
        // ... メソッド実行
    }
    
    if !rpcResult.success {
        return error(message: rpcResult.errorMessage, to: request.peerId)
    }
    
    // 成功したら ack を送信
    sendAcknowledgment(requestId: request.id, to: request.peerId)
    
    return rpcResult
}
```

### リトライ動作

1. **タイムアウト検出**: 1秒ごとにタイマーがキューをチェック
2. **リトライ判定**: 5秒以上経過したリクエストを検出
3. **再送実行**: リトライカウントが上限未満なら再送
4. **最大リトライ**: 3回のリトライ後、キューから削除

### 設定のカスタマイズ
```swift
// カスタムタイムアウトとリトライ回数
let requestQueue = RequestQueue(timeout: 10.0, maxRetries: 5)
```

## 拡張性

### 新しいエンティティの追加
1. `RPCEntity` プロトコルを実装
2. `Method` 列挙型に追加
3. `Param` 列挙型に追加
4. `RPCModel` でケース処理を追加

### カスタムエンコーディング
各エンティティで独自のエンコーディングロジックを実装可能

このRPCシステムにより、型安全で拡張可能かつ信頼性の高い分散アプリケーションアーキテクチャを実現しています。