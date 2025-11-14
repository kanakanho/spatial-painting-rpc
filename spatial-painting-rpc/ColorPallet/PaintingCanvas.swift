/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 A class that creates a volume so that a person can create meshes with the location of the drag gesture.
 */

import SwiftUI
import RealityKit

struct IndividualStroke {
    var currentStroke: BezierStroke?
    var currentPosition: SIMD3<Float> = .zero
    var isFirstStroke: Bool = true
    var activeColor: SimpleMaterial.Color = SimpleMaterial.Color.white
    var maxRadius: Float = 1E-2
}

@Observable
/// A class that stores each stroke and generates a mesh, in real time, from a person's gesture movement.
class PaintingCanvas {
    /// The main root entity for the painting canvas.
    let root = Entity()
    
    var strokes: [BezierStroke] = []
    let tmpRoot = Entity()
    var tmpStrokes: [BezierStroke] = []
    var tmpBoundingBoxEntity: Entity = Entity()
    var tmpBoundingBox: BoundingBoxCube = BoundingBoxCube()
    
    var eraserEntity: Entity = Entity()
    
    // added by nagao 2025/7/10
    var boundingBoxEntity: ModelEntity = ModelEntity()
    
    var boundingBoxCenter: SIMD3<Float> = .zero
    
    /// The stroke that a person creates.
    /// UUID : UserId
    var individualStrokeDic: [UUID: IndividualStroke] = [:]
    
    /// Whether it is in control mode.
    var isControlMode: Bool = false
    
    /// The distance for the box that extends in the positive direction.
    let big: Float = 1E2
    
    /// The distance for the box that extends in the negative direction.
    let small: Float = 1E-2
    
    // Sets up the painting canvas with six collision boxes that stack on each other.
    init() {
        root.addChild(addBox(size: [big, big, small], position: [0, 0, -0.5 * big]))
        root.addChild(addBox(size: [big, big, small], position: [0, 0, +0.5 * big]))
        root.addChild(addBox(size: [big, small, big], position: [0, -0.5 * big, 0]))
        root.addChild(addBox(size: [big, small, big], position: [0, +0.5 * big, 0]))
        root.addChild(addBox(size: [small, big, big], position: [-0.5 * big, 0, 0]))
        root.addChild(addBox(size: [small, big, big], position: [+0.5 * big, 0, 0]))
        root.addChild(tmpRoot)
        
        let color = UIColor(red: 192/255, green: 192/255, blue: 192/255, alpha: 0.5)
        boundingBoxEntity = ModelEntity(
            mesh: .generateBox(size: 0.1, cornerRadius: 0.0),
            materials: [SimpleMaterial(color: color, isMetallic: true)],
            collisionShape: .generateBox(size: SIMD3<Float>(repeating: 0.1)),
            mass: 0.0)
        boundingBoxEntity.name = "boundingBox"
        boundingBoxEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
    }
    
    func reset() {
        root.children.removeAll()
        strokes.removeAll()
        root.addChild(addBox(size: [big, big, small], position: [0, 0, -0.5 * big]))
        root.addChild(addBox(size: [big, big, small], position: [0, 0, +0.5 * big]))
        root.addChild(addBox(size: [big, small, big], position: [0, -0.5 * big, 0]))
        root.addChild(addBox(size: [big, small, big], position: [0, +0.5 * big, 0]))
        root.addChild(addBox(size: [small, big, big], position: [-0.5 * big, 0, 0]))
        root.addChild(addBox(size: [small, big, big], position: [+0.5 * big, 0, 0]))
        root.addChild(tmpRoot)
    }
    
    /// Create a collision box that takes in user input with the drag gesture.
    private func addBox(size: SIMD3<Float>, position: SIMD3<Float>) -> Entity {
        /// The new entity for the box.
        let box = Entity()
        
        // Enable user inputs.
        box.components.set(InputTargetComponent())
        
        // Enable collisions for the box.
        box.components.set(CollisionComponent(shapes: [.generateBox(size: size)], isStatic: true))
        
        // Set the position of the box from the position value.
        box.position = position
        
        return box
    }
    
    func setActiveColor(userId: UUID ,color: SimpleMaterial.Color) {
        if let individualStroke: IndividualStroke = individualStrokeDic[userId] {
            var newIndividualStroke = individualStroke
            newIndividualStroke.activeColor = color
            individualStrokeDic[userId] = newIndividualStroke
        } else {
            individualStrokeDic[userId] = IndividualStroke(activeColor: color)
        }
    }
    
    func setMaxRadius(userId: UUID,radius: Float) {
        if let individualStroke: IndividualStroke = individualStrokeDic[userId] {
            var newIndividualStroke = individualStroke
            newIndividualStroke.maxRadius = radius
            individualStrokeDic[userId] = newIndividualStroke
        } else {
            individualStrokeDic[userId] = IndividualStroke(maxRadius: radius)
        }
    }
    
    func setEraserEntity(_ entity: Entity) {
        eraserEntity = entity
    }
    
    /// Generate a point when the individual uses the drag gesture.
    func addPoint(_ strokeId: UUID, _ position: SIMD3<Float>, userId: UUID) {
        var individualStroke: IndividualStroke = individualStrokeDic[userId] ?? IndividualStroke()
        
        if individualStroke.isFirstStroke {
            individualStroke.isFirstStroke = false
            individualStrokeDic[userId] = individualStroke
            return
        }
        
        /// currentPosition との距離が一定以上離れている場合は早期リターンする
        let distance = length(position - individualStroke.currentPosition)
        individualStroke.currentPosition = position
        //print("distance: \(distance)")
        if distance > 0.1 {
            //print("distance is too far, return")
            individualStroke.currentStroke = nil
            individualStrokeDic[userId] = individualStroke
            return
        }
        
        /// The maximum distance between two points before requiring a new point.
        let threshold: Float = 1E-9
        
        // Start a new stroke if no stroke exists.
        if individualStroke.currentStroke == nil {
            individualStroke.currentStroke = BezierStroke(uuid: strokeId)
            individualStroke.currentStroke!.setActiveColor(color: individualStroke.activeColor)
            individualStroke.currentStroke!.setMaxRadius(radius: individualStroke.maxRadius)
            strokes.append(individualStroke.currentStroke!)
            
            // Add the stroke to the root.
            root.addChild(individualStroke.currentStroke!.root)
        }
        
        // Check whether the length between the current hand position and the previous point meets the threshold.
        if let previousPoint = individualStroke.currentStroke?.points.last, length(position - previousPoint) < threshold {
            return
        }
        
        // Add the current position to the stroke.
        individualStroke.currentStroke?.points.append(position)
        
        // Update the current stroke mesh.
        individualStroke.currentStroke?.updateMesh()
        
        individualStrokeDic[userId] = individualStroke
    }
    
    /// Clear the stroke when the drag gesture ends.
    func finishStroke(_ uuid: UUID) {
        guard var individualStroke: IndividualStroke = individualStrokeDic[uuid] else {
            return
        }
        
        if let stroke = individualStroke.currentStroke {
            // Trigger the update mesh operation.
            if stroke.points.count < 4 {
                strokes.removeAll { $0.uuid == stroke.uuid }
                stroke.root.removeFromParent()
                individualStroke.currentStroke = nil
                individualStrokeDic[uuid] = individualStroke
                return
            }
            stroke.finishRemesh()
            for i in 0..<stroke.bezierPoints.count {
                individualStroke.currentStroke?.root.addChild(stroke.bezierPoints[i].root)
            }
            
            var count = 0
            for point in stroke.points {
                if count % 5 == 0 {
                    let entity = eraserEntity.clone(recursive: true)
                    entity.name = "clear"
                    var invisibleMaterial = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1.0))
                    invisibleMaterial.opacityThreshold = 1.0
                    entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [invisibleMaterial]))
                    entity.components.set(StrokeRootComponent(stroke.uuid))
                    entity.setScale([0.0025, 0.0025, 0.0025], relativeTo: nil)
                    entity.position = point
                    root.addChild(entity)
                }
                count += 1
            }
            
            individualStroke.currentStroke?.bezierPoints.forEach {
                $0.root.isEnabled = false
            }
            
            // Clear the current stroke.
            individualStroke.currentStroke = nil
            
            individualStrokeDic[uuid] = individualStroke
        }
    }
    
    func isControlModeToggle() {
        isControlMode.toggle()
        if isControlMode {
            startControlMode()
        } else {
            finishControlMode()
        }
    }
    
    func startControlMode() {
        for stroke in strokes {
            for bezierPoint in stroke.bezierPoints {
                bezierPoint.root.isEnabled = true
            }
            stroke.updateMeshEnableFaceCulling()
        }
    }
    
    func finishControlMode() {
        for stroke in strokes {
            for bezierPoint in stroke.bezierPoints {
                bezierPoint.root.isEnabled = false
            }
            stroke.updateMeshDisableFaceCulling()
        }
    }
    
    func moveControlPoint(strokeId: UUID, controlPointId: UUID, controlType: BezierStroke.BezierPoint.PointType, newPosition: SIMD3<Float>) {
        for stroke in strokes {
            if stroke.uuid == strokeId {
                stroke.bezierPoints.add(pointId: controlPointId, point: newPosition, pn: controlType)
                stroke.updateMesh()
            }
        }
    }
    
    func finishControlPoint(strokeId: UUID, controlPointId: UUID) {
        for stroke in strokes {
            if stroke.uuid == strokeId {
                stroke.updateMesh()
                
                // 既存のEraserEntityを削除
                root.children.removeAll(where: { $0.name == "clear" && $0.components[StrokeRootComponent.self]?.uuid == stroke.uuid })
                
                var count = 0
                for point in stroke.points {
                    if count % 5 == 0 {
                        let entity = eraserEntity.clone(recursive: true)
                        entity.name = "clear"
                        var invisibleMaterial = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1.0))
                        invisibleMaterial.opacityThreshold = 1.0
                        entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [invisibleMaterial]))
                        entity.components.set(StrokeRootComponent(stroke.uuid))
                        entity.setScale([0.0025, 0.0025, 0.0025], relativeTo: nil)
                        entity.position = point
                        root.addChild(entity)
                    }
                    count += 1
                }
            }
        }
    }
    
    func addStrokes(_ strokes: [BezierStroke]) {
        for stroke in strokes {
            addStroke(stroke)
        }
    }
    
    func addStroke(_ stroke: BezierStroke) {
        let newStroke = BezierStroke(uuid: stroke.uuid)
        newStroke.maxRadius = stroke.maxRadius
        newStroke.setActiveColor(color: stroke.activeColor)
        newStroke.points = stroke.points
        newStroke.finishRemesh()
        for i in 0..<newStroke.bezierPoints.count {
            newStroke.root.addChild(newStroke.bezierPoints[i].root)
        }
        
        var count = 0
        for point in stroke.points {
            if count % 5 == 0 {
                let entity = eraserEntity.clone(recursive: true)
                entity.name = "clear"
                var invisibleMaterial = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1.0))
                invisibleMaterial.opacityThreshold = 1.0
                entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [invisibleMaterial]))
                entity.components.set(StrokeRootComponent(stroke.uuid))
                entity.setScale([0.0025, 0.0025, 0.0025], relativeTo: nil)
                entity.position = point
                root.addChild(entity)
            }
            count += 1
        }
        
        newStroke.bezierPoints.forEach {
            $0.root.isEnabled = false
        }
        
        strokes.append(newStroke)
        root.addChild(newStroke.root)
    }
}

/// 直接 Stroke を追加するときに行う処理の拡張
extension PaintingCanvas {
    /// 一時的な Stroke をまとめて追加する modified by nagao 2015/7/10
    func addTmpStrokes(_ strokes: [BezierStroke]) {
        //print("load tmp strokes")
        for stroke in strokes {
            addTmpStroke(stroke)
        }
        
        // 頂点同士を繋ぐ線のエンティティを生成
        generateBoundingBox()
        
        generateInputTargetEntity()
        
        for stroke in tmpStrokes {
            stroke.points = stroke.points.map { (position:  SIMD3<Float>) in
                // entityのローカル座標に変換する
                return stroke.root.convert(position: position, from: nil)
            }
            stroke.root.setPosition(stroke.root.position - boundingBoxCenter, relativeTo: nil)
            boundingBoxEntity.addChild(stroke.root)
        }
        tmpRoot.addChild(boundingBoxEntity)
    }
    
    // modified by nagao 2015/7/10
    func generateInputTargetEntity() {
        let shapes = ShapeResource.generateBox(
            width: tmpBoundingBox.corners[.maxXMaxYMaxZ]!.x - tmpBoundingBox.corners[.minXMinYMinZ]!.x,
            height: tmpBoundingBox.corners[.maxXMaxYMaxZ]!.y - tmpBoundingBox.corners[.minXMinYMinZ]!.y,
            depth: tmpBoundingBox.corners[.maxXMaxYMaxZ]!.z - tmpBoundingBox.corners[.minXMinYMinZ]!.z
        )
        let mesh = MeshResource.generateBox(
            width: tmpBoundingBox.corners[.maxXMaxYMaxZ]!.x - tmpBoundingBox.corners[.minXMinYMinZ]!.x,
            height: tmpBoundingBox.corners[.maxXMaxYMaxZ]!.y - tmpBoundingBox.corners[.minXMinYMinZ]!.y,
            depth: tmpBoundingBox.corners[.maxXMaxYMaxZ]!.z - tmpBoundingBox.corners[.minXMinYMinZ]!.z
        )
        let midPoint = tmpBoundingBox.center
        boundingBoxCenter = midPoint
        let color = UIColor(red: 192/255, green: 192/255, blue: 192/255, alpha: 0.5)
        let material = SimpleMaterial(color: color, isMetallic: true)
        
        boundingBoxEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        boundingBoxEntity.components.set(CollisionComponent(shapes: [shapes], isStatic: true))
        boundingBoxEntity.setPosition(midPoint, relativeTo: nil)
    }
    
    /// 一時的な Stroke を追加する
    func addTmpStroke(_ stroke: BezierStroke) {
        let newStroke = BezierStroke(uuid: stroke.uuid, originalMaxRadius: stroke.originalMaxRadius)
        newStroke.maxRadius = stroke.maxRadius
        newStroke.setActiveColor(color: stroke.activeColor)
        newStroke.points = stroke.points
        newStroke.updateMesh()
        self.tmpStrokes.append(newStroke)
    }
    
    /// 追加処理の完了 modified by nagao 2015/7/10
    func confirmTmpStrokes() {
        if tmpStrokes.isEmpty { return }
        for stroke in tmpStrokes {
            stroke.points = stroke.points.map { (position: SIMD3<Float>) in
                return SIMD3<Float>(stroke.root.transformMatrix(relativeTo: nil) * SIMD4<Float>(position, 1.0))
            }
            let newStroke = BezierStroke(uuid: stroke.uuid, originalMaxRadius: stroke.originalMaxRadius)
            newStroke.maxRadius = stroke.maxRadius
            newStroke.setActiveColor(color: stroke.activeColor)
            newStroke.points = stroke.points
            newStroke.finishRemesh()
            for i in 0..<newStroke.bezierPoints.count {
                newStroke.root.addChild(newStroke.bezierPoints[i].root)
            }
            
            newStroke.bezierPoints.forEach {
                $0.root.isEnabled = false
            }
            
            strokes.append(newStroke)
            root.addChild(newStroke.root)
            
            var count = 0
            for point in stroke.points {
                if count % 5 == 0 {
                    let entity = eraserEntity.clone(recursive: true)
                    entity.name = "clear"
                    var invisibleMaterial = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1.0))
                    invisibleMaterial.opacityThreshold = 1.0
                    entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [invisibleMaterial]))
                    entity.components.set(StrokeRootComponent(stroke.uuid))
                    entity.setScale([0.0025, 0.0025, 0.0025], relativeTo: nil)
                    entity.position = point
                    root.addChild(entity)
                }
                count += 1
            }
        }
        
        // root から tmpStrokes のエンティティを削除
        boundingBoxEntity.children.removeAll()
        tmpStrokes.removeAll()
        boundingBoxEntity.removeFromParent()
        boundingBoxEntity.transform.matrix = .identity
    }
    
    /// 一時的なストロークをクリアする（追加処理の停止）
    func clearTmpStrokes() {
        boundingBoxEntity.children.removeAll()
        tmpStrokes.removeAll()
        boundingBoxEntity.removeFromParent()
        boundingBoxEntity.transform.matrix = .identity
    }
    
    struct BoundingBoxCube {
        /// 頂点の位置を示す列挙型
        enum Corner: Int, CaseIterable {
            case minXMinYMinZ = 0
            case maxXMinYMinZ = 1
            case minXMaxYMinZ = 2
            case maxXMaxYMinZ = 3
            case minXMinYMaxZ = 4
            case maxXMinYMaxZ = 5
            case minXMaxYMaxZ = 6
            case maxXMaxYMaxZ = 7
        }
        
        let corners: [Corner:SIMD3<Float>]  // 8頂点
        
        /// イニシャライザ（指定なし時は原点に8頂点）
        init() {
            self.corners = Dictionary(uniqueKeysWithValues: Corner.allCases.map { ($0, SIMD3<Float>(0, 0, 0)) })
        }
        
        /// イニシャライザ（全頂点指定）
        init(corners: [Corner: SIMD3<Float>]) {
            self.corners = corners
        }
        
        var center: SIMD3<Float> {
            let sum = corners.values.reduce(SIMD3<Float>.zero, +)
            return sum / Float(corners.count)
        }
        
        // 6個の面
        var surface: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
            let surfaceIndices: [(Corner, Corner, Corner, Corner)] = [
                (.minXMinYMinZ, .maxXMinYMinZ, .maxXMaxYMinZ, .minXMaxYMinZ), // 底面
                (.minXMinYMaxZ, .maxXMinYMaxZ, .maxXMaxYMaxZ, .minXMaxYMaxZ), // 上面
                (.minXMinYMinZ, .minXMinYMaxZ, .minXMaxYMaxZ, .minXMaxYMinZ), // 左面
                (.maxXMinYMinZ, .maxXMinYMaxZ, .maxXMaxYMaxZ, .maxXMaxYMinZ), // 右面
                (.minXMinYMinZ, .minXMaxYMinZ, .maxXMaxYMinZ, .maxXMinYMinZ), // 前面
                (.minXMinYMaxZ, .minXMaxYMaxZ, .maxXMaxYMaxZ, .maxXMinYMaxZ)  // 後面
            ]
            return surfaceIndices.map { (corners[$0.0]!, corners[$0.1]!, corners[$0.2]!, corners[$0.3]!) }
        }
    }
    
    /// [Stroke] 全体で最も端の位置を取得する
    ///  - Returns: 最も端の位置（直方体の8頂点）
    private func generateBoundingBox() {
        guard !self.tmpStrokes.isEmpty else { return }
        
        var minX: Float = .greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude
        
        for stroke in self.tmpStrokes {
            for point in stroke.points {
                minX = Swift.min(minX, point.x)
                minY = Swift.min(minY, point.y)
                minZ = Swift.min(minZ, point.z)
                maxX = Swift.max(maxX, point.x)
                maxY = Swift.max(maxY, point.y)
                maxZ = Swift.max(maxZ, point.z)
            }
        }
        
        tmpBoundingBox = BoundingBoxCube(corners: [
            .minXMinYMinZ: SIMD3<Float>(minX, minY, minZ),
            .maxXMinYMinZ: SIMD3<Float>(maxX, minY, minZ),
            .minXMaxYMinZ: SIMD3<Float>(minX, maxY, minZ),
            .maxXMaxYMinZ: SIMD3<Float>(maxX, maxY, minZ),
            .minXMinYMaxZ: SIMD3<Float>(minX, minY, maxZ),
            .maxXMinYMaxZ: SIMD3<Float>(maxX, minY, maxZ),
            .minXMaxYMaxZ: SIMD3<Float>(minX, maxY, maxZ),
            .maxXMaxYMaxZ: SIMD3<Float>(maxX, maxY, maxZ)
        ])
    }
}
