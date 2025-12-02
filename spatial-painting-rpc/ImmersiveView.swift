//
//  ImmersiveView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import SwiftUI
import ARKit
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow: OpenWindowAction
    @Environment(\.dismissWindow) private var dismissWindow: DismissWindowAction
    @Environment(\.displayScale) private var displayScale: CGFloat
    
    @State private var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    @State private var lastIndexPose: SIMD3<Float>? = nil
    @State private var initIndexPose: SIMD3<Float>? = nil

    @State private var sourceTransform: Transform? = nil
    
    @State private var lastControlIndexPose: SIMD3<Float>? = nil
    
    private let keyDownHeight: Float = 0.005
    
    @State private var isCurrentSendPoint: Bool = false
    
    var body: some View {
        RealityView { content in
            do {
                /// RealityKit content のバンドルを取得
                let scene: Entity = try await Entity(named: "colorpallet", in: realityKitContentBundle)
                
                /// RealityKit のシーンを RealityView に追加
                if let eraserEntity: Entity = scene.findEntity(named: "collider"),
                   let bezierEndPointEntity: Entity = scene.findEntity(named: "bezierEndPoint"),
                   let bezierHandleEntity: Entity = scene.findEntity(named: "bezierHandle") {
                    appModel.rpcModel.painting.paintingCanvas.setEntities(eraserEntity: eraserEntity, bezierEndPointEntity: bezierEndPointEntity.clone(recursive: true), bezierHandleEntity: bezierHandleEntity.clone(recursive: true))
                } else {
                    if scene.findEntity(named: "collider") == nil {
                        print("collider not found")
                    } else if scene.findEntity(named: "bezierEndPoint") == nil {
                        print("bezierEndPoint not found")
                    } else if scene.findEntity(named: "bezierHandle") == nil {
                        print("bezierHandle not found")
                    }
                }
                
                if let buttonPlateEntity = scene.findEntity(named: "board") {
                    appModel.model.setButtonPlateEntity(buttonPlateEntity)
                } else {
                    print("buttonPlateEntity not found")
                }
                
                // added by nagao 2025/11/20
                if let drawModeEntity: Entity = scene.findEntity(named: "draw"),
                   let editModeEntity: Entity = scene.findEntity(named: "edit"),
                   let bezierModelEntity: Entity = scene.findEntity(named: "bezier") {
                    appModel.model.setModeEntities(drawModeEntity: drawModeEntity, editModeEntity: editModeEntity, bezierModeEntity: bezierModelEntity)
                } else {
                    if scene.findEntity(named: "draw") == nil {
                        print("draw not found")
                    } else if scene.findEntity(named: "edit") == nil {
                        print("edit not found")
                    } else if scene.findEntity(named: "bezier") == nil {
                        print("bezier not found")
                    }
                }

                appModel.rpcModel.painting.advancedColorPalletModel.setSceneEntity(scene: scene)
                
                /// ViewModel の Entity を RealityView に追加
                let contentEntity: Entity = appModel.model.setupContentEntity()
                content.add(contentEntity)
                
                /// ColorPalletModel の初期化
                appModel.model.initColorPalletModel(colorPalletModel: appModel.rpcModel.painting.advancedColorPalletModel)
                content.add(appModel.rpcModel.painting.advancedColorPalletModel.colorPalletEntity)
                appModel.rpcModel.painting.advancedColorPalletModel.initEntity()
                
                /// お絵描き用の PaintingCanvas の初期化
                let root: Entity = appModel.rpcModel.painting.paintingCanvas.root
                content.add(root)
                
                /// Collision の設定
                setupCollisionSubscriptions(on: content)
                      
                /// お絵描き中に移動した場所を記録する
                root.components.set(ClosureComponent(closure: { (deltaTime: TimeInterval) in
                    var anchors: [HandAnchor] = []
                    if let right: HandAnchor = appModel.model.latestHandTracking.right {
                        anchors.append(right)
                    }
                    
                    for anchor in anchors {
                        let anchor: HandAnchor = anchor
                        guard let handSkeleton: HandSkeleton = anchor.handSkeleton else { continue }
                        
                        let thumbPos: SIMD3<Float> = (anchor.originFromAnchorTransform * handSkeleton.joint(.thumbTip).anchorFromJointTransform).position
                        let indexPos: SIMD3<Float> = (anchor.originFromAnchorTransform * handSkeleton.joint(.indexFingerTip).anchorFromJointTransform).position
                        let pinchThreshold: Float = 0.03
                        
                        if length(thumbPos - indexPos) < pinchThreshold {
                            if lastIndexPose == nil, initIndexPose == nil {
                                initIndexPose = indexPos
                            }
                            lastIndexPose = indexPos
                        } else {
                            lastIndexPose = nil
                            initIndexPose = nil
                        }
                    }
                }))
                
            } catch {
                print("Error in RealityView's make: \(error)")
            }
        }
        /// ARKitSession の起動
        .task {
            do {
                try await appModel.model.session.run([appModel.model.sceneReconstruction, appModel.model.handTracking])
            } catch {
                print("Failed to start session: \(error)")
                await dismissImmersiveSpace()
            }
        }
        /// ハンドトラッキングの処理を起動
        .task {
            await appModel.model.processHandUpdates()
        }
        /// 空間検出の処理を起動
        .task(priority: .low) {
            await appModel.model.processReconstructionUpdates()
        }
        /// 指先の球を表示
        .task {
            appModel.model.showFingerTipSpheres()
        }
        .onChange(of: appModel.model.isArrowShown) {
            Task {
                if appModel.model.isArrowShown {
                    appModel.model.showHandArrowEntities()
                } else {
                    appModel.model.hideHandArrowEntities()
                }
            }
        }
        .onDisappear {
            appModel.model.dismissEntities()
            appModel.model.colorPalletModel.colorPalletEntity.children.removeAll()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .simultaneously(with: MagnifyGesture())
                .targetedToAnyEntity()
                .onChanged({ (value: EntityTargetValue<SimultaneousGesture<DragGesture, MagnifyGesture>.Value>) in
                    if sourceTransform == nil {
                        sourceTransform = value.entity.transform
                    }

                    if appModel.rpcModel.painting.paintingCanvas.isControlMode {
                        if appModel.rpcModel.painting.paintingCanvas.isBezierSelected, let pos: SIMD3<Float> = lastIndexPose, let initPos: SIMD3<Float> = initIndexPose
                        {
                            let dist: Float = distance(initPos, pos)
                            //print("Distance between pos and initPos: \(dist)")
                            if dist < 0.01 || dist > 0.5 {
                                return
                            }
                            
                            let entity = appModel.rpcModel.painting.paintingCanvas.selectedBezierEntity
                            let comp = entity.components[BezierStrokeControlComponent.self]
                            let entityPos: SIMD3<Float> = appModel.rpcModel.painting.paintingCanvas.selectedBezierPosition

                            appModel.rpcModel.painting.paintingCanvas.moveControlPoint(
                                strokeId: comp!.bezierStrokeId,
                                controlPointId: comp!.bezierPointId,
                                controlType: comp!.controlType,
                                newPosition: entityPos + pos - initPos
                            )
                            for (id,affineMatrix): (Int, simd_float4x4) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                                let clientPos: SIMD3<Float> = matmul4x4_3x1(affineMatrix, entityPos + pos - initPos)
                                _ = appModel.rpcModel.sendRequest(
                                    RequestSchema(
                                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                        method: .moveControlPoint,
                                        param: .moveControlPoint(
                                            .init(
                                                strokeId: comp!.bezierStrokeId,
                                                controlPointId: comp!.bezierPointId,
                                                controlType: comp!.controlType,
                                                newPosition: clientPos
                                            )
                                        )
                                    ),
                                    mcPeerId: id
                                )
                            }
                        }
                        return
                    }
                    
                    /// 保存したストロークを再度表示させるための処理
                    if !appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty {
                        if value.entity.name == "boundingBox" {
                            let isHandGripped: Bool = appModel.model.isHandGripped
                            
                            if isHandGripped {
                                // 例: ジェスチャ中の更新ハンドラ内
                                if let t: Vector3D = value.first?.translation3D,
                                   let src: Transform = sourceTransform {
                                    // ← ジェスチャ開始時に保存した Transform

                                    // 1) ドラッグ量 → 角度（ラジアン）に変換（係数は好みで調整）
                                    let radiansPerMeter: Float = 0.01
                                    let yaw: Float = Float(t.x) * radiansPerMeter // 水平ドラッグ → Yaw
                                    let pitch: Float = Float(t.y) * radiansPerMeter // 垂直ドラッグ → Pitch

                                    // 2) まずワールド Y 軸で Yaw を適用（turntable 風）
                                    let qYaw: simd_quatf = simd_quatf(angle: yaw, axis: [0, 1, 0])
                                    var q: simd_quatf = qYaw * src.rotation
                                    // ← 右側（src）→ 左側（qYaw）の順で適用

                                    // 3) つづいて「Yaw 後のローカル X 軸」を求めて Pitch を適用
                                    let localXAfterYaw: SIMD3<Float> = normalize(q.act([1, 0, 0]))
                                    let qPitch: simd_quatf = simd_quatf(angle: pitch, axis: localXAfterYaw)
                                    q = qPitch * q

                                    // 4) 正規化して反映
                                    value.entity.transform.rotation = simd_normalize(q)
                                }
                            } else if let magnification: CGFloat = value.second?.magnification {
                                //print("magnification: \(magnification)")
                                let magnification: Float = Float(magnification)
                                
                                value.entity.transform.scale = [sourceTransform!.scale.x * magnification, sourceTransform!.scale.y * magnification, sourceTransform!.scale.z * magnification]
                                
                                value.entity.children.forEach { child in
                                    appModel.rpcModel.painting.paintingCanvas.tmpStrokes.filter({ $0.root.components[StrokeRootComponent.self]?.uuid == child.components[StrokeRootComponent.self]?.uuid }).forEach { stroke in
                                        stroke.updateMaxRadiusAndRemesh(scaleFactor: value.entity.transform.scale.sum() / 3.0)
                                    }
                                }
                            } else if let translation: Vector3D = value.first?.translation3D {
                                let convertedTranslation: SIMD3<Float> = value.convert(translation, from: .local, to: value.entity.parent!)
                                
                                value.entity.transform.translation = sourceTransform!.translation + convertedTranslation
                            }
                        }
                    }
                    /// ストロークの点の追加
                    else if !appModel.model.isEraserMode,
                            appModel.rpcModel.coordinateTransforms.coordinateTransformEntity.state == .initial,
                            let pos: SIMD3<Float> = lastIndexPose {
                        isCurrentSendPoint.toggle()
                        if isCurrentSendPoint {
                            return
                        }
                        let uuid: UUID = UUID()
                        appModel.rpcModel.painting.paintingCanvas.addPoint(uuid, pos, userId: appModel.mcPeerIDUUIDWrapper.myId)
                        for (id,affineMatrix): (Int, simd_float4x4) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                            let clientPos: SIMD3<Float> = matmul4x4_3x1(affineMatrix, pos)
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .addStrokePoint,
                                    param: .addStrokePoint(
                                        .init(
                                            uuid: uuid,
                                            point: clientPos,
                                            userId: appModel.mcPeerIDUUIDWrapper.myId
                                        )
                                    )
                                ),
                                mcPeerId: id
                            )
                        }
                    }
                })
                .onEnded({ _ in
                    sourceTransform = nil
                    lastIndexPose = nil
                    initIndexPose = nil

                    if appModel.rpcModel.painting.paintingCanvas.isControlMode {
                        if appModel.rpcModel.painting.paintingCanvas.isBezierSelected
                        {
                            let entity = appModel.rpcModel.painting.paintingCanvas.selectedBezierEntity
                            appModel.rpcModel.painting.paintingCanvas.setSelectedBezierPosition(entity.position(relativeTo: nil))
                            let comp = entity.components[BezierStrokeControlComponent.self]
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .finishControlPoint,
                                    param: .finishControlPoint(
                                        .init(
                                            strokeId: comp!.bezierStrokeId,
                                            controlPointId: comp!.bezierPointId
                                        )
                                    )
                                )
                            )
                            //print("Final position of controlpoint of bezierstroke: \(entity.position(relativeTo: nil))")
                        }
                        return
                    }
                    
                    if !appModel.model.isEraserMode,
                       appModel.rpcModel.coordinateTransforms.coordinateTransformEntity.state == .initial {
                        // 自分の端末の中でベジェ曲線化
                        guard let bezierStroke: BezierStroke = appModel.rpcModel.painting.paintingCanvas.individualPoints2Bezier(userId: appModel.mcPeerIDUUIDWrapper.myId) else {
                            return
                        }
                        
                        // ベジェ曲線の情報を共有
                        for (id,affineMatrix): (Int, simd_float4x4) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId:  appModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .addBezierStrokePoints,
                                    param: .addBezierStrokePoints(
                                        .init(userId: appModel.mcPeerIDUUIDWrapper.myId, bezierPoints: bezierStroke.bezierPoints.getPoints(affine: affineMatrix))
                                    )
                                ),
                                mcPeerId: id
                            )
                        }
                        
                        _ = appModel.rpcModel.sendRequest(
                            RequestSchema(
                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                method: .finishStroke,
                                param: .finishStroke(
                                    .init(
                                        userId: appModel.mcPeerIDUUIDWrapper.myId
                                    )
                                )
                            )
                        )
                    }
                })
        )
        .onChange(of: appModel.rpcModel.coordinateTransforms.affineMatrixs) {
            appModel.model.resetInitBall()
            appModel.model.disableIndexFingerTipGuideBall()
        }
        .onChange(of: appModel.model.latestRightIndexFingerCoordinates) {
            if appModel.rpcModel.coordinateTransforms.requestTransform {
                latestRightIndexFingerCoordinates = appModel.model.latestRightIndexFingerCoordinates
            }
        }
        .onChange(of: appModel.rpcModel.coordinateTransforms.requestTransform){
            if appModel.rpcModel.coordinateTransforms.requestTransform {
                print("immersive coordinateTransforms")
                appModel.model.fingerSignal(hand: .right, flag: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Task{
                        appModel.model.fingerSignal(hand: .right, flag: false)
                        let rpcResult: RPCResult = appModel.rpcModel.sendRequest(
                            RequestSchema(
                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                method: .setTransform,
                                param: .setTransform(
                                    .init(
                                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                        matrix: latestRightIndexFingerCoordinates.floatList
                                    )
                                )
                            ),
                            mcPeerId: appModel.rpcModel.coordinateTransforms.otherPeerId
                        )
                        if !rpcResult.success {
                            await dismissImmersiveSpace()
                            openWindow(id: "error")
                        }
                        appModel.model.initBall(transform: latestRightIndexFingerCoordinates, ballColor: .cyan)
                    }
                }
            }
        }
        .onChange(of: appModel.rpcModel.coordinateTransforms.matrixCount) {
            if appModel.rpcModel.coordinateTransforms.matrixCount == 0 {
                return
            }
            
            guard let nextPos: SIMD3<Float> = appModel.rpcModel.coordinateTransforms.getNextIndexFingerTipPosition() else {
                print("No next index finger tip position available.")
                return
            }
            appModel.model.enableIndexFingerTipGuideBall(position: nextPos)
        }
    }
}

// added by nagao 2015/7/19
extension ImmersiveView {
    func setupCollisionSubscriptions(on content: RealityViewContent) {
        for finger: ModelEntity in appModel.model.fingerEntities.values {
            subscribeBegan(on: finger, content: content)
            subscribeEnded(on: finger, content: content)
        }
    }
    
    private func subscribeBegan(on entity: Entity, content: RealityViewContent) {
        _ = content.subscribe(to: CollisionEvents.Began.self, on: entity) { (event: CollisionEvents.Began) in
            handleBegan(event: event, finger: entity)
        }
    }
    
    private func handleBegan(event: CollisionEvents.Began, finger: Entity) {
        let name: String = event.entityB.name
        
        if appModel.model.colorPalletModel.colorNames().contains(name) {
            didTouchColor(name, finger: finger)
        }
        else if appModel.model.colorPalletModel.toolNames().contains(name) {
            didTouchTool(name, finger: finger)
        }
        else if name == "eraser" {
            activateEraser(finger: finger)
        }
        else if name == "bezierEndPoint" {
            selectBezierEndPoint(event.entityB)
        }
        else if name == "bezierHandle" {
            selectBezierHandle(event.entityB)
        }
        else if event.entityB.hasStrokeRootComponent, appModel.model.isEraserMode, appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty, !appModel.rpcModel.painting.paintingCanvas.isControlMode {
            deleteStroke(event.entityB)
        }
        else if event.entityB.hasStrokeRootComponent, appModel.model.isSelectorMode {
            selectStroke(event.entityB)
        }
        else if name == "button" {
            appModel.model.buttonEntity.transform.translation.y -= keyDownHeight
            appModel.model.iconEntity.transform.translation.y += 0.01
            appModel.model.iconEntity.orientation = simd_quatf(angle: .pi / 2.0, axis: SIMD3(1, 0, 0))
            _ = appModel.model.recordTime(isBegan: true)
        }
        else if name == "button2" {
            appModel.model.buttonEntity2.transform.translation.y -= keyDownHeight
            appModel.model.iconEntity2.transform.translation.y += 0.01
            appModel.model.iconEntity2.orientation = simd_quatf(angle: .pi / 2.0, axis: SIMD3(1, 0, 0))
            appModel.model.iconEntity3.transform.translation.y += 0.01
            appModel.model.iconEntity3.transform.translation.z -= 0.005
            appModel.model.iconEntity3.orientation = simd_quatf(angle: 75.0 * .pi / 180.0, axis: SIMD3(1, 0, 0))
            _ = appModel.model.recordTime(isBegan: true)
        }
        else if name == "draw" {
            appModel.model.authoringMode = .draw
            appModel.rpcModel.painting.paintingCanvas.setIsControlMode(false)
            appModel.model.resetColor()
            appModel.rpcModel.painting.paintingCanvas.setActiveColor(userId: appModel.mcPeerIDUUIDWrapper.myId, color: SimpleMaterial.Color.white)
            appModel.model.colorPalletModel.setActiveColor(color: SimpleMaterial.Color.white)
            let mat = SimpleMaterial(
                color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0),
                isMetallic: false
            )
            finger.components.set(
                ModelComponent(
                    mesh: .generateSphere(radius: 0.01),
                    materials: [mat]
                )
            )
            if appModel.rpcModel.painting.paintingCanvas.confirmMovingStrokes() {
                sendTmpStrokes()
            }
            appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
            appModel.model.isSelectorMode = false
        }
        else if name == "edit" {
            appModel.model.authoringMode = .edit
            appModel.rpcModel.painting.paintingCanvas.setIsControlMode(false)
            appModel.model.resetColor()
            let mat = SimpleMaterial(
                color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0),
                isMetallic: true
            )
            finger.components.set(
                ModelComponent(
                    mesh: .generateSphere(radius: 0.01),
                    materials: [mat]
                )
            )
            if appModel.rpcModel.painting.paintingCanvas.confirmMovingStrokes() {
                sendTmpStrokes()
            }
            appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
            appModel.model.isEraserMode = false
            appModel.model.isSelectorMode = true
        }
        else if name == "bezier" {
            appModel.model.authoringMode = .bezier
            if appModel.rpcModel.painting.paintingCanvas.confirmMovingStrokes() {
                sendTmpStrokes()
            }
            appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
            appModel.model.resetColor()
            let mat = SimpleMaterial(
                color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.2),
                isMetallic: false
            )
            finger.components.set(
                ModelComponent(
                    mesh: .generateSphere(radius: 0.01),
                    materials: [mat]
                )
            )
            appModel.model.isEraserMode = false
            appModel.model.isSelectorMode = false

            let prev = appModel.rpcModel.painting.paintingCanvas.selectedBezierEntity
            let flag = appModel.rpcModel.painting.paintingCanvas.isBezierSelected
            if flag {
                let mat = SimpleMaterial(
                    color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.1),
                    isMetallic: true
                )
                prev.components.set(
                    ModelComponent(
                        mesh: .generateBox(size: 1.0, cornerRadius: 0.0),
                        materials: [mat]
                    )
                )
                appModel.rpcModel.painting.paintingCanvas.setSelectedBezierEntity(Entity())
                appModel.rpcModel.painting.paintingCanvas.setIsBezierSelected(false)
            }
            appModel.rpcModel.painting.paintingCanvas.setIsControlMode(true)
        }
    }
    
    private func subscribeEnded(on entity: Entity, content: RealityViewContent) {
        _ = content.subscribe(to: CollisionEvents.Ended.self, on: entity) { (event: CollisionEvents.Ended) in
            handleEnded(event: event, finger: entity)
        }
    }
    
    private func handleEnded(event: CollisionEvents.Ended, finger: Entity) {
        let name: String = event.entityB.name
        
        if appModel.model.colorPalletModel.colorNames().contains(name) {
            _ = appModel.rpcModel.sendRequest(
                RequestSchema(
                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                    method: .setStrokeColor,
                    param: .setStrokeColor(
                        .init(
                            userId: appModel.mcPeerIDUUIDWrapper.myId,
                            strokeColorName: name
                        )
                    )
                )
            )
            if let color: UIColor =
                appModel.rpcModel.painting.advancedColorPalletModel.colorDictionary[name] {
                let material: SimpleMaterial = SimpleMaterial(color: color, isMetallic: false)
                finger.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
            }
        }
        else if name == "eraser" {
            if appModel.model.recordTime(isBegan: false) {
                _ = appModel.rpcModel.sendRequest(
                    RequestSchema(
                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                        method: .removeAllStroke,
                        param: .removeAllStroke(.init())
                    )
                )
            }
        }
        else if name == "button" {
            appModel.model.buttonEntity.transform.translation.y += keyDownHeight
            appModel.model.iconEntity.orientation = simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
            appModel.model.iconEntity.transform.translation.y -= 0.01
            if appModel.model.recordTime(isBegan: false) {
                let cleaned: [BezierStroke] = appModel.rpcModel.painting.paintingCanvas.strokes.removingShortStrokes(minPoints: 3)
                if cleaned.isEmpty { return }
                appModel.externalStrokeFileWapper.writeStroke(
                    strokes: cleaned,
                    displayScale: displayScale,
                    planeNormalVector: appModel.model.planeNormalVector,
                    planePoint: appModel.model.planePoint
                )
            }
        }
        else if name == "button2" {
            appModel.model.buttonEntity2.transform.translation.y += keyDownHeight
            appModel.model.iconEntity2.orientation = simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
            appModel.model.iconEntity2.transform.translation.y -= 0.01
            appModel.model.iconEntity3.orientation = simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
            appModel.model.iconEntity3.transform.translation.y -= 0.01
            appModel.model.iconEntity3.transform.translation.z += 0.005
            if appModel.model.recordTime(isBegan: false) {
                toggleStrokeWindow()
            }
        }
    }
    
    // MARK: — Began-handlers
    private func didTouchColor(_ name: String, finger: Entity) {
        appModel.model.changeFingerColor(entity: finger, colorName: name)
        if appModel.model.authoringMode == .edit {
            let color: UIColor = appModel.model.getColor(colorName: name)
            appModel.rpcModel.painting.paintingCanvas.changeColorOfMovingStrokes(color)
        } else if appModel.model.authoringMode == .draw {
            appModel.rpcModel.painting.paintingCanvas.setMaxRadius(userId: appModel.mcPeerIDUUIDWrapper.myId, radius: 0.01)
            appModel.model.isEraserMode = false
        }
    }
    
    private func didTouchTool(_ name: String, finger: Entity) {
        _ = appModel.rpcModel.sendRequest(
            RequestSchema(
                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .changeFingerLineWidth,
                param: .changeFingerLineWidth(
                    .init(
                        userId: appModel.mcPeerIDUUIDWrapper.myId,
                        toolName: name
                    )
                )
            )
        )
        
        if let toolBall: ToolBall = appModel.rpcModel.painting.advancedColorPalletModel.toolBalls.get(withID: name),
           let activeColor: UIColor = appModel.rpcModel.painting.paintingCanvas.individualStrokeDic[appModel.mcPeerIDUUIDWrapper.myId]?.activeColor {
            let material: SimpleMaterial = SimpleMaterial(color: activeColor, isMetallic: false)
            finger.components.set(ModelComponent(mesh: .generateSphere(radius: Float(toolBall.lineWidth)), materials: [material]))
        }
        if appModel.model.authoringMode == .edit {
            let lineWidth: Float = appModel.model.getLineWidth(toolName: name)
            appModel.rpcModel.painting.paintingCanvas.changeLineWidthOfMovingStrokes(lineWidth)
        } else if appModel.model.authoringMode == .draw {
            appModel.model.isEraserMode = false
        }
    }
    
    private func activateEraser(finger: Entity) {
        let eraserMat: SimpleMaterial = SimpleMaterial(
            color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.2),
            isMetallic: true
        )
        finger.components.set(
            ModelComponent(
                mesh: .generateSphere(radius: 0.01),
                materials: [eraserMat]
            )
        )
        appModel.model.resetColor()
        appModel.model.isEraserMode = true
        appModel.model.colorPalletModel.selectedToolName = "eraser"
        _ = appModel.model.recordTime(isBegan: true)
    }
    
    private func deleteStroke(_ entity: Entity) {
        guard let comp: StrokeRootComponent = entity.components[StrokeRootComponent.self] else { return }
        _ = appModel.rpcModel.sendRequest(
            RequestSchema(
                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .removeStroke,
                param: .removeStroke(.init(uuid: comp.uuid))
            )
        )
    }
    
    // added by nagao 2025/11/21
    private func selectStroke(_ entity: Entity) {
        guard let comp: StrokeRootComponent = entity.components[StrokeRootComponent.self] else { return }
        let stroke: [BezierStroke] = appModel.rpcModel.painting.paintingCanvas.strokes.filter {
            $0.root.components[StrokeRootComponent.self]?.uuid == comp.uuid
        }
        if stroke.count == 0 { return }
        appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
        appModel.rpcModel.painting.paintingCanvas.addMovingStrokes(stroke.first!)
        // tmpStrokeに追加
        appModel.rpcModel.painting.paintingCanvas.addTmpStrokes(appModel.rpcModel.painting.paintingCanvas.movingStrokes)
        
        if !appModel.model.colorPalletModel.colorPalletEntity.isEnabled {
            deleteStroke(entity)
        }
    }

    // added by nagao 2025/11/26
    private func selectBezierEndPoint(_ entity: Entity) {
        let prev = appModel.rpcModel.painting.paintingCanvas.selectedBezierEntity
        let flag = appModel.rpcModel.painting.paintingCanvas.isBezierSelected
        if flag, prev != entity {
            let mat = SimpleMaterial(
                color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.1),
                isMetallic: true
            )
            prev.components.set(
                ModelComponent(
                    mesh: .generateBox(size: 1.0, cornerRadius: 0.0),
                    materials: [mat]
                )
            )
        } else if prev == entity {
            return
        }
        let mat = SimpleMaterial(
            color: UIColor(red: 255/255, green: 215/255, blue: 0/255, alpha: 1.0),
            isMetallic: true
        )
        entity.components.set(
            ModelComponent(
                mesh: .generateBox(size: 1.1, cornerRadius: 0.0),
                materials: [mat]
            )
        )
        appModel.rpcModel.painting.paintingCanvas.setSelectedBezierEntity(entity)
        appModel.model.colorPalletModel.playBezierPointSound()
    }
    private func selectBezierHandle(_ entity: Entity) {
        let prev = appModel.rpcModel.painting.paintingCanvas.selectedBezierEntity
        let flag = appModel.rpcModel.painting.paintingCanvas.isBezierSelected
        if flag, prev != entity {
            let mat = SimpleMaterial(
                color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.1),
                isMetallic: true
            )
            prev.components.set(
                ModelComponent(
                    mesh: .generateBox(size: 1.0, cornerRadius: 0.0),
                    materials: [mat]
                )
            )
        } else if prev == entity {
            return
        }
        let mat = SimpleMaterial(
            color: .red,
            isMetallic: true
        )
        entity.components.set(
            ModelComponent(
                mesh: .generateSphere(radius: 5.0),
                materials: [mat]
            )
        )
        appModel.rpcModel.painting.paintingCanvas.setSelectedBezierEntity(entity)
        appModel.model.colorPalletModel.playBezierHandleSound()
    }

    private func sendTmpStrokes() {
        for (id,affineMatrix): (Int, simd_float4x4) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
            let transformedStrokes: [BezierStroke] = appModel.rpcModel.painting.paintingCanvas.tmpStrokes.map({ (stroke: BezierStroke) in
                // points 全てにアフィン変換を適用
                let tmpRootTransfromPoints: [SIMD4<Float>] = stroke.points.map { (point: SIMD3<Float>) in
                    return stroke.root.transformMatrix(relativeTo: nil) * SIMD4<Float>(point, 1.0)
                }
                let transformedPoints: [SIMD3<Float>] = tmpRootTransfromPoints.map { (point: SIMD4<Float>) in
                    matmul4x4_4x1(affineMatrix, point)
                }
                let transformedStroke: BezierStroke = BezierStroke(uuid: stroke.uuid, points: transformedPoints, color: stroke.activeColor, maxRadius: stroke.maxRadius)
                transformedStroke.bezierPoints = stroke.bezierPoints.getPoints(affine: affineMatrix)
                return transformedStroke
            })
            _ = appModel.rpcModel.sendRequest(
                .init(
                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                    method: .addBezierStrokes,
                    param: .addBezierStrokes(.init(strokes: transformedStrokes))
                ),
                mcPeerId: id
            )
        }
    }

    // MARK: — Ended-handlers
    private func toggleStrokeWindow() {
        if !appModel.externalStrokeFileWapper.isFileManagerActive {
            openWindow(id: "ExternalStroke")
        } else {
            //print("FileManager is already active.")
            appModel.rpcModel.painting.paintingCanvas.confirmTmpStrokes()
            for (id,affineMatrix): (Int, simd_float4x4) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                let transformedStrokes: [BezierStroke] = appModel.rpcModel.painting.paintingCanvas.tmpStrokes.map({ (stroke: BezierStroke) in
                    // points 全てにアフィン変換を適用
                    let tmpRootTransfromPoints: [SIMD4<Float>] = stroke.points.map { (point: SIMD3<Float>) in
                        return stroke.root.transformMatrix(relativeTo: nil) * SIMD4<Float>(point, 1.0)
                    }
                    let transformedPoints: [SIMD3<Float>] = tmpRootTransfromPoints.map { (point: SIMD4<Float>) in
                        matmul4x4_4x1(affineMatrix, point)
                    }
                    let transformedStroke: BezierStroke = BezierStroke(uuid: stroke.uuid, points: transformedPoints, color: stroke.activeColor, maxRadius: stroke.maxRadius)
                    transformedStroke.bezierPoints = stroke.bezierPoints.getPoints(affine: affineMatrix)
                    return transformedStroke
                })
                _ = appModel.rpcModel.sendRequest(
                    .init(
                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                        method: .addBezierStrokes,
                        param: .addBezierStrokes(.init(strokes: transformedStrokes))
                    ),
                    mcPeerId: id
                )
            }
            appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
            DispatchQueue.main.async {
                dismissWindow(id: "ExternalStroke")
            }
        }
        appModel.externalStrokeFileWapper.isFileManagerActive.toggle()
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environmentObject(AppModel())
}
