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
    var isCanvasEnabled: Bool = false
    var colorPalletModel: ColorPalletModel?
    
    var session = ARKitSession()
    var handTracking = HandTrackingProvider()
    var sceneReconstruction = SceneReconstructionProvider()
    var worldTracking = WorldTrackingProvider()
    
    private var meshEntities = [UUID: ModelEntity]()
    var contentEntity = Entity()
    var initBallEntity = Entity()
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    var leftHandEntity = Entity()
    var rightHandEntity = Entity()
    
    var latestRightIndexFingerCoordinates: simd_float4x4 = .init()
    var latestLeftIndexFingerCoordinates: simd_float4x4 = .init()
    
    var latestWorldTracking: WorldAnchor = .init(originFromAnchorTransform: .init())
    
    // ここで反発係数を決定している可能性あり
    let material = PhysicsMaterialResource.generate(friction: 0.8,restitution: 0.0)
    
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }
    
    var errorState = false
    
    // ストロークを消去する時の長押し時間 added by nagao 2025/3/24
    var clearTime: Int = 0
    
    // ストロークを選択的に消去するモード added by nagao 2025/6/20
    var isEraserMode: Bool = false

    // added by nagao 2025/6/18
    var handSphereEntity: Entity? = nil

    var handArrowEntities: [Entity] = []
    
    var headLockedEntity: Entity?

    var axisVectors: [SIMD3<Float>] = [SIMD3<Float>(0,0,0), SIMD3<Float>(0,0,0), SIMD3<Float>(0,0,0)]
    
    var normalVector: SIMD3<Float> = SIMD3<Float>(0,0,0)

    var senseThreshold: Float = 0.3  // 感度の閾値
    var distanceThreshold: Float = 0.8  // 距離の閾値
    var isArrowShown: Bool = false  // 手の向きを表す矢印の表示

    func setHeadLockedEntity(_ entity: Entity) {
        self.headLockedEntity = entity
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

    func dismissHandArrowEntities() {
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
        colorPalletModel?.colorPalletEntityDisable()
    }

    var fingerEntities: [HandAnchor.Chirality: ModelEntity] = [
        //        .left: .createFingertip(name: "L", color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0)),
        .right: .createFingertip(name: "R", color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 1.0))
    ]
    
    func setupContentEntity() -> Entity {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
        
        contentEntity.addChild(initBallEntity)
        
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
    
    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(type: _, status: let status):
                print("Authorization changed to: \(status)")
                
                if status == .denied {
                    errorState = true
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                print("Data provider changed: \(providers), \(state)")
                if let error {
                    print("Data provider reached an error state: \(error)")
                    errorState = true
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }
    
    func processWorldUpdates() async {
        for await update in worldTracking.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor
                latestWorldTracking = anchor
                print(latestWorldTracking.originFromAnchorTransform.position)
            default:
                break
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
    
    // 手のひらをどこに向けているのかを判定 modified by nagao 2025/6/18
    func watchLeftPalm(handAnchor: HandAnchor) {
        // 座標変換の処理が終了するまでは、お絵描きの機能を行えないようにする
        if !isCanvasEnabled {
            return
        }

        guard let middleBase = handAnchor.handSkeleton?.joint(.middleFingerTip),
        let littleBase = handAnchor.handSkeleton?.joint(.littleFingerTip),
        let thumbBase = handAnchor.handSkeleton?.joint(.thumbTip),
        let middleFingerIntermediateBase = handAnchor.handSkeleton?.joint(.middleFingerIntermediateBase),
        let middleFingerKnuckleBase = handAnchor.handSkeleton?.joint(.middleFingerKnuckle),
        let wristBase = handAnchor.handSkeleton?.joint(.wrist)
        else { return }

        guard let head: simd_float4x4 = headLockedEntity?.transformMatrix(relativeTo: nil) else { return }

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
            colorPalletModel?.colorPalletEntityDisable()
            return
        } else {
            if handSphereEntity == nil {
                createHandSphere(wrist: wristPos, middle: middlePos, little: littlePos, isArrowShown: isArrowShown)
            } else {
                updateHandSphere(wrist: wristPos, middle: middlePos, little: littlePos)
            }
        }

        // ワールドの下方向ベクトル
        let worldUp = simd_float3(0, -1, 0)
        let dot = simd_dot(normalVector, worldUp)
        //print("💥 法線ベクトルとの内積 \(dot)")
        let distance = distance(positionMatrix.position, head.position) / 2.0
        //print("💥 頭との距離 \(distance)")
        let isShow = dot > senseThreshold && distance < distanceThreshold

        if (!isShow) {
            colorPalletModel?.colorPalletEntityDisable()
            return
        }

        guard let isEnabled = colorPalletModel?.colorPalletEntity.isEnabled else { return }

        if !isEnabled {
            colorPalletModel?.colorPalletEntityEnabled()
        }

        colorPalletModel?.updatePosition(position: positionMatrix.position, headPosition: head.position)
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

    func changeFingerColor(entity: Entity, colorName: String) {
        guard let colors = colorPalletModel?.colors else {
            return
        }
        for color in colors {
            let words = color.accessibilityName.split(separator: " ")
            if let name = words.last, name == colorName {
                let material = SimpleMaterial(color: color, isMetallic: true)
                entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
                break
            }
        }
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
    
    func initColorPalletNodel(colorPalletModel: ColorPalletModel) {
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
