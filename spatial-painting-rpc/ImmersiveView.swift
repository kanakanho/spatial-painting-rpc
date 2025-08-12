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
    @State private var sourceTransform: Transform? = nil
    @State private var isFileManagerActive: Bool = false
    
    private let keyDownHeight: Float = 0.005
    
    var body: some View {
        RealityView { content in
            do {
                /// RealityKit content のバンドルを取得
                let scene: Entity = try await Entity(named: "colorpallet", in: realityKitContentBundle)
                
                /// RealityKit のシーンを RealityView に追加
                if let eraserEntity: Entity = scene.findEntity(named: "collider") {
                    appModel.rpcModel.painting.paintingCanvas.setEraserEntity(eraserEntity)
                } else {
                    print("eraserEntity not found")
                }
                
                if let buttonPlateEntity = scene.findEntity(named: "board") {
                    appModel.model.setButtonPlateEntity(buttonPlateEntity)
                } else {
                    print("buttonPlateEntity not found")
                }
                
                appModel.rpcModel.painting.advancedColorPalletModel.setSceneEntity(scene: scene)
                
                /// ViewModel の Entity を RealityView に追加
                let contentEntity: Entity = appModel.model.setupContentEntity()
                content.add(contentEntity)
                
                /// ColorPalletModel の初期化
                appModel.model.initColorPalletNodel(colorPalletModel: appModel.rpcModel.painting.advancedColorPalletModel)
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
                    
                    if let left: HandAnchor = appModel.model.latestHandTracking.left {
                        anchors.append(left)
                    }
                    
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
                            lastIndexPose = indexPos
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
                openWindow(id: "error")
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
        .onChange(of: appModel.model.isArrowShown) { _, newValue in
            let newValue: Bool = newValue
            Task {
                if newValue {
                    appModel.model.showHandArrowEntities()
                } else {
                    appModel.model.hideHandArrowEntities()
                }
            }
        }
        .onDisappear {
            appModel.model.dismissHandArrowEntities()
            appModel.model.colorPalletModel.colorPalletEntity.children.removeAll()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .simultaneously(with: MagnifyGesture())
                .targetedToAnyEntity()
                .onChanged({ value in
                    let value: EntityTargetValue<SimultaneousGesture<DragGesture, MagnifyGesture>.Value> = value
                    if sourceTransform == nil {
                        sourceTransform = value.entity.transform
                    }
                    if !appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty {
                        if value.entity.name == "boundingBox" {
                            let isHandGripped = appModel.model.isHandGripped
                            
                            if isHandGripped {
                                if let translation = value.first?.translation3D {
                                    let rotationX = Float(translation.x / 1000.0) * .pi
                                    let rotationY = Float(translation.y / 1000.0) * .pi
                                    
                                    value.entity.transform.rotation = sourceTransform!.rotation * simd_quatf(angle: rotationX, axis: [0, 1, 0]) * simd_quatf(angle: rotationY, axis: [1, 0, 0])
                                }
                            } else if let magnification = value.second?.magnification {
                                //print("magnification: \(magnification)")
                                let magnification = Float(magnification)
                                
                                value.entity.transform.scale = [sourceTransform!.scale.x * magnification, sourceTransform!.scale.y * magnification, sourceTransform!.scale.z * magnification]
                                
                                value.entity.children.forEach { child in
                                    appModel.rpcModel.painting.paintingCanvas.tmpStrokes.filter({ $0.entity.components[StrokeComponent.self]?.uuid == child.components[StrokeComponent.self]?.uuid }).forEach { stroke in
                                        stroke.updateMaxRadiusAndRemesh(scaleFactor: value.entity.transform.scale.sum() / 3)
                                    }
                                }
                            } else if let translation = value.first?.translation3D {
                                let convertedTranslation = value.convert(translation, from: .local, to: value.entity.parent!)
                                
                                value.entity.transform.translation = sourceTransform!.translation + convertedTranslation
                            }
                        }
                    } else if !appModel.model.isEraserMode,
                              appModel.rpcModel.coordinateTransforms.coordinateTransformEntity.state == .initial,
                              let pos = lastIndexPose {
                        let uuid: UUID = UUID()
                        appModel.rpcModel.painting.paintingCanvas.addPoint(uuid, pos)
                        let matrix:[Double] = [pos.x.toDouble(), pos.y.toDouble(), pos.z.toDouble(), 1]
                        for (id,affineMatrix) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                            let clientPos = matmul4x4_4x1(affineMatrix.doubleList, matrix)
                            _ = appModel.rpcModel.sendRequest(
                                RequestSchema(
                                    peerId: appModel.rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                                    method: .addStrokePoint,
                                    param: .addStrokePoint(
                                        .init(
                                            uuid: uuid,
                                            point: .init(x: Float(clientPos[0]), y: Float(clientPos[1]), z: Float(clientPos[2]))
                                        )
                                    )
                                ),
                                mcPeerId: id
                            )
                        }
                    }
                })
                .onEnded({ _ in
                    if appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty,
                       !appModel.model.isEraserMode,
                       appModel.rpcModel.coordinateTransforms.coordinateTransformEntity.state == .initial {
                        _ = appModel.rpcModel.sendRequest(
                            RequestSchema(
                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                method: .finishStroke,
                                param: .finishStroke(.init())
                            )
                        )
                    }
                    
                    sourceTransform = nil
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
                        let rpcResult = appModel.rpcModel.sendRequest(
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
            
            guard let nextPos = appModel.rpcModel.coordinateTransforms.getNextIndexFingerTipPosition() else {
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
        for finger in appModel.model.fingerEntities.values {
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
        let name = event.entityB.name
        
        if appModel.model.colorPalletModel.colorNames().contains(name) {
            didTouchColor(name, finger: finger)
        }
        else if appModel.model.colorPalletModel.toolNames().contains(name) {
            didTouchTool(name, finger: finger)
        }
        else if name == "eraser" {
            activateEraser(finger: finger)
        }
        else if event.entityB.hasStrokeComponent, appModel.model.isEraserMode, appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty {
            deleteStroke(event.entityB)
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
    }
    
    private func subscribeEnded(on entity: Entity, content: RealityViewContent) {
        _ = content.subscribe(to: CollisionEvents.Ended.self, on: entity) { (event: CollisionEvents.Ended) in
            handleEnded(event: event, finger: entity)
        }
    }
    
    private func handleEnded(event: CollisionEvents.Ended, finger: Entity) {
        let name = event.entityB.name
        
        if appModel.model.colorPalletModel.colorNames().contains(name) {
            _ = appModel.rpcModel.sendRequest(
                RequestSchema(
                    peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                    method: .setStrokeColor,
                    param: .setStrokeColor(.init(strokeColorName: name))
                )
            )
            if let color: UIColor =
                appModel.rpcModel.painting.advancedColorPalletModel.colorDictionary[name] {
                let material = SimpleMaterial(color: color, isMetallic: false)
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
                let cleaned = appModel.rpcModel.painting.paintingCanvas.strokes.removingShortStrokes(minPoints: 3)
                if cleaned.isEmpty { return }
                let externalStrokes: [ExternalStroke] = .init(strokes: cleaned, initPoint: .one)
                appModel.externalStrokeFileWapper.writeStroke(
                    externalStrokes: externalStrokes,
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
                toggleExternalStrokeWindow()
            }
        }
    }
    
    // MARK: — Began-handlers
    private func didTouchColor(_ name: String, finger: Entity) {
        appModel.model.changeFingerColor(entity: finger, colorName: name)
        appModel.rpcModel.painting.paintingCanvas.setMaxRadius(radius: 0.01)
        appModel.model.isEraserMode = false
    }
    
    private func didTouchTool(_ name: String, finger: Entity) {
        _ = appModel.rpcModel.sendRequest(
            RequestSchema(
                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .changeFingerLineWidth,
                param: .changeFingerLineWidth(.init(toolName: name))
            )
        )
        
        let toolBall = appModel.rpcModel.painting.advancedColorPalletModel.toolBalls.get(withID: name)
        if toolBall != nil {
            let material: SimpleMaterial = SimpleMaterial(color: appModel.rpcModel.painting.paintingCanvas.activeColor, isMetallic: false)
            finger.components.set(ModelComponent(mesh: .generateSphere(radius: Float(toolBall!.lineWidth)), materials: [material]))
        }
        appModel.model.isEraserMode = false
    }
    
    private func activateEraser(finger: Entity) {
        let eraserMat = SimpleMaterial(
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
        guard let comp: StrokeComponent = entity.components[StrokeComponent.self] else { return }
        print("Removing stroke with UUID: \(comp.uuid)")
        _ = appModel.rpcModel.sendRequest(
            RequestSchema(
                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                method: .removeStroke,
                param: .removeStroke(.init(uuid: comp.uuid))
            )
        )
    }
    
    // MARK: — Ended-handlers
    private func toggleExternalStrokeWindow() {
        if !isFileManagerActive {
            openWindow(id: "ExternalStroke")
        } else {
            for element in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                let id: Int = element.key
                let affineMatrix: simd_float4x4 = element.value
                
                let transformedExternalStrokes: [ExternalStroke] = appModel.rpcModel.painting.paintingCanvas.tmpStrokes.map { (stroke:Stroke) in
                    let transformedPoints: [SIMD3<Float>] = stroke.points.map { (point: SIMD3<Float>) in
                        let position = SIMD4<Float>(point.x, point.y, point.z, 1.0)
                        let transformed = affineMatrix * (stroke.entity.transformMatrix(relativeTo: nil) * position)
                        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
                    }
                    return ExternalStroke(points: transformedPoints, color: stroke.activeColor)
                }
                
                _ = appModel.rpcModel.sendRequest(
                    RequestSchema(
                        peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                        method: .confirmTmpStrokes,
                        param: .confirmTmpStrokes(
                            .init(externalStrokes: transformedExternalStrokes)
                        )
                    ),
                    mcPeerId: id
                )
                DispatchQueue.main.async {
                    dismissWindow(id: "ExternalStroke")
                }
            }
            isFileManagerActive.toggle()
            dismissWindow(id: "ExternalStroke")
        }
        isFileManagerActive.toggle()
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environmentObject(AppModel())
}
