# 8. 座標変換システム

## 概要

Spatial Painting RPCの座標変換システムは、異なるデバイス間で3D空間の座標系を統一し、すべてのユーザーが同じ仮想空間で協調作業できるようにする重要なコンポーネントです。アフィン変換行列を使用した数学的に正確な座標変換を実現します。

## 座標変換の必要性

### 問題設定
各Vision Proデバイスは独自のローカル座標系を持ちます：
- **デバイスA**: 座標系A（原点、軸の向きがデバイス固有）
- **デバイスB**: 座標系B（原点、軸の向きがデバイス固有）

### 解決方法
アフィン変換行列を計算し、座標系を統一：
```
座標系A → 統一座標系 ← 座標系B
```

## システム構成

```
┌──────────────────────────────────────────────────────────┐
│              Coordinate Transformation System            │
├──────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐  │
│  │           CoordinateTransforms                      │  │
│  │                                                     │  │
│  │ - 座標変換エンティティ管理                           │  │
│  │ - アフィン変換行列計算                               │  │
│  │ - ピア間座標データ交換                               │  │
│  │ - 変換プロセス状態管理                               │  │
│  └─────────────────────────────────────────────────────┘  │
│                          │                               │
│  ┌─────────────────────────▼─────────────────────────────┐  │
│  │        CoordinateTransformEntity                     │  │
│  │                                                     │  │
│  │ - 状態管理 (initial → prepared)                     │  │
│  │ - 行列データ保存 (A, B, AtoB)                      │  │
│  │ - RPC メソッド定義                                   │  │
│  │ - パラメータ構造体                                   │  │
│  └─────────────────────────────────────────────────────┘  │
│                          │                               │
│  ┌─────────────────────────▼─────────────────────────────┐  │
│  │    TransformationMatrixPreparationView              │  │
│  │                                                     │  │
│  │ - ユーザーインターフェース                           │  │
│  │ - プロセスガイダンス                                 │  │
│  │ - 座標データ確認・承認                               │  │
│  │ - エラーハンドリング                                 │  │
│  └─────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## 座標変換状態管理

### TransformationMatrixPreparationState
```swift
enum TransformationMatrixPreparationState: Codable {
    case initial                    // 初期状態
    case selecting                  // ピア選択中
    case getTransformMatrixHost     // ホスト側座標取得中
    case getTransformMatrixClient   // クライアント側座標取得中
    case confirm                    // 確認中
    case prepared                   // 準備完了
}
```

### 状態遷移フロー
```
initial
   ↓ (初期設定開始)
selecting
   ↓ (ピア選択)
getTransformMatrixHost / getTransformMatrixClient
   ↓ (座標データ収集)
confirm
   ↓ (アフィン行列計算)
prepared
```

## CoordinateTransforms クラス

### 概要
座標変換システムの中核を担うクラスです。座標データの管理、アフィン変換行列の計算、RPC通信を統合的に処理します。

### クラス定義
```swift
class CoordinateTransforms: ObservableObject {
    var coordinateTransformEntity: CoordinateTransformEntity = .init(state: .initial)
    
    /// 座標の交換を管理するフラグ
    @Published var requestTransform: Bool = false
    
    /// 座標を交換する回数
    @Published var matrixCount: Int = 0 {
        didSet {
            if matrixCount >= matrixCountLimit {
                coordinateTransformEntity.state = .confirm
            }
        }
    }
    
    /// 座標を交換する回数の上限
    var matrixCountLimit: Int = 4
}
```

### 主要プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `coordinateTransformEntity` | CoordinateTransformEntity | 座標変換エンティティ |
| `requestTransform` | Bool | 座標交換リクエストフラグ |
| `matrixCount` | Int | 座標交換回数カウンター |
| `matrixCountLimit` | Int | 座標交換回数の上限 |

## CoordinateTransformEntity

### 概要
座標変換データとメタデータを管理するエンティティです。

### データ構造
```swift
class CoordinateTransformEntity {
    /// 現在の状態
    var state: TransformationMatrixPreparationState = .initial
    
    /// A行列データ（4x4変換行列）
    var A: [[Float]] = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
    
    /// B行列データ（4x4変換行列）
    var B: [[Float]] = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
    
    /// AからBへのアフィン変換行列
    var affineMatrixAtoB: simd_float4x4 = matrix_identity_float4x4
    
    /// ホスト・クライアント判定
    var isHost: Bool = false
    
    /// 接続ピア情報
    var myPeerId: Int = 0
    var otherPeerId: Int = 0
}
```

### RPC メソッド定義
```swift
enum Method: RPCEntityMethod {
    case initMyPeer         // 自ピア初期化
    case initOtherPeer      // 他ピア初期化
    case resetPeer          // ピアリセット
    case requestTransform   // 座標変換リクエスト
    case setTransform       // 座標変換設定
    case setATransform      // A行列設定
    case setBTransform      // B行列設定
    case clacAffineMatrix   // アフィン行列計算
    case setState           // 状態設定
}
```

## 座標変換プロセス

### 1. 初期化フェーズ
```swift
func initMyPeer(param: InitMyPeerParam) -> RPCResult {
    coordinateTransformEntity.myPeerId = param.peerId
    return RPCResult()
}

func initOtherPeer(param: InitOtherPeerParam) -> RPCResult {
    coordinateTransformEntity.otherPeerId = param.peerId
    return RPCResult()
}
```

### 2. 座標データ収集フェーズ
```swift
func requestTransform(param: RequestTransformParam) -> RPCResult {
    requestTransform = true
    return RPCResult()
}

func setTransform(param: SetTransformParam) -> RPCResult {
    // 受信した変換行列を適切な配列（AまたはB）に格納
    matrixCount += 1
    // matrixCountが上限に達すると自動的に確認フェーズに移行
    return RPCResult()
}
```

### 3. ホスト・クライアント固有処理
```swift
func setATransform(param: SetATransformParam) -> RPCResult {
    coordinateTransformEntity.A = param.A
    return RPCResult()
}

func setBTransform(param: SetBTransformParam) -> RPCResult {
    coordinateTransformEntity.B = param.B
    return RPCResult()
}
```

### 4. アフィン変換行列計算
```swift
func clacAffineMatrix(param: ClacAffineMatrixParam) -> RPCResult {
    guard let result = calcAffineTransform(
        coordinateTransformEntity.A,
        coordinateTransformEntity.B
    ) else {
        return RPCResult("Failed to calculate affine matrix")
    }
    
    coordinateTransformEntity.affineMatrixAtoB = result
    return RPCResult()
}
```

### 5. 座標変換の適用
```swift
func setAffineMatrix() {
    // 計算されたアフィン変換行列をシステムに適用
}
```

## アフィン変換行列計算

### calcAffineTransform 関数
外部関数として実装された数学的計算処理：

```swift
func calcAffineTransform(_ A: [[Float]], _ B: [[Float]]) -> simd_float4x4?
```

**入力:**
- `A`: 座標系Aの4x4変換行列
- `B`: 座標系Bの4x4変換行列

**出力:**
- AからBへのアフィン変換行列（4x4）

**計算原理:**
1. 行列Aと行列Bから対応点を抽出
2. 最小二乗法による最適変換行列の計算
3. 回転、平行移動、スケーリングを統合したアフィン変換

### 数学的背景
アフィン変換は以下の形式で表現されます：
```
[x']   [a b c tx] [x]
[y'] = [d e f ty] [y]
[z']   [g h i tz] [z]
[1 ]   [0 0 0 1 ] [1]
```

ここで：
- (x, y, z) → (x', y', z') の座標変換
- 回転行列 + 平行移動ベクトル + スケーリング

## UI統合

### TransformationMatrixPreparationView
座標変換プロセスのユーザーインターフェースを提供：

#### 1. 初期設定 (InitialView)
```swift
Button("初期設定を開始します") {
    let setStateRPCResult = rpcModel.coordinateTransforms.setState(
        param: .init(state: .selecting)
    )
}
```

#### 2. 確認画面 (ConfirmView)
```swift
VStack {
    // A行列の表示
    Text("A").font(.title)
    ForEach(0..<rpcModel.coordinateTransforms.coordinateTransformEntity.A.count, id: \.self) { index in
        Text(rpcModel.coordinateTransforms.coordinateTransformEntity.A[index].description)
    }
    
    // B行列の表示
    Text("B").font(.title)
    ForEach(0..<rpcModel.coordinateTransforms.coordinateTransformEntity.B.count, id: \.self) { index in
        Text(rpcModel.coordinateTransforms.coordinateTransformEntity.B[index].description)
    }
    
    Button("設定を完了する") {
        prepared()
    }
}
```

## エラーハンドリング

### 一般的なエラーケース
1. **通信エラー**: ピア間でのデータ送受信失敗
2. **計算エラー**: アフィン変換行列の計算失敗
3. **データ不整合**: 行列サイズや形式の不一致
4. **タイムアウト**: 座標データ収集の時間切れ

### エラー処理戦略
```swift
// エラー時のリセット処理
func resetPeer(param: ResetPeerParam) -> RPCResult {
    coordinateTransformEntity = .init(state: .initial)
    requestTransform = false
    matrixCount = 0
    return RPCResult()
}
```

## パフォーマンス最適化

### 1. 非同期処理
- UI更新とは独立した座標計算
- バックグラウンドでの行列演算

### 2. データ圧縮
- 不要な精度の削除
- 効率的な行列表現

### 3. キャッシュ機能
- 計算済み変換行列の保存
- 再計算の回避

## セキュリティ考慮事項

### データ検証
- 受信した座標データの妥当性チェック
- 異常値の検出と除外

### プライバシー保護
- 座標データの最小限共有
- セッション終了時のデータ削除

この座標変換システムにより、複数のVision Proデバイス間で統一された3D空間を実現し、自然な協調ペイント体験を提供しています。