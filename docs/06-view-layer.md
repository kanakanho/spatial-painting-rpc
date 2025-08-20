# 6. ビューレイヤー

## 概要

Spatial Painting RPCアプリケーションのビューレイヤーは、SwiftUIとRealityKitを活用したAR/VR対応のユーザーインターフェースを提供します。2Dと3Dの統合されたインタラクションを実現し、直感的な操作体験を提供します。

## ビュー階層構造

```
spatial_painting_rpcApp
├── WindowGroup (ContentView)
├── WindowGroup ("ExternalStroke") - ExternalStrokeView
└── ImmersiveSpace - ImmersiveView
```

## メインアプリケーション

### spatial_painting_rpcApp

アプリケーションのエントリーポイントです。

```swift
@main
struct spatial_painting_rpcApp: App {
    @ObservedObject private var appModel = AppModel()
    
    var body: some Scene {
        // メインウィンドウ
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        
        // 外部ストローク管理ウィンドウ
        WindowGroup("ExternalStroke", id: "ExternalStroke") {
            ExternalStrokeView()
                .environmentObject(appModel)
                .handlesExternalEvents(preferring: [], allowing: [])
        }
        .handlesExternalEvents(matching: ["targetContentIdentifier"])
        
        // Immersive Space (AR/VR)
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environmentObject(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
```

### 主要なウィンドウ構成
- **メインウィンドウ**: 設定とナビゲーション
- **ExternalStrokeウィンドウ**: ファイル管理
- **ImmersiveSpace**: 3Dペイント環境

## ContentView

### 概要
アプリケーションのメインUIを担当し、セットアップと基本的なナビゲーションを提供します。

### 状態管理
```swift
enum SharedCoordinateState {
    case prepare    // 準備段階
    case sharing    // 座標設定中
    case shared     // 座標共有完了
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sharedCoordinateState: SharedCoordinateState = .prepare
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openWindow) private var openWindow
    
    // タイマー管理
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var startTime = Date()
    @State var isStartImmersiveSpace: Bool = false
}
```

### UI構成

#### 1. ファイル管理ボタン
```swift
Button("File Manager") {
    openWindow(id: "ExternalStroke")
}
```

#### 2. Immersive Space切り替え
```swift
ToggleImmersiveSpaceButton()
    .environmentObject(appModel)
    .disabled(!isStartImmersiveSpace)
```

#### 3. 座標共有状態に応じたUI
```swift
switch sharedCoordinateState {
case .prepare:
    Button("Start Sharing") {
        sharedCoordinateState = .sharing
    }
case .sharing:
    TransformationMatrixPreparationView(
        rpcModel: appModel.rpcModel,
        sharedCoordinateState: $sharedCoordinateState
    )
case .shared:
    Text("Shared Coordinate Ready")
}
```

### ライフサイクル管理

#### アプリ起動時
```swift
.onAppear() {
    print(">>> App appeared")
    appModel.peerManager.start()
    sharedCoordinateState = .prepare
}
```

#### フォアグラウンド復帰時
```swift
.onChange(of: scenePhase) { oldScenePhase, newScenePhase in
    if oldScenePhase == .inactive && newScenePhase == .active {
        // PeerManagerを再初期化
        appModel.peerManager = PeerManager(...)
        appModel.peerManager.start()
    }
}
```

#### バックグラウンド移行時
```swift
if newScenePhase == .background {
    sharedCoordinateState = .prepare
    appModel.mcPeerIDUUIDWrapper.standby.removeAll()
    appModel.peerManager.stop()
}
```

#### 遅延Immersive Space有効化
```swift
.onReceive(timer) { _ in
    if !isStartImmersiveSpace {
        let elapsedTime = Date().timeIntervalSince(startTime)
        if elapsedTime >= 3 {
            isStartImmersiveSpace = true
        }
    }
}
```

## ImmersiveView

### 概要
AR/VR空間でのメイン体験を提供する3Dビューです。ハンドトラッキング、空間認識、3Dペイントを統合的に管理します。

### RealityView構成
```swift
struct ImmersiveView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.displayScale) private var displayScale
    
    @State private var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    @State private var lastIndexPose: SIMD3<Float>? = nil
    @State private var sourceTransform: Transform? = nil
    
    private let keyDownHeight: Float = 0.005
}
```

### RealityViewの初期化
```swift
RealityView { content in
    // RealityKit contentのバンドル取得
    // 3Dシーンの構築
    content.add(appModel.model.setupContentEntity())
} update: { content in
    // 更新処理
}
```

### 非同期タスク管理

#### ハンドトラッキング処理
```swift
.task {
    await appModel.model.processHandUpdates()
}
```

#### 空間検出処理
```swift
.task(priority: .low) {
    await appModel.model.processReconstructionUpdates()
}
```

#### 指先ガイド表示
```swift
.task {
    appModel.model.showFingerTipSpheres()
}
```

### インタラクション管理

#### 矢印表示の切り替え
```swift
.onChange(of: appModel.model.isArrowShown) { _, newValue in
    Task {
        if newValue {
            appModel.model.showHandArrowEntities()
        } else {
            appModel.model.hideHandArrowEntities()
        }
    }
}
```

#### ジェスチャー処理
```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .simultaneously(with: MagnifyGesture())
        .targetedToAnyEntity()
        .onChanged({ value in
            // ドラッグとピンチジェスチャーの処理
        })
)
```

#### 衝突イベント処理
```swift
private func subscribeToCollisions(on entity: Entity, content: RealityViewContent) {
    _ = content.subscribe(to: CollisionEvents.Began.self, on: entity) { event in
        handleBegan(event: event, finger: entity)
    }
}

private func handleBegan(event: CollisionEvents.Began, finger: Entity) {
    // ボタン押下時の視覚フィードバック
    appModel.model.buttonEntity2.transform.translation.y -= keyDownHeight
    appModel.model.iconEntity2.transform.translation.y += 0.01
    // サウンド再生
    _ = appModel.model.recordTime(isBegan: true)
}
```

## TransformationMatrixPreparationView

### 概要
座標変換行列の準備プロセスを管理するビューです。複数のサブビューを状態に応じて切り替えます。

### クラス定義
```swift
struct TransformationMatrixPreparationView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State private var errorMessage = ""
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var time: String = ""
    @Binding private var sharedCoordinateState: SharedCoordinateState
}
```

### 状態ベースのビュー切り替え
```swift
switch rpcModel.coordinateTransforms.coordinateTransformEntity.state {
case .initial:
    InitialView(rpcModel: rpcModel)
        .disabled(time.isEmpty)
case .selecting:
    SelectingPeerView(rpcModel: rpcModel)
case .getTransformMatrixHost:
    GetTransformMatrixHostView(rpcModel: rpcModel)
case .getTransformMatrixClient:
    GetTransformMatrixClientView(rpcModel: rpcModel)
case .confirm:
    ConfirmView(rpcModel: rpcModel)
case .prepared:
    Text(rpcModel.coordinateTransforms.coordinateTransformEntity.affineMatrixAtoB.debugDescription)
    Button("設定を完了しました") {
        let setStateRPCResult = rpcModel.coordinateTransforms.resetPeer(param: .init())
        if !setStateRPCResult.success {
            errorMessage = setStateRPCResult.errorMessage
        }
        sharedCoordinateState = .sharing
    }
}
```

### サブビューの詳細

#### InitialView
```swift
struct InitialView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State private var errorMessage = ""
    
    var body: some View {
        Button("初期設定を開始します") {
            let setStateRPCResult = rpcModel.coordinateTransforms.setState(
                param: .init(state: .selecting)
            )
            if !setStateRPCResult.success {
                errorMessage = setStateRPCResult.errorMessage
            }
        }
    }
}
```

#### ConfirmView
```swift
struct ConfirmView: View {
    var body: some View {
        VStack {
            // A行列表示
            Text("A").font(.title)
            ForEach(0..<rpcModel.coordinateTransforms.coordinateTransformEntity.A.count, id: \.self) { index in
                Text(rpcModel.coordinateTransforms.coordinateTransformEntity.A[index].description)
            }
            
            // B行列表示
            Text("B").font(.title)
            ForEach(0..<rpcModel.coordinateTransforms.coordinateTransformEntity.B.count, id: \.self) { index in
                Text(rpcModel.coordinateTransforms.coordinateTransformEntity.B[index].description)
            }
            
            Button("設定を完了する") {
                prepared()
            }
        }
    }
}
```

## ToggleImmersiveSpaceButton

### 概要
Immersive Spaceの開閉を制御する汎用ボタンコンポーネントです。

```swift
struct ToggleImmersiveSpaceButton: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                case .open:
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                case .closed:
                    appModel.immersiveSpaceState = .inTransition
                    await openImmersiveSpace(id: appModel.immersiveSpaceID)
                case .inTransition:
                    break
                }
            }
        } label: {
            Text(appModel.immersiveSpaceState == .open ? "Hide Immersive Space" : "Show Immersive Space")
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
    }
}
```

## レスポンシブデザインと適応性

### 動的UI更新
- `@ObservedObject` と `@Published` による自動UI更新
- 状態変更に応じたリアルタイムレンダリング

### エラーハンドリング
- ネットワークエラーの表示
- 座標変換エラーの処理
- ユーザーフレンドリーなメッセージ

### アクセシビリティ
- Vision Pro のアクセシビリティ機能対応
- 音声フィードバック統合
- 視覚的インジケーター

このビューレイヤーにより、直感的で応答性の高いユーザーインターフェースを実現し、シームレスなAR/VR体験を提供しています。