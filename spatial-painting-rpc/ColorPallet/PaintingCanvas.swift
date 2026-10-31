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
}

/// A class that stores each stroke and generates a mesh, in real time, from a person's gesture movement.
@MainActor
@Observable
class PaintingCanvas {
    /// The main root entity for the painting canvas.
    let root = Entity()
    
//    var gridPoints: GridPoints = GridPoints()
    
    /// キャンバス上のストローク
    ///
    /// - Note: データの実体は Entity ツリーにあり、参照のたびに生成する。同一性は `uuid` で比較すること
    var strokes: [BezierStroke] {
        root.children.compactMap { (entity: Entity) -> BezierStroke? in
            return BezierStroke(entity: entity)
        }
    }
    let tmpRoot = Entity()
    /// ユーザーごとの Painter の親
    let paintersRoot: Entity = Entity()
    var tmpStrokes: [BezierStroke] = []
    var tmpBoundingBoxEntity: Entity = Entity()
    var tmpBoundingBox: BoundingBoxCube = BoundingBoxCube()
    
    // added by nagao 2025/11/21
    var movingStrokes: [BezierStroke] = []

    // added by nagao 2025/11/26
    var selectedBezierEntity: Entity = Entity()
    var isBezierSelected: Bool = false
    var selectedBezierPosition: SIMD3<Float> = .zero

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
        root.components.set(StrokeAssetsComponent(eraser: Entity(), bezierEndPoint: Entity(), bezierHandle: Entity()))
        addCanvasBoxes()
        root.addChild(tmpRoot)
        root.addChild(paintersRoot)
        
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
        addCanvasBoxes()
        root.addChild(tmpRoot)
        root.addChild(paintersRoot)
    }
    
    /// Add the six collision boxes that surround the painting canvas.
    private func addCanvasBoxes() {
        root.addChild(addBox(size: [big, big, small], position: [0, 0, -0.5 * big]))
        root.addChild(addBox(size: [big, big, small], position: [0, 0, +0.5 * big]))
        root.addChild(addBox(size: [big, small, big], position: [0, -0.5 * big, 0]))
        root.addChild(addBox(size: [big, small, big], position: [0, +0.5 * big, 0]))
        root.addChild(addBox(size: [small, big, big], position: [-0.5 * big, 0, 0]))
        root.addChild(addBox(size: [small, big, big], position: [+0.5 * big, 0, 0]))
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
    
    /// ユーザーの Painter を探す
    private func painter(userId: UUID) -> Entity? {
        paintersRoot.children.first { (entity: Entity) -> Bool in
            return entity.components[PainterComponent.self]?.userId == userId
        }
    }
    
    /// ユーザーの Painter を探し、なければ作成する
    private func ensurePainter(userId: UUID) -> Entity {
        if let painter: Entity = painter(userId: userId) {
            return painter
        }
        let painter = Entity()
        painter.components.set(PainterComponent(userId: userId))
        painter.components.set(BrushComponent())
        paintersRoot.addChild(painter)
        return painter
    }
    
    /// ユーザーの筆の色
    ///
    /// - Returns: Painter がなければ nil
    func activeColor(userId: UUID) -> UIColor? {
        painter(userId: userId)?.components[BrushComponent.self]?.color
    }
    
    func setActiveColor(userId: UUID ,color: SimpleMaterial.Color) {
        ensurePainter(userId: userId).components[BrushComponent.self]?.color = color
    }
    
    func setMaxRadius(userId: UUID,radius: Float) {
        ensurePainter(userId: userId).components[BrushComponent.self]?.maxRadius = radius
    }
    
    func setEntities(eraserEntity: Entity, bezierEndPointEntity: Entity, bezierHandleEntity: Entity) {
        root.components.set(StrokeAssetsComponent(eraser: eraserEntity, bezierEndPoint: bezierEndPointEntity, bezierHandle: bezierHandleEntity))
    }
    
    // added by nagao 2025/11/26
    func setSelectedBezierEntity(_ entity: Entity) {
        selectedBezierEntity = entity
        isBezierSelected = true
        selectedBezierPosition = entity.position(relativeTo: nil)
    }
    
    func setIsBezierSelected(_ isSelected: Bool) {
        isBezierSelected = isSelected
    }
    
    func setSelectedBezierPosition(_ position: SIMD3<Float>) {
        //if isBezierSelected == false { return }
        selectedBezierPosition = position
    }

    /// 連続する点の間がこの距離（m）より離れたら、手の位置が飛んだとみなして別のストロークにする
    static let strokeJumpThreshold: Float = 0.1
    
    /// 描画中のストロークがあり、次の点が前の点から飛んでいるかどうか
    ///
    /// - Note: true の場合は `addPoint` の前にストロークを確定すること。確定しないと `addPoint` が描画中のストロークを捨ててしまう
    func isStrokeJump(userId: UUID, to position: SIMD3<Float>) -> Bool {
        guard let individualStroke = individualStrokeDic[userId],
              individualStroke.currentStroke != nil else {
            return false
        }
        return length(position - individualStroke.currentPosition) > Self.strokeJumpThreshold
    }
    
    /// Generate a point when the individual uses the drag gesture.
    func addPoint(_ strokeId: UUID, _ position: SIMD3<Float>, userId: UUID) {
        let painter: Entity = ensurePainter(userId: userId)
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
        if distance > Self.strokeJumpThreshold {
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
            if let brush: BrushComponent = painter.components[BrushComponent.self] {
                individualStroke.currentStroke!.setActiveColor(color: brush.color)
                individualStroke.currentStroke!.setMaxRadius(radius: brush.maxRadius)
            }
            
            // Add the stroke to the root.
            root.addChild(individualStroke.currentStroke!.root)
        }
        
        // Check whether the length between the current hand position and the previous point meets the threshold.
        if let previousPoint = individualStroke.currentStroke?.points.last, length(position - previousPoint) < threshold {
            return
        }
        
        // Add the current position to the stroke.
        // `points` は computed property で配列全体がコピーされるので、`geometry` に直接追記する
        individualStroke.currentStroke?.geometry.points.append(position)
        
        // Update the current stroke mesh.
        individualStroke.currentStroke?.updateMesh()
        
        individualStrokeDic[userId] = individualStroke
    }
    
    func addBezierStrokePoints(userId: UUID, bezierPoints: [BezierPointData]) {
        guard let individualStroke: IndividualStroke = individualStrokeDic[userId],
              let stroke = individualStroke.currentStroke else {
            return
        }
        
        stroke.bezierPoints = bezierPoints
        attachControlPoints(to: stroke)
    }
    
    func individualPoints2Bezier(userId: UUID) -> BezierStroke? {
        guard var individualStroke: IndividualStroke = individualStrokeDic[userId],
              let stroke = individualStroke.currentStroke else {
            return nil
        }
        
        stroke.bezierPoints = points2BezierData(strokeId: stroke.uuid, points: stroke.points)
        individualStroke.currentStroke = stroke
        individualStrokeDic[userId] = individualStroke
        
        return stroke
    }
    
    /// 制御点の Entity 群を非表示で生成してストロークに付ける
    private func attachControlPoints(to stroke: BezierStroke) {
        guard let assets: StrokeAssetsComponent = root.components[StrokeAssetsComponent.self] else { return }
        stroke.rebuildControlPoints(endPoint: assets.bezierEndPoint, handle: assets.bezierHandle)
    }
    
    /// Clear the stroke when the drag gesture ends.
    func finishStroke(_ uuid: UUID) {
        guard var individualStroke: IndividualStroke = individualStrokeDic[uuid] else {
            return
        }
        
        if let stroke = individualStroke.currentStroke {
            // Trigger the update mesh operation.
            if stroke.points.count < 8 { // 4->8 by nagao 2025/12/31
                stroke.root.removeFromParent()
                individualStroke.currentStroke = nil
                individualStrokeDic[uuid] = individualStroke
                return
            }
            stroke.updateMesh()
//            gridPoints.addPoints(from: stroke.bezierPoints)
            attachControlPoints(to: stroke)
            
            stroke.updateColliders()
            
            // Clear the current stroke.
            individualStroke.currentStroke = nil
            
            individualStrokeDic[uuid] = individualStroke
        }
    }
    
    func removeStroke(strokeId: UUID) {
//        if let index = strokes.firstIndex(where: { $0.uuid == strokeId }) {
//            gridPoints.removePoints(from: strokes[index].bezierPoints)
//        }
//        
        
        DispatchQueue.main.async {
            let childrenToRemove = self.root.children.filter {
                $0.components[StrokeRootComponent.self]?.uuid == strokeId
            }
            for child in childrenToRemove {
                child.removeFromParent()
            }
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
    
    func setIsControlMode(_ isControlMode: Bool) {
        if self.isControlMode == isControlMode {
            return
        }
        self.isControlMode = isControlMode
        if isControlMode {
            startControlMode()
        } else {
            finishControlMode()
        }
    }

    func startControlMode() {
        for stroke in strokes {
            stroke.setControlPointsEnabled(true)
            stroke.setFaceCulling(true)
        }
    }
    
    func finishControlMode() {
        for stroke in strokes {
            stroke.setControlPointsEnabled(false)
            stroke.setFaceCulling(false)
        }
    }
    
    func moveControlPoint(strokeId: UUID, controlPointId: UUID, controlType: BezierPointType, newPosition: SIMD3<Float>) {
        for stroke in strokes {
            if stroke.uuid == strokeId {
                stroke.moveControlPoint(pointId: controlPointId, to: newPosition, pn: controlType)
                stroke.updateMesh()
            }
        }
    }
    
    func finishControlPoint(strokeId: UUID, controlPointId: UUID) {
        for stroke in strokes {
            if stroke.uuid == strokeId {
//                gridPoints.addPoints(from: stroke.bezierPoints)
                
                stroke.updateColliders()
            }
        }
    }
    
    func addBezierStrokes(_ strokes: [BezierStroke]) {
        for stroke in strokes {
            addBezierStroke(stroke)
        }
    }
    
    func addBezierStroke(_ stroke: BezierStroke) {
        let newStroke = BezierStroke(uuid: stroke.uuid)
        newStroke.maxRadius = stroke.maxRadius
        newStroke.setActiveColor(color: stroke.activeColor)
//        newStroke.points = stroke.points
        newStroke.bezierPoints = stroke.bezierPoints
        newStroke.updateMesh()
        attachControlPoints(to: newStroke)
//        gridPoints.addPoints(from: newStroke.bezierPoints)
        
        newStroke.updateColliders()
        
        root.addChild(newStroke.root)
    }
}

/// 直接 Stroke を追加するときに行う処理の拡張
extension PaintingCanvas {
    /// 一時的な Stroke をまとめて追加する modified by nagao 2015/7/10
    func addTmpStrokes(_ strokes: [BezierStroke]) {
        if strokes.isEmpty { return }
        //print("load tmp strokes")
        for stroke in strokes {
            addTmpStroke(stroke)
        }
        
        // 頂点同士を繋ぐ線のエンティティを生成
        generateBoundingBox()
        
        generateInputTargetEntity()
        
        for stroke in tmpStrokes {
            stroke.points = stroke.points.map { (position: SIMD3<Float>) in
                // entityのローカル座標に変換する
                return stroke.root.convert(position: position, from: nil)
            }
            stroke.bezierPoints = points2BezierData(strokeId: stroke.uuid, points: stroke.points)
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
        newStroke.bezierPoints = points2BezierData(strokeId: stroke.uuid, points: stroke.points)
        newStroke.updateMesh()
        self.tmpStrokes.append(newStroke)
    }
    
    /// 追加処理の完了 modified by nagao 2015/7/10
    func confirmTmpStrokes() {
        if tmpStrokes.isEmpty { return }
        var newStrokes: [BezierStroke] = []
        for stroke in tmpStrokes {
            stroke.points = stroke.points.map { (position: SIMD3<Float>) in
                return SIMD3<Float>(stroke.root.transformMatrix(relativeTo: nil) * SIMD4<Float>(position, 1.0))
            }
            let uuid: UUID = UUID() // added by nagao 2025/11/21
            let newStroke = BezierStroke(uuid: uuid, originalMaxRadius: stroke.originalMaxRadius)
            newStroke.maxRadius = stroke.maxRadius
            newStroke.setActiveColor(color: stroke.activeColor)
            newStroke.points = stroke.points
            newStroke.bezierPoints = points2BezierData(strokeId: uuid, points: stroke.points)
            newStroke.updateMesh()
            attachControlPoints(to: newStroke)
            
            root.addChild(newStroke.root)
            
            newStroke.updateColliders()
            newStrokes.append(newStroke)
        }
        
        // root から tmpStrokes のエンティティを削除
        //boundingBoxEntity.children.removeAll()
        tmpStrokes = newStrokes
        //boundingBoxEntity.removeFromParent()
        //boundingBoxEntity.transform.matrix = .identity
    }
    
    /// 一時的なストロークをクリアする（追加処理の停止）
    func clearTmpStrokes() {
        boundingBoxEntity.children.removeAll()
        tmpStrokes.removeAll()
        boundingBoxEntity.removeFromParent()
        boundingBoxEntity.transform.matrix = .identity
    }
    
    // added by nagao 2025/11/21
    func addMovingStrokes(_ stroke: BezierStroke) {
        movingStrokes.append(stroke)
    }
    func clearMovingStrokes() {
        movingStrokes.removeAll()
    }
    func confirmMovingStrokes() -> Bool {
        if movingStrokes.isEmpty { return false }
        confirmTmpStrokes()
        movingStrokes.removeAll()
        return true
    }
    func changeColorOfMovingStrokes(_ color: UIColor ) {
        if movingStrokes.isEmpty { return }
        //var points: [SIMD3<Float>] = []
        for stroke in tmpStrokes {
            stroke.setActiveColor(color: color)
            /*
            points.append(contentsOf: stroke.points)
            stroke.points = stroke.points.map { (position: SIMD3<Float>) in
                return SIMD3<Float>(stroke.root.transformMatrix(relativeTo: nil) * SIMD4<Float>(position, 1.0))
            }
            */
            stroke.updateMesh(false)
            //stroke.points = points
            //points.removeAll()
        }
    }
    func changeLineWidthOfMovingStrokes(_ lineWidth: Float ) {
        if movingStrokes.isEmpty { return }
        //var points: [SIMD3<Float>] = []
        for stroke in tmpStrokes {
            stroke.maxRadius = lineWidth
            /*
            points.append(contentsOf: stroke.points)
            stroke.points = stroke.points.map { (position: SIMD3<Float>) in
                return SIMD3<Float>(stroke.root.transformMatrix(relativeTo: nil) * SIMD4<Float>(position, 1.0))
            }
            */
            stroke.updateMesh(false)
            //stroke.points = points
            //points.removeAll()
        }
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
