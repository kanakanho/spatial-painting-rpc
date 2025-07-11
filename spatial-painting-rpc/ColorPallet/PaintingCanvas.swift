/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 A class that creates a volume so that a person can create meshes with the location of the drag gesture.
 */

import SwiftUI
import RealityKit

/// A class that stores each stroke and generates a mesh, in real time, from a person's gesture movement.
class PaintingCanvas {
    /// The main root entity for the painting canvas.
    let root = Entity()
    var strokes: [Stroke] = []
    
    var eraserEntity: Entity = Entity()
    
    /// The stroke that a person creates.
    var currentStroke: Stroke?
    
    var activeColor = SimpleMaterial.Color.white
    
    /// The distance for the box that extends in the positive direction.
    let big: Float = 1E2
    
    /// The distance for the box that extends in the negative direction.
    let small: Float = 1E-2
    
    var currentPosition: SIMD3<Float> = .zero
    var isFirstStroke = true
    
    // Sets up the painting canvas with six collision boxes that stack on each other.
    init() {
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
    
    func setActiveColor(color: SimpleMaterial.Color) {
        activeColor = color
    }
    
    /// Set the eraser entity that will be used to erase strokes.
    func setEraserEntity(_ entity: Entity) {
        eraserEntity = entity
    }
    
    /// Generate a point when the user uses the drag gesture.
    func addPoint(_ uuid: UUID, _ position: SIMD3<Float>) {
        if isFirstStroke {
            isFirstStroke = false
            return
        }
        
        /// currentPosition との距離が一定以上離れている場合は早期リターンする
        let distance = length(position - currentPosition)
        currentPosition = position
        // print("distance: \(distance)")
        if distance > 0.1 {
            print("distance is too far, return")
            currentStroke = nil
            return
        }
        
        /// The maximum distance between two points before requiring a new point.
        let threshold: Float = 1E-9
        
        // Start a new stroke if no stroke exists.
        if currentStroke == nil {
            currentStroke = Stroke(uuid: uuid)
            currentStroke!.setActiveColor(color: activeColor)
            strokes.append(currentStroke!)
            
            // Add the stroke to the root.
            root.addChild(currentStroke!.entity)
        }
        
        // Check whether the length between the current hand position and the previous point meets the threshold.
        if let previousPoint = currentStroke?.points.last, length(position - previousPoint) < threshold {
            return
        }
        
        // Add the current position to the stroke.
        currentStroke?.points.append(position)
        
        // Update the current stroke mesh.
        currentStroke?.updateMesh()
    }
    
    
    /// Clear the stroke when the drag gesture ends.
    func finishStroke() {
        if let stroke = currentStroke {
            // Trigger the update mesh operation.
            stroke.updateMesh()
            
            var count = 0
            for point in stroke.points {
                if count % 5 == 0 {
                    let entity = eraserEntity.clone(recursive: true)
                    entity.name = "eraser"
                    let material = SimpleMaterial(color: UIColor(white: 1.0, alpha: 0.0), isMetallic: false)
                    entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
                    entity.components.set(StrokeComponent(stroke.uuid))
                    entity.setScale([0.0025, 0.0025, 0.0025], relativeTo: nil)
                    entity.position = point
                    //entity.position = .zero
                    //stroke.entity.addChild(entity)
                    root.addChild(entity)
                    // print("Added eraser entity at point: \(point)")
                }
                count += 1
            }
            
            // Clear the current stroke.
            currentStroke = nil
            isFirstStroke = true
        }
    }
    
    /// Strokeを直接追加する
    func addStrokes(_ strokes: [Stroke]) {
        for stroke in strokes {
            addStroke(stroke)
        }
    }
    
    /// Stroke構造体を利用して追加する
    func addStroke(_ stroke: Stroke) {
        let newStroke = Stroke(uuid: stroke.uuid)
        newStroke.setActiveColor(color: stroke.activeColor)
        newStroke.points = stroke.points
        newStroke.updateMesh()
        self.strokes.append(newStroke)
        root.addChild(newStroke.entity)
        
        var count = 0
        for point in stroke.points {
            if count % 5 == 0 {
                let entity = eraserEntity.clone(recursive: true)
                entity.name = "eraser"
                let material = SimpleMaterial(color: UIColor(white: 1.0, alpha: 0.0), isMetallic: false)
                entity.components.set(ModelComponent(mesh: .generateSphere(radius: 0.01), materials: [material]))
                entity.components.set(StrokeComponent(stroke.uuid))
                entity.setScale([0.0025, 0.0025, 0.0025], relativeTo: nil)
                entity.position = point
                root.addChild(entity)
            }
            count += 1
        }
    }
}

