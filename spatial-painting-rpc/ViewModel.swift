//
//  ViewModel.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/03/18.
//

import ARKit
import RealityKit
import SwiftUI

@Observable
@MainActor
class ViewModel {
    var colorPalletModel: AdvancedColorPalletModel = AdvancedColorPalletModel()
    
    var session = ARKitSession()
    var handTracking = HandTrackingProvider()
    var sceneReconstruction = SceneReconstructionProvider()
    
    private var meshEntities = [UUID: ModelEntity]()
    var contentEntity = Entity()
    var initBallEntity = Entity()
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    var leftHandEntity = Entity()
    var rightHandEntity = Entity()
    
    var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    var latestLeftIndexFingerCoordinates: simd_float4x4 = .init()
    
    var isGlab: Bool = false
    
    var isHandGripped: Bool = false
    
    enum OperationLock {
        case none
        case right
        case left
    }
    
    enum HandGlab {
        case right
        case left
    }
    
    var entitiyOperationLock = OperationLock.none
    
    // ここで反発係数を決定している可能性あり
    let material = PhysicsMaterialResource.generate(friction: 0.8,restitution: 0.0)
    
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }
    
    // added by nagao 2015/11/20
    enum AuthoringMode {
        case draw
        case edit
        case bezier
    }
    var authoringMode: AuthoringMode = .draw

    // ストロークを消去する時の長押し時間 added by nagao 2025/3/24
    var clearTime: Int = 0
    
    // ストロークを選択的に消去するモード added by nagao 2025/6/20
    var isEraserMode: Bool = false
    
    // ストロークを選択するモード added by nagao 2025/11/21
    var isSelectorMode: Bool = false
    
    // ペンのボタンを押しているかどうか added by nagao 2025/12/31
    var isStylusButtonPressed: Bool = false

    // added by nagao 2025/6/18
    var handSphereEntity: Entity? = nil
    
    var handArrowEntities: [Entity] = []
    
    var buttonEntity: Entity = Entity()
    
    var iconEntity: Entity = Entity()
    
    var buttonEntity2: Entity = Entity()
    
    var iconEntity2: Entity = Entity()
    
    var iconEntity3: Entity = Entity()
    
    var buttonPlateEntity: Entity = Entity()
    
    // added by nagao 2025/11/20
    var drawModeEntity: Entity = Entity()
    var editModeEntity: Entity = Entity()
    var bezierModeEntity: Entity = Entity()

    var axisVectors: [SIMD3<Float>] = [SIMD3<Float>(0,0,0), SIMD3<Float>(0,0,0), SIMD3<Float>(0,0,0)]
    
    var normalVector: SIMD3<Float> = SIMD3<Float>(0,0,0)
    
    var planeNormalVector: SIMD3<Float> = SIMD3<Float>(0,0,0)
    
    var unitVector: SIMD3<Float> = SIMD3<Float>(0,0,0)
    
    var planePoint: SIMD3<Float> = SIMD3<Float>(0,0,0)
    
    var senseThreshold: Float = 0.3  // 感度の閾値
    var distanceThreshold: Float = 0.8  // 距離の閾値
    var isArrowShown: Bool = false  // 手の向きを表す矢印の表示
    
    func setButtonEntity(_ entity: Entity) {
        self.buttonEntity = entity
    }
    
    func setButtonEntity2(_ entity: Entity) {
        self.buttonEntity2 = entity
    }
    
    func setButtonPlateEntity(_ entity: Entity) {
        //print("Set buttonPlateEntity")
        self.buttonPlateEntity = entity
        if let button = entity.findEntity(named: "button") {
            buttonEntity = button
            if let icon = button.findEntity(named: "save") {
                iconEntity = icon
            }
        }
        if let button = entity.findEntity(named: "button2") {
            buttonEntity2 = button
            if let icon2 = button.findEntity(named: "import_loupe") {
                iconEntity2 = icon2
            }
            if let icon3 = button.findEntity(named: "import_film") {
                iconEntity3 = icon3
            }
        }
    }
    
    // added by nagao 2025/11/20
    func setModeEntities(drawModeEntity: Entity, editModeEntity: Entity, bezierModeEntity: Entity) {
        self.drawModeEntity = drawModeEntity
        self.editModeEntity = editModeEntity
        self.bezierModeEntity = bezierModeEntity
    }

    func showHandArrowEntities() {
        if handSphereEntity != nil {
            contentEntity.addChild(handSphereEntity!)
            if handArrowEntities.count > 0 {
                for entity in handArrowEntities {
                    contentEntity.addChild(entity)
                }
            }
        }
    }
    
    func hideHandArrowEntities() {
        if handSphereEntity != nil {
            handSphereEntity!.removeFromParent()
            if handArrowEntities.count > 0 {
                for entity in handArrowEntities {
                    entity.removeFromParent()
                }
            }
        }
    }
    
    func dismissEntities() {
        if handSphereEntity != nil {
            handSphereEntity!.removeFromParent()
            if handArrowEntities.count > 0 {
                for entity in handArrowEntities {
                    entity.removeFromParent()
                }
                handArrowEntities = []
            }
        }
        handSphereEntity = nil
        colorPalletModel.colorPalletEntityDisable()
        
        buttonPlateEntity.removeFromParent()
        drawModeEntity.removeFromParent()
        editModeEntity.removeFromParent()
        bezierModeEntity.removeFromParent()
    }
        
    let fingerEntities: [HandAnchor.Chirality: ModelEntity] = [/*.left: .createFingertip(name: "L", color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0)),*/ .right: .createFingertip(name: "R", color: SimpleMaterial.Color.white)]

    // added by nagao 2025/12/31
    let stylusTipEntity: ModelEntity = .createFingertip(name: "StylusTipIndicator", color: SimpleMaterial.Color.white)
    
    func setupContentEntity() -> Entity {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
        
        contentEntity.addChild(initBallEntity)
        
        contentEntity.addChild(stylusTipEntity) // added by nagao 2025/12/31

        // 位置合わせする座標を教えてくれる球体の追加
        let indexFingerTipGuideBall = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.4), isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.03),
            mass: 0.0
        )
        indexFingerTipGuideBall.name = "indexFingerTipGuideBall"
        indexFingerTipGuideBall.components.set(InputTargetComponent(allowedInputTypes: .all))
        indexFingerTipGuideBall.isEnabled = false
        contentEntity.addChild(indexFingerTipGuideBall)
        
        return contentEntity
    }
    
    // 指先に球を表示 added by nagao 2025/3/22
    func showFingerTipSpheres() {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
    }
    
    func dismissFingerTipSpheres() {
        for entity in fingerEntities.values {
            entity.removeFromParent()
        }
    }
    
    // 指先の球の色を変更 added by nagao 2025/3/11
    func fingerSignal(hand: HandAnchor.Chirality, flag: Bool) {
        if flag {
            let goldColor = UIColor(red: 255/255, green: 215/255, blue: 0/255, alpha: 1.0)
            let material = SimpleMaterial(color: goldColor, isMetallic: true)
            self.fingerEntities[hand]?.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
        } else {
            let silverColor = UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0)
            let material = SimpleMaterial(color: silverColor, isMetallic: true)
            self.fingerEntities[hand]?.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
        }
    }
    
    // modified by nagao 2025/7/17
    func changeFingerColor(entity: Entity, colorName: String) {
        let colorBall = colorPalletModel.colorBalls.get(withID: colorName)
        if colorBall == nil {
            return
        }
        let prev = colorPalletModel.selectedBasicColorName
        if prev != "" {
            if colorBall!.isBasic /*|| colorName.hasPrefix("m")*/ {
                if prev == colorName {
                    return
                }
                if let prevEntity = colorPalletModel.colorEntityDictionary[prev] {
                    prevEntity.setScale(SIMD3<Float>(repeating: 0.01), relativeTo: nil)
                    let colorBall2 = colorPalletModel.colorBalls.get(withID: prev)
                    if colorBall2 != nil {
                        //print("Unselected color ball: \(colorBall2!.id)")
                        let subColorBalls = colorPalletModel.colorBalls.filterByID(containing: String(prev.prefix(1)), isBasic: false)
                        for cb in subColorBalls {
                            if let entity2: Entity = colorPalletModel.colorEntityDictionary[cb.id] {
                                entity2.removeFromParent()
                            }
                        }
                    }
                }
                colorPalletModel.selectedBasicColorName = ""
            }
        }
        if let color: UIColor = colorPalletModel.colorDictionary[colorName] {
            if color == colorPalletModel.activeColor {
                return
            }
            colorPalletModel.setActiveColor(color: color)
            let material = SimpleMaterial(color: color, isMetallic: false)
            entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
            if let colorEntity = colorPalletModel.colorEntityDictionary[colorName] {
                if colorBall!.isBasic {
                    colorEntity.setScale(SIMD3<Float>(repeating: 0.013), relativeTo: nil)
                    let subColorBalls = colorPalletModel.colorBalls.filterByID(containing: String(colorName.prefix(1)), isBasic: false)
                    for cb in subColorBalls {
                        if let entity2: Entity = colorPalletModel.colorEntityDictionary[cb.id] {
                            colorPalletModel.colorPalletEntity.addChild(entity2)
                        }
                    }
                    colorPalletModel.selectedBasicColorName = colorName
                }
                //print("Selected color ball: \(colorBall!.id)  \(colorBall!.hue)  \(colorBall!.brightness)  \(colorBall!.isSelected)")
            }
            colorPalletModel.selectedColorName = colorName // added by nagao 2025/12/31
        }
    }
    
    func changeFingerLineWidth(entity: Entity, toolName: String) {
        //print("Finger line width changed to: \(toolName)")
        if colorPalletModel.selectedToolName == toolName {
            return
        }
        let toolBall = colorPalletModel.toolBalls.get(withID: toolName)
        if toolBall != nil {
            let material = SimpleMaterial(color: colorPalletModel.activeColor, isMetallic: false)
            entity.components.set(ModelComponent(mesh: .generateSphere(radius: Float(toolBall!.lineWidth)), materials: [material]))
            //print("Selected tool ball: \(toolBall!.id)  \(toolBall!.lineWidth)  \(toolBall!.isSelected)")
        }
        colorPalletModel.selectedToolName = toolName
    }

    // added by nagao 2025/11/21
    func getColor(colorName: String) -> UIColor {
        if let color: UIColor = colorPalletModel.colorDictionary[colorName] {
            return color
        } else {
            return .black
        }
    }
    func getLineWidth(toolName: String) -> Float {
        let toolBall = colorPalletModel.toolBalls.get(withID: toolName)
        if toolBall != nil {
            return Float(toolBall!.lineWidth)
        } else {
            return 1E-2
        }
    }

    // added by nagao 2025/7/17
    func resetColor() {
        if colorPalletModel.selectedBasicColorName == "" {
            return
        }
        let prev = colorPalletModel.selectedBasicColorName
        if prev != "" {
            if let prevEntity = colorPalletModel.colorEntityDictionary[prev] {
                prevEntity.setScale(SIMD3<Float>(repeating: 0.01), relativeTo: nil)
                let colorBall2 = colorPalletModel.colorBalls.get(withID: prev)
                if colorBall2 != nil {
                    //print("Unselected color ball: \(colorBall2!.id)")
                    let subColorBalls = colorPalletModel.colorBalls.filterByID(containing: String(prev.prefix(1)), isBasic: false)
                    for cb in subColorBalls {
                        if let entity: Entity = colorPalletModel.colorEntityDictionary[cb.id] {
                            entity.removeFromParent()
                        }
                    }
                }
            }
        }
        colorPalletModel.selectedBasicColorName = ""
        //colorPalletModel.selectedColorName = ""
    }
    
    // added by nagao 2025/12/31
    func recallColor(entity: Entity) {
        let colorName: String = colorPalletModel.selectedColorName
        print("Finger color recalled to: \(colorName)")
        if colorName == "" {
            return
        }
        if let color: UIColor = colorPalletModel.colorDictionary[colorName] {
            let material = SimpleMaterial(color: color, isMetallic: false)
            entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
        }
        isEraserMode = false
    }

    // added by nagao 2025/7/17
    func changeFingerLineWidth(entity: Entity, toolName: String, activeColor: UIColor) {
        //print("Finger line width changed to: \(toolName)")
        if colorPalletModel.selectedToolName == toolName {
            return
        }
        let toolBall = colorPalletModel.toolBalls.get(withID: toolName)
        if toolBall != nil {
            let material = SimpleMaterial(color: activeColor, isMetallic: false)
            entity.components.set(ModelComponent(mesh: .generateSphere(radius: Float(toolBall!.lineWidth)), materials: [material]))
            //print("Selected tool ball: \(toolBall!.id)  \(toolBall!.lineWidth)  \(toolBall!.isSelected)")
        }
        colorPalletModel.selectedToolName = toolName
    }
    
    
    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            let meshAnchor = update.anchor
            
            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
            switch update.event {
            case .added:
                let entity = ModelEntity()
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                entity.components.set(InputTargetComponent())
                
                // mode が dynamic でないと物理演算が適用されない
                entity.physicsBody = PhysicsBodyComponent(mode: .dynamic)
                
                meshEntities[meshAnchor.id] = entity
                contentEntity.addChild(entity)
            case .updated:
                guard let entity = meshEntities[meshAnchor.id] else { continue }
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision?.shapes = [shape]
            case .removed:
                meshEntities[meshAnchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: meshAnchor.id)
            }
        }
    }
    
    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor
                
                guard anchor.isTracked else { continue }
                
                // added by nagao 2025/3/22
                let fingerTipIndex = anchor.handSkeleton?.joint(.indexFingerTip)
                let originFromWrist = anchor.originFromAnchorTransform
                let wristFromIndex = fingerTipIndex?.anchorFromJointTransform
                let originFromIndex = originFromWrist * wristFromIndex!
                fingerEntities[anchor.chirality]?.setTransformMatrix(originFromIndex, relativeTo: nil)
                
                if anchor.chirality == .left {
                    latestHandTracking.left = anchor
                    guard let handAnchor = latestHandTracking.left else { continue }
                    guard let handSkeletonAnchorTransform = latestHandTracking.left?.handSkeleton?.joint(.indexFingerTip).anchorFromJointTransform else { return }
                    latestLeftIndexFingerCoordinates = handAnchor.originFromAnchorTransform * handSkeletonAnchorTransform
                    watchLeftPalm(handAnchor: handAnchor)
                } else if anchor.chirality == .right {
                    latestHandTracking.right = anchor
                    guard let handAnchor = latestHandTracking.right else { continue }
                    guard let handSkeletonAnchorTransform = latestHandTracking.right?.handSkeleton?.joint(.indexFingerTip).anchorFromJointTransform else { return }
                    latestRightIndexFingerCoordinates = handAnchor.originFromAnchorTransform * handSkeletonAnchorTransform
                }
            default:
                break
            }
        }
    }
    
    // 左の掌の向きを計算
    func watchLeftPalm(handAnchor: HandAnchor) {
        guard let middleBase = handAnchor.handSkeleton?.joint(.middleFingerTip),
              let littleBase = handAnchor.handSkeleton?.joint(.littleFingerTip),
              let thumbBase = handAnchor.handSkeleton?.joint(.thumbTip),
              let middleFingerIntermediateBase = handAnchor.handSkeleton?.joint(.middleFingerIntermediateBase),
              let middleFingerKnuckleBase = handAnchor.handSkeleton?.joint(.middleFingerKnuckle),
              let wristBase = handAnchor.handSkeleton?.joint(.wrist)
        else { return }
        
        guard let rightHandAnchor = latestHandTracking.right,
              let rightWristBase = rightHandAnchor.handSkeleton?.joint(.wrist)
        else { return }
        
        let middle: simd_float4x4 = handAnchor.originFromAnchorTransform * middleBase.anchorFromJointTransform
        let little: simd_float4x4 = handAnchor.originFromAnchorTransform * littleBase.anchorFromJointTransform
        let wrist: simd_float4x4 = handAnchor.originFromAnchorTransform * wristBase.anchorFromJointTransform
        let thumb: simd_float4x4 = handAnchor.originFromAnchorTransform * thumbBase.anchorFromJointTransform
        let positionMatrix: simd_float4x4 = handAnchor.originFromAnchorTransform * middleFingerIntermediateBase.anchorFromJointTransform
        let middleKnuckle: simd_float4x4 = handAnchor.originFromAnchorTransform * middleFingerKnuckleBase.anchorFromJointTransform
        
        let wristPos = simd_make_float3(wrist.columns.3)
        let middlePos = simd_make_float3(middle.columns.3)
        let littlePos = simd_make_float3(little.columns.3)
        let thumbPos = simd_make_float3(thumb.columns.3)
        let middleKnucklePos = simd_make_float3(middleKnuckle.columns.3)
        
        let distances = [
            distance(middlePos, thumbPos),
            distance(middlePos, littlePos),
            distance(middlePos, wristPos)
        ]
        
        //print("hand joints distance \(distances)")
        let handSize = max(distance(wristPos, middleKnucklePos), 0.1) // 手のサイズの最大値を取得
        //print("hand size \(handSize)")
        let threshold = handSize * 0.5 // 手のサイズに基づいた閾値を計算
        let flag = distances.allSatisfy { $0 > threshold }
        
        let distances2 = [
            distance(middlePos, thumbPos),
            distance(middlePos, littlePos),
            distance(thumbPos, littlePos),
        ]
        isHandGripped = distances2.allSatisfy { $0 < threshold }
        
        if !flag {
            if isArrowShown && handSphereEntity != nil {
                handSphereEntity!.removeFromParent()
                if handArrowEntities.count > 0 {
                    for entity in handArrowEntities {
                        entity.removeFromParent()
                    }
                    handArrowEntities = []
                }
            }
            handSphereEntity = nil
            colorPalletModel.colorPalletEntityDisable()
            return
        } else {
            if handSphereEntity == nil {
                createHandSphere(wrist: wristPos, middle: middlePos, little: littlePos, isArrowShown: isArrowShown)
            } else {
                updateHandSphere(wrist: wristPos, middle: middlePos, little: littlePos)
            }
        }
        
        // ワールドの上方向ベクトル
        let worldUp = simd_float3(0, 1, 0)
        let dot = simd_dot(normalVector, worldUp)
        if dot > senseThreshold {
            let point = calculateExtendedPoint(point: planePoint, vector: normalVector, distance: 0.05)
            let matrix = makeBoxTransformMatrix(center: point, longAxis: planeNormalVector, size: SIMD3<Float>(2.5, 2.5, 2.5))
            buttonPlateEntity.setTransformMatrix(matrix, relativeTo: nil)
            let isButtonExist = contentEntity.children.contains { $0 === buttonPlateEntity }
            if !isButtonExist {
                contentEntity.addChild(buttonPlateEntity)
            }
            let unitVector2 = projectOntoPlane(vector: unitVector, normalVector: SIMD3<Float>(0,1,0))
            let point2 = calculateExtendedPoint(point: planePoint, vector: normalVector, distance: 0.15)
            let point3 = calculateExtendedPoint(point: point2, vector: unitVector2, distance: 0.08)
            let point4 = calculateExtendedPoint(point: point2, vector: unitVector2, distance: -0.08)
            var drawScale: Float = 2.0
            var editScale: Float = 2.0
            var bezierScale: Float = 2.0
            switch authoringMode {
            case .draw:
                drawScale = 2.5
            case .edit:
                editScale = 2.5
            case .bezier:
                bezierScale = 2.5
            }
            let matrix2 = makeBoxTransformMatrix(center: point2, longAxis: planeNormalVector, size: SIMD3<Float>(editScale, editScale, editScale))
            let matrix3 = makeBoxTransformMatrix(center: point3, longAxis: planeNormalVector, size: SIMD3<Float>(drawScale, drawScale, drawScale))
            let matrix4 = makeBoxTransformMatrix(center: point4, longAxis: planeNormalVector, size: SIMD3<Float>(bezierScale, bezierScale, bezierScale))

            drawModeEntity.setTransformMatrix(matrix3, relativeTo: nil)
            let isDrawModeExist = contentEntity.children.contains { $0 === drawModeEntity }
            if !isDrawModeExist {
                contentEntity.addChild(drawModeEntity)
            }
            editModeEntity.setTransformMatrix(matrix2, relativeTo: nil)
            let isEditModeExist = contentEntity.children.contains { $0 === editModeEntity }
            if !isEditModeExist {
                contentEntity.addChild(editModeEntity)
            }
            bezierModeEntity.setTransformMatrix(matrix4, relativeTo: nil)
            let isBezierModeExist = contentEntity.children.contains { $0 === bezierModeEntity }
            if !isBezierModeExist {
                contentEntity.addChild(bezierModeEntity)
            }
        } else {
            buttonPlateEntity.removeFromParent()
            drawModeEntity.removeFromParent()
            editModeEntity.removeFromParent()
            bezierModeEntity.removeFromParent()
        }
        
        // ワールドの下方向ベクトル
        let worldDown = simd_float3(0, -1, 0)
        let dot2 = simd_dot(normalVector, worldDown)
        //print("💥 法線ベクトルとの内積 \(dot)")
        
        let rightWrist: simd_float4x4 = rightHandAnchor.originFromAnchorTransform * rightWristBase.anchorFromJointTransform
        let rightWristPos = simd_make_float3(rightWrist.columns.3)
        let distance = distance(positionMatrix.position, rightWristPos)
        //print("💥 右手との距離 \(distance)")
        
        let isShow = dot2 > senseThreshold && distance < distanceThreshold
        
        if (!isShow) {
            colorPalletModel.colorPalletEntityDisable()
            return
        }
        
        //colorPalletModel.colorPalletEntityEnabled()
        if !(colorPalletModel.colorPalletEntity.isEnabled) {
            colorPalletModel.colorPalletEntityEnabled()
        }
        
        colorPalletModel.updatePosition(position: positionMatrix.position, unitVector: unitVector, distVector: planeNormalVector)
    }
    
    func createHandSphere(wrist: SIMD3<Float>, middle: SIMD3<Float>, little: SIMD3<Float>, isArrowShown: Bool) {
        // 中指と手首を結ぶベクトル
        let axisVector = simd_float3(x: middle.x - wrist.x, y: middle.y - wrist.y, z: middle.z - wrist.z)
        
        axisVectors[0] = simd_normalize(axisVector)
        
        // 線分ABから点Cへの垂線ベクトルを計算
        let perpendicularVector = perpendicularVectorFromPointToSegment(A: wrist, B: middle, C: little)
        
        axisVectors[1] = simd_normalize(perpendicularVector)
        
        axisVectors[2] = simd_cross(axisVectors[0], axisVectors[1])
        
        let sphereEntity = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [SimpleMaterial(color: .systemRed, isMetallic: false)], collisionShape: .generateSphere(radius: 0.02), mass: 0.0)
        
        let center = (wrist + middle) / 2.0
        
        sphereEntity.position = center
        
        if isArrowShown {
            contentEntity.addChild(sphereEntity)
        }
        
        handSphereEntity = sphereEntity
        
        normalVector = axisVectors[2]
        
        planeNormalVector = axisVectors[0]
        
        unitVector = axisVectors[1]
        
        planePoint = center
        
        for vector in axisVectors {
            let arrowEntity = Entity()
            
            // 矢印の円柱（軸部分）を作成
            let arrowLength: Float = 0.15
            let direction = vector
            let cylinderMesh = MeshResource.generateCylinder(height: arrowLength * 0.8, radius: 0.01)
            let material = SimpleMaterial(color: .green, isMetallic: false)
            let cylinderEntity = ModelEntity(mesh: cylinderMesh, materials: [material])
            
            // 回転軸に沿った回転を適用
            let axisDirection = normalize(direction)
            let quaternion = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: axisDirection)
            cylinderEntity.orientation = quaternion
            
            // 位置を設定（矢印の中央が開始位置になるように調整）
            cylinderEntity.position = direction * arrowLength * 0.4
            arrowEntity.addChild(cylinderEntity)
            
            // 矢尻（円錐部分）を作成
            let coneMesh = MeshResource.generateCone(height: arrowLength * 0.2, radius: 0.02)
            let coneMaterial = SimpleMaterial(color: .red, isMetallic: false)
            let coneEntity = ModelEntity(mesh: coneMesh, materials: [coneMaterial])
            
            // 矢尻の回転を軸に合わせる
            coneEntity.orientation = quaternion
            
            // 矢尻の位置を調整（矢印の先端に配置）
            coneEntity.position = direction * arrowLength * 0.9
            arrowEntity.addChild(coneEntity)
            
            arrowEntity.position = center
            
            handArrowEntities.append(arrowEntity)
            
            if isArrowShown {
                contentEntity.addChild(arrowEntity)
            }
        }
    }
    
    func updateHandSphere(wrist: SIMD3<Float>, middle: SIMD3<Float>, little: SIMD3<Float>) {
        if handSphereEntity == nil {
            return
        }
        
        // 中指と手首を結ぶベクトル
        let axisVector = simd_float3(x: middle.x - wrist.x, y: middle.y - wrist.y, z: middle.z - wrist.z)
        
        let currentAxisVector = simd_normalize(axisVector)
        
        // 線分ABから点Cへの垂線ベクトルを計算
        let perpendicularVector = perpendicularVectorFromPointToSegment(A: wrist, B: middle, C: little)
        
        let currentLittleVector = simd_normalize(perpendicularVector)
        
        let currentNormalVector = simd_cross(currentAxisVector, currentLittleVector)
        
        let center = (wrist + middle) / 2.0
        
        handSphereEntity!.position = center
        
        normalVector = currentNormalVector
        
        planeNormalVector = currentAxisVector
        
        unitVector = currentLittleVector
        
        planePoint = center
        
        let vectors = [currentAxisVector, currentLittleVector, currentNormalVector]
        var quats: [simd_quatf] = []
        for (index, vector) in vectors.enumerated() {
            let arrowEntity = handArrowEntities[index]
            
            arrowEntity.position = center
            
            // クォータニオンを計算
            let quat = calculateQuaternionFromVectors(axisVectors[index], vector)
            quats.append(quat)
            
            // エンティティに回転を適用
            arrowEntity.orientation = quat
        }
    }
    
    // 線分ABからCへの垂線ベクトルを計算する関数
    func perpendicularVectorFromPointToSegment(A: simd_float3, B: simd_float3, C: simd_float3) -> simd_float3 {
        let AB = B - A
        let AC = C - A
        
        // tの計算 (ACをABに射影するためのスカラー)
        let t = simd_dot(AC, AB) / simd_dot(AB, AB)
        
        // 射影点Pを計算
        let projection = A + t * AB
        
        // 点Cから射影点Pへのベクトル (これが垂線ベクトル)
        let perpendicularVector = C - projection
        return perpendicularVector
    }
    
    // 法線ベクトルを計算する関数
    func calculateNormalVector(A: simd_float3, B: simd_float3, C: simd_float3) -> simd_float3 {
        let AB = B - A
        let AC = C - A
        let normal = simd_cross(AB, AC)
        return simd_normalize(normal)
    }
    
    // ベクトルAからベクトルBへの回転を計算する関数
    func calculateQuaternionFromVectors(_ A: simd_float3, _ B: simd_float3) -> simd_quatf {
        // ベクトルAとベクトルBを正規化する
        let normalizedA = simd_normalize(A)
        let normalizedB = simd_normalize(B)
        
        // ベクトルAとBの内積を使ってコサイン角度を計算
        let dotProduct = simd_dot(normalizedA, normalizedB)
        
        // もしベクトルAとBが平行でない場合、回転軸を外積で求める
        let crossProduct = simd_cross(normalizedA, normalizedB)
        
        // 回転角度は内積の逆余弦で計算
        let angle = acos(dotProduct)
        
        // 回転クォータニオンを作成
        if simd_length(crossProduct) > 1e-6 {
            // 有効な回転軸が存在する場合にクォータニオンを作成
            return simd_quatf(angle: angle, axis: simd_normalize(crossProduct))
        } else {
            // AとBが同じ方向を向いている場合、単位クォータニオンを返す
            return simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))  // 回転不要
        }
    }
    
    /// 中心 `center` と長辺方向ベクトル `longAxis`、そして box のサイズ `size`
    /// (x: 短辺, y: 高さ, z: 長辺) から
    /// 回転・スケール・平行移動を含む 4×4 ワールド変換行列を作成する
    func makeBoxTransformMatrix(
        center: SIMD3<Float>,
        longAxis: SIMD3<Float>,
        size: SIMD3<Float>
    ) -> float4x4 {
        // 1) 長辺方向を正規化してローカルZ軸に
        let axisZ = normalize(longAxis)
        
        // 2) ワールド上方向を平面に投影してローカルX軸を作成
        //    → まずワールド上方向ベクトル (0,1,0) と直交するベクトルを求める
        let worldUp = SIMD3<Float>(0, 1, 0)
        var axisX = cross(axisZ, worldUp)
        if length_squared(axisX) < 1e-6 {
            // axisZ と worldUp がほぼ平行なら別ベクトルを使う
            axisX = cross(axisZ, SIMD3<Float>(1, 0, 0))
        }
        axisX = normalize(axisX)
        
        // 3) ローカル Y 軸は右手系で残りの軸として生成
        let axisY = cross(axisX, axisZ)
        
        // 4) サイズの半分を軸ごとにスケール成分として利用
        let halfSize = size * 0.5
        let sx = halfSize.x, sy = halfSize.y, sz = halfSize.z
        
        // 5) 行列組み立て (列優先)
        var m = matrix_identity_float4x4
        // X 軸列
        m.columns.0 = SIMD4<Float>(axisX.x * sx,
                                   axisX.y * sx,
                                   axisX.z * sx,
                                   0)
        // Y 軸列
        m.columns.1 = SIMD4<Float>(axisY.x * sy,
                                   axisY.y * sy,
                                   axisY.z * sy,
                                   0)
        // Z 軸列
        m.columns.2 = SIMD4<Float>(-axisZ.x * sz,
                                   -axisZ.y * sz,
                                   -axisZ.z * sz,
                                   0)
        // 平行移動列
        m.columns.3 = SIMD4<Float>(center.x,
                                   center.y,
                                   center.z,
                                   1)
        
        return m
    }
    
    // 点から単位ベクトル方向にある、その点から一定距離分離れた位置の点を計算する関数
    func calculateExtendedPoint(point: SIMD3<Float>, vector: SIMD3<Float>, distance: Float) -> SIMD3<Float> {
        // 単位ベクトルにスカラー量（距離）を掛けて延長方向のベクトルを計算
        let extensionVector = SIMD3<Float>(x: vector.x * distance, y: vector.y * distance, z: vector.z * distance)
        
        // 点に延長ベクトルを加えて、新しい点の座標を計算
        let extendedPoint = SIMD3<Float>(x: point.x + extensionVector.x, y: point.y + extensionVector.y, z: point.z + extensionVector.z)
        
        return extendedPoint
    }
    
    // あるベクトルを、別のベクトルが法線ベクトルとなる平面に射影したベクトルを計算する関数
    func projectOntoPlane(vector: SIMD3<Float>, normalVector: SIMD3<Float>, epsilon: Float = 1e-8) -> SIMD3<Float> {
        let denom = simd_length_squared(normalVector)
        if denom < epsilon {
            // 法線がゼロに近い場合は平面が定義できないため、そのまま返す（または適宜エラー処理）
            return vector
        }
        let t = simd_dot(vector, normalVector) / denom
        return vector - t * normalVector
    }

    // ストロークを消去する時の長押し時間の処理 added by nagao 2025/3/24
    func recordTime(isBegan: Bool) -> Bool {
        if isBegan {
            let now = Date()
            let milliseconds = Int(now.timeIntervalSince1970 * 1000)
            let calendar = Calendar.current
            let nanoseconds = calendar.component(.nanosecond, from: now)
            let exactMilliseconds = milliseconds + (nanoseconds / 1_000_000)
            clearTime = exactMilliseconds
            //print("現在時刻: \(exactMilliseconds)")
            return true
        } else {
            if clearTime > 0 {
                let now = Date()
                let milliseconds = Int(now.timeIntervalSince1970 * 1000)
                let calendar = Calendar.current
                let nanoseconds = calendar.component(.nanosecond, from: now)
                let exactMilliseconds = milliseconds + (nanoseconds / 1_000_000)
                let time = exactMilliseconds - clearTime
                if time > 1000 {
                    clearTime = 0
                    //print("経過時間: \(time)")
                    return true
                }
            }
            return false
        }
    }
    
    func resetInitBall() {
        initBallEntity.removeFromParent()
        initBallEntity = Entity()
        contentEntity.addChild(initBallEntity)
    }
    
    func initBall(transform: simd_float4x4, ballColor: SimpleMaterial.Color) {
        let ball = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: .cyan, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.05),
            mass: 0.0
        )
        ball.name = "rightIndexTip"
        ball.setPosition(transform.position, relativeTo: nil)
        ball.setOrientation(simd_quatf(transform), relativeTo: nil)
        ball.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        initBallEntity.addChild(ball)
        
        // zStrokeArrow
        let zStroke = ModelEntity(
            mesh: .init(shape: .generateBox(width: 0.004, height: 0.004, depth: 0.1)),
            materials: [SimpleMaterial(color: .blue, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        
        zStroke.name = "zStrokeArrow"
        zStroke.setPosition(SIMD3<Float>(0, 0, 0.05), relativeTo: ball)
        zStroke.setOrientation(simd_quatf(transform), relativeTo: nil)
        zStroke.components.set(InputTargetComponent(allowedInputTypes: .all))
        initBallEntity.addChild(zStroke)
        
        // yStrokeArrow
        let yStroke = ModelEntity(
            mesh: .init(shape: .generateBox(width: 0.004, height: 0.1, depth: 0.004)),
            materials: [SimpleMaterial(color: .green, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        yStroke.name = "yStrokeArrow"
        yStroke.setPosition(SIMD3<Float>(0, 0.05, 0), relativeTo: ball)
        yStroke.setOrientation(simd_quatf(transform), relativeTo: nil)
        yStroke.components.set(InputTargetComponent(allowedInputTypes: .all))
        initBallEntity.addChild(yStroke)
        
        // xStrokeArrow
        let xStroke = ModelEntity(
            mesh: .init(shape: .generateBox(width: 0.1, height: 0.004, depth: 0.004)),
            materials: [SimpleMaterial(color: .red, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        xStroke.name = "xStrokeArrow"
        xStroke.setPosition(SIMD3<Float>(0.05, 0, 0), relativeTo: ball)
        xStroke.setOrientation(simd_quatf(transform), relativeTo: nil)
        xStroke.components.set(InputTargetComponent(allowedInputTypes: .all))
        initBallEntity.addChild(xStroke)
    }
    
    func initColorPalletModel(colorPalletModel: AdvancedColorPalletModel) {
        //print("initColorPalletModel")
        self.colorPalletModel = colorPalletModel
    }
    
    enum enableIndexFingerTipGuideBallPosition {
        case left
        case right
        case top
    }
    
    func enableIndexFingerTipGuideBall(position: SIMD3<Float>) {
        guard let indexFingerTipGuideBall = contentEntity.findEntity(named: "indexFingerTipGuideBall") else {
            print("indexFingerTipGuideBall not found")
            return
        }
        indexFingerTipGuideBall.setPosition(position, relativeTo: nil)
        indexFingerTipGuideBall.isEnabled = true
    }
    
    func disableIndexFingerTipGuideBall() {
        guard let indexFingerTipGuideBall = contentEntity.findEntity(named: "indexFingerTipGuideBall") else {
            print("indexFingerTipGuideBall not found")
            return
        }
        indexFingerTipGuideBall.isEnabled = false
    }
}
