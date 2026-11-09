/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 A class that creates a volume so that a person can create meshes with the location of the drag gesture.
 */

import SwiftUI
import RealityKit

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
    /// 位置や大きさをまとめて操作する一時ストローク
    ///
    /// - Note: データの実体はグループの子の Entity にある
    var tmpStrokes: [BezierStroke] {
        boundingBoxEntity.children.compactMap { (entity: Entity) -> BezierStroke? in
            return BezierStroke(entity: entity)
        }
    }
    
    // added by nagao 2025/7/10
    let boundingBoxEntity: ModelEntity
    
    /// Whether it is in control mode.
    var isControlMode: Bool = false
    
    /// The distance for the box that extends in the positive direction.
    let big: Float = 1E2
    
    /// The distance for the box that extends in the negative direction.
    let small: Float = 1E-2
    
    // Sets up the painting canvas with six collision boxes that stack on each other.
    init() {
        let color = UIColor(red: 192/255, green: 192/255, blue: 192/255, alpha: 0.5)
        boundingBoxEntity = ModelEntity(
            mesh: .generateBox(size: 0.1, cornerRadius: 0.0),
            materials: [SimpleMaterial(color: color, isMetallic: true)],
            collisionShape: .generateBox(size: SIMD3<Float>(repeating: 0.1)),
            mass: 0.0)
        boundingBoxEntity.name = "boundingBox"
        boundingBoxEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        boundingBoxEntity.components.set(StrokeGroupComponent())
        
        root.components.set(ControlPointSelectionComponent())
        root.components.set(StrokeAssetsComponent(eraser: Entity(), bezierEndPoint: Entity(), bezierHandle: Entity()))
        addCanvasBoxes()
        root.addChild(tmpRoot)
        root.addChild(paintersRoot)
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
        painter.components.set(DraftStrokeComponent())
        paintersRoot.addChild(painter)
        return painter
    }
    
    /// ユーザーが描画中のストローク
    private func draftStroke(userId: UUID) -> BezierStroke? {
        guard let entity: Entity = painter(userId: userId)?.components[DraftStrokeComponent.self]?.strokeEntity else {
            return nil
        }
        return BezierStroke(entity: entity)
    }
    
    /// ユーザーがストロークを描画中かどうか
    func hasDraftStroke(userId: UUID) -> Bool {
        draftStroke(userId: userId) != nil
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
    /// 選択中の制御点
    var selectedControlPoint: Entity? {
        root.components[ControlPointSelectionComponent.self]?.entity
    }
    
    /// 選択中の制御点の操作の基準になる位置
    var selectedControlPointBasePosition: SIMD3<Float> {
        root.components[ControlPointSelectionComponent.self]?.basePosition ?? .zero
    }
    
    /// 制御点を選択する
    ///
    /// - Returns: 選択済みの Entity なら false
    func selectControlPoint(_ entity: Entity) -> Bool {
        if selectedControlPoint === entity {
            return false
        }
        deselectControlPoint()
        entity.components.set(SelectedControlPointComponent())
        entity.components.set(ControlPointAppearanceDirty())
        root.components.set(ControlPointSelectionComponent(entity: entity, basePosition: entity.position(relativeTo: nil)))
        return true
    }
    
    func clearControlPointSelection() {
        deselectControlPoint()
        root.components.set(ControlPointSelectionComponent())
    }
    
    /// 選択中の制御点の目印を外す
    private func deselectControlPoint() {
        guard let entity: Entity = selectedControlPoint else { return }
        entity.components.remove(SelectedControlPointComponent.self)
        entity.components.set(ControlPointAppearanceDirty())
    }
    
    /// 制御点の現在の位置を操作の基準にする
    func updateControlPointBasePosition() {
        guard let entity: Entity = selectedControlPoint else { return }
        root.components[ControlPointSelectionComponent.self]?.basePosition = entity.position(relativeTo: nil)
    }

    /// 連続する点の間がこの距離（m）より離れたら、手の位置が飛んだとみなして別のストロークにする
    static let strokeJumpThreshold: Float = 0.1
    
    /// 描画中のストロークがあり、次の点が前の点から飛んでいるかどうか
    ///
    /// - Note: true の場合は `addPoint` の前にストロークを確定すること。確定しないと `addPoint` が描画中のストロークを捨ててしまう
    func isStrokeJump(userId: UUID, to position: SIMD3<Float>) -> Bool {
        guard let draft: DraftStrokeComponent = painter(userId: userId)?.components[DraftStrokeComponent.self],
              draft.strokeEntity != nil else {
            return false
        }
        return length(position - draft.lastPosition) > Self.strokeJumpThreshold
    }
    
    /// Generate a point when the individual uses the drag gesture.
    func addPoint(_ strokeId: UUID, _ position: SIMD3<Float>, userId: UUID) {
        let painter: Entity = ensurePainter(userId: userId)
        var draft: DraftStrokeComponent = painter.components[DraftStrokeComponent.self] ?? DraftStrokeComponent()
        
        guard draft.step(to: position, jumpThreshold: Self.strokeJumpThreshold) == .accepted else {
            painter.components.set(draft)
            return
        }
        
        /// The maximum distance between two points before requiring a new point.
        let threshold: Float = 1E-9
        
        // Start a new stroke if no stroke exists.
        let stroke: BezierStroke
        if let entity: Entity = draft.strokeEntity, let currentStroke: BezierStroke = BezierStroke(entity: entity) {
            stroke = currentStroke
        } else {
            stroke = BezierStroke(uuid: strokeId)
            if let brush: BrushComponent = painter.components[BrushComponent.self] {
                stroke.setActiveColor(color: brush.color)
                stroke.setMaxRadius(radius: brush.maxRadius)
            }
            
            // Add the stroke to the root.
            root.addChild(stroke.root)
            draft.strokeEntity = stroke.root
        }
        painter.components.set(draft)
        
        // Check whether the length between the current hand position and the previous point meets the threshold.
        if let previousPoint: SIMD3<Float> = stroke.geometry.points.last, length(position - previousPoint) < threshold {
            return
        }
        
        // Add the current position to the stroke.
        // `points` は computed property で配列全体がコピーされるので、`geometry` に直接追記する
        stroke.geometry.points.append(position)
        
        // Update the current stroke mesh.
        stroke.updateMesh()
    }
    
    func addBezierStrokePoints(userId: UUID, bezierPoints: [BezierPointData]) {
        guard let stroke: BezierStroke = draftStroke(userId: userId) else {
            return
        }
        
        stroke.bezierPoints = bezierPoints
        attachControlPoints(to: stroke)
    }
    
    func individualPoints2Bezier(userId: UUID) -> BezierStroke? {
        guard let stroke: BezierStroke = draftStroke(userId: userId) else {
            return nil
        }
        
        stroke.bezierPoints = points2BezierData(strokeId: stroke.uuid, points: stroke.points)
        
        return stroke
    }
    
    /// 制御点の Entity 群を非表示で生成してストロークに付ける
    private func attachControlPoints(to stroke: BezierStroke) {
        guard let assets: StrokeAssetsComponent = root.components[StrokeAssetsComponent.self] else { return }
        stroke.rebuildControlPoints(endPoint: assets.bezierEndPoint, handle: assets.bezierHandle)
    }
    
    /// Clear the stroke when the drag gesture ends.
    func finishStroke(_ uuid: UUID) {
        guard let stroke: BezierStroke = draftStroke(userId: uuid) else {
            return
        }
        
        // Trigger the update mesh operation.
        if stroke.points.count < 8 { // 4->8 by nagao 2025/12/31
            stroke.root.removeFromParent()
        } else {
            stroke.updateMesh()
//            gridPoints.addPoints(from: stroke.bezierPoints)
            attachControlPoints(to: stroke)
            
            stroke.updateColliders()
        }
        
        // Clear the current stroke.
        painter(userId: uuid)?.components[DraftStrokeComponent.self]?.strokeEntity = nil
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
        let newStrokes: [BezierStroke] = tmpStrokes + strokes.map { (stroke: BezierStroke) -> BezierStroke in
            return makeTmpStroke(from: stroke)
        }
        
        // 頂点同士を繋ぐ線のエンティティを生成
        let tmpPoints: [SIMD3<Float>] = newStrokes.flatMap { (stroke: BezierStroke) -> [SIMD3<Float>] in
            return stroke.points
        }
        guard let boundingBox: BoundingBoxCube = BoundingBoxCube(enclosing: tmpPoints) else { return }
        
        generateInputTargetEntity(boundingBox: boundingBox)
        
        for stroke in newStrokes {
            stroke.points = stroke.points.map { (position: SIMD3<Float>) in
                // entityのローカル座標に変換する
                return stroke.root.convert(position: position, from: nil)
            }
            stroke.bezierPoints = points2BezierData(strokeId: stroke.uuid, points: stroke.points)
            stroke.root.setPosition(stroke.root.position - boundingBox.center, relativeTo: nil)
            boundingBoxEntity.addChild(stroke.root)
        }
        tmpRoot.addChild(boundingBoxEntity)
    }
    
    // modified by nagao 2015/7/10
    private func generateInputTargetEntity(boundingBox: BoundingBoxCube) {
        let size: SIMD3<Float> = boundingBox.corners[.maxXMaxYMaxZ]! - boundingBox.corners[.minXMinYMinZ]!
        let shapes = ShapeResource.generateBox(width: size.x, height: size.y, depth: size.z)
        let mesh = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z)
        let color = UIColor(red: 192/255, green: 192/255, blue: 192/255, alpha: 0.5)
        let material = SimpleMaterial(color: color, isMetallic: true)
        
        boundingBoxEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        boundingBoxEntity.components.set(CollisionComponent(shapes: [shapes], isStatic: true))
        boundingBoxEntity.setPosition(boundingBox.center, relativeTo: nil)
    }
    
    /// 一時的な Stroke を生成する
    private func makeTmpStroke(from stroke: BezierStroke) -> BezierStroke {
        let newStroke = BezierStroke(uuid: stroke.uuid, originalMaxRadius: stroke.originalMaxRadius)
        newStroke.maxRadius = stroke.maxRadius
        newStroke.setActiveColor(color: stroke.activeColor)
        newStroke.points = stroke.points
        newStroke.bezierPoints = points2BezierData(strokeId: stroke.uuid, points: stroke.points)
        newStroke.updateMesh()
        return newStroke
    }
    
    /// 追加処理の完了 modified by nagao 2015/7/10
    ///
    /// - Returns: 確定した新しいストローク
    @discardableResult
    func confirmTmpStrokes() -> [BezierStroke] {
        var newStrokes: [BezierStroke] = []
        for stroke in tmpStrokes {
            let rootMatrix: simd_float4x4 = stroke.root.transformMatrix(relativeTo: nil)
            let worldPoints: [SIMD3<Float>] = stroke.points.map { (position: SIMD3<Float>) in
                return SIMD3<Float>(rootMatrix * SIMD4<Float>(position, 1.0))
            }
            let uuid: UUID = UUID() // added by nagao 2025/11/21
            let newStroke = BezierStroke(uuid: uuid, originalMaxRadius: stroke.originalMaxRadius)
            newStroke.maxRadius = stroke.maxRadius
            newStroke.setActiveColor(color: stroke.activeColor)
            newStroke.points = worldPoints
            newStroke.bezierPoints = points2BezierData(strokeId: uuid, points: worldPoints)
            newStroke.updateMesh()
            attachControlPoints(to: newStroke)
            
            root.addChild(newStroke.root)
            
            newStroke.updateColliders()
            newStrokes.append(newStroke)
        }
        return newStrokes
    }
    
    /// 一時的なストロークをクリアする（追加処理の停止）
    func clearTmpStrokes() {
        boundingBoxEntity.children.removeAll()
        boundingBoxEntity.removeFromParent()
        boundingBoxEntity.transform.matrix = .identity
    }
    
    /// 編集モードで選択した元のストローク
    private var movingStrokes: [BezierStroke] {
        let sources: [Entity] = boundingBoxEntity.components[StrokeGroupComponent.self]?.sources ?? []
        return sources.compactMap { (entity: Entity) -> BezierStroke? in
            return BezierStroke(entity: entity)
        }
    }
    
    // added by nagao 2025/11/21
    /// ストロークを選択に加えて、選択中の全てのストロークを一時ストロークにする
    func addMovingStroke(_ stroke: BezierStroke) {
        clearTmpStrokes()
        boundingBoxEntity.components[StrokeGroupComponent.self]?.sources.append(stroke.root)
        // tmpStrokeに追加
        addTmpStrokes(movingStrokes)
    }
    func confirmMovingStrokes() -> [BezierStroke] {
        if movingStrokes.isEmpty { return [] }
        let confirmedStrokes: [BezierStroke] = confirmTmpStrokes()
        boundingBoxEntity.components[StrokeGroupComponent.self]?.sources.removeAll()
        return confirmedStrokes
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
        
        /// 全ての点を囲む直方体を生成する
        ///
        /// - Returns: 点がなければ nil
        init?(enclosing points: [SIMD3<Float>]) {
            guard let first: SIMD3<Float> = points.first else { return nil }
            
            var minimum: SIMD3<Float> = first
            var maximum: SIMD3<Float> = first
            for point: SIMD3<Float> in points {
                minimum = pointwiseMin(minimum, point)
                maximum = pointwiseMax(maximum, point)
            }
            
            self.corners = [
                .minXMinYMinZ: SIMD3<Float>(minimum.x, minimum.y, minimum.z),
                .maxXMinYMinZ: SIMD3<Float>(maximum.x, minimum.y, minimum.z),
                .minXMaxYMinZ: SIMD3<Float>(minimum.x, maximum.y, minimum.z),
                .maxXMaxYMinZ: SIMD3<Float>(maximum.x, maximum.y, minimum.z),
                .minXMinYMaxZ: SIMD3<Float>(minimum.x, minimum.y, maximum.z),
                .maxXMinYMaxZ: SIMD3<Float>(maximum.x, minimum.y, maximum.z),
                .minXMaxYMaxZ: SIMD3<Float>(minimum.x, maximum.y, maximum.z),
                .maxXMaxYMaxZ: SIMD3<Float>(maximum.x, maximum.y, maximum.z)
            ]
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
}
