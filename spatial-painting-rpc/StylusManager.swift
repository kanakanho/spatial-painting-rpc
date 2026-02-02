//
//  StylusManager.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2026/01/26.
//

import RealityKit
import CoreHaptics
import GameController

@Observable
@MainActor
final class StylusManager {
    var appModel: AppModel
    var rootEntity: Entity = Entity()
    var stylusAnchorEntity: AnchorEntity? = nil
    private var hapticEngines: [ObjectIdentifier: CHHapticEngine] = [:]
    private var hapticPlayers: [ObjectIdentifier: CHHapticPatternPlayer] = [:]
    
    init(appModel: AppModel) {
        self.appModel = appModel
    }

    // 現在のスタイラスを特定するためのキー
    private var currentStylusKey: ObjectIdentifier?

    func handleControllerSetup() async {
        // Existing connections
        let styluses = GCStylus.styli

        for stylus in styluses where stylus.productCategory == GCProductCategorySpatialStylus {
            try? await stylusAnchorEntity = setupAccessory(stylus: stylus)
        }

        // Connect
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.GCStylusDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let stylus = note.object as? GCStylus,
                  stylus.productCategory == GCProductCategorySpatialStylus else { return }

            Task { @MainActor in
                do {
                    let anchor = try await self.setupAccessory(stylus: stylus)
                    self.stylusAnchorEntity = anchor
                    self.currentStylusKey = ObjectIdentifier(stylus)

                    for finger in self.appModel.model.fingerEntities.values {
                        finger.removeFromParent()
                    }
                } catch {
                    // ignore / log
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.GCStylusDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let stylus = note.object as? GCStylus,
                  stylus.productCategory == GCProductCategorySpatialStylus else { return }

            Task { @MainActor in
                let key = ObjectIdentifier(stylus)
                guard key == self.currentStylusKey else { return }

                // 必要ならシーンからも外す
                //self.stylusAnchorEntity?.removeFromParent()

                // nil にする
                self.stylusAnchorEntity = nil
                self.currentStylusKey = nil

                for finger in self.appModel.model.fingerEntities.values {
                    self.appModel.model.contentEntity.addChild(finger)
                    self.appModel.model.recallColor(entity: finger)
                }
            }
        }
    }

    private func setupAccessory(stylus: GCStylus) async throws -> AnchorEntity? {
        let source = try await AnchoringComponent.AccessoryAnchoringSource(device: stylus)
        
        // List available locations (aim and origin appear to be possible)
        print("📍 Available locations: \(source.accessoryLocations)")

        guard let location = source.locationName(named: "aim") else { return nil }

        let anchor = AnchorEntity(
            .accessory(from: source, location: location),
            trackingMode: .predicted,
            physicsSimulation: .none
        )
        rootEntity.addChild(anchor)

        let key = ObjectIdentifier(stylus)
        currentStylusKey = key

        // Setup haptics if available
        setupHaptics(for: stylus, key: key)
        setupStylusInputs(stylus: stylus, anchor: anchor, key: key)
        addStylusTipIndicator(to: anchor)
        
        for finger in appModel.model.fingerEntities.values {
            finger.removeFromParent()
        }

        return anchor
    }

    private func setupHaptics(for stylus: GCStylus, key: ObjectIdentifier) {
        guard let deviceHaptics = stylus.haptics else { return }
        
        // Create haptic engine
        let engine = deviceHaptics.createEngine(withLocality: .default)
        do {
            try engine?.start()
            hapticEngines[key] = engine
            
            // Create a simple "tap" pattern for button presses
            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0.0)
            ], parameters: [])
            
            let player = try engine?.makePlayer(with: pattern)
            hapticPlayers[key] = player
        } catch {
            print("❌ Failed to setup haptics: \(error)")
        }
    }
    
    private func playHaptic(for key: ObjectIdentifier) {
        guard let player = hapticPlayers[key] else { return }
        
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("❌ Failed to play haptic: \(error)")
        }
    }

    private func addStylusTipIndicator(to anchor: AnchorEntity) {
        let tipEntity = appModel.model.stylusTipEntity
        appModel.model.recallColor(entity: tipEntity)
        anchor.addChild(tipEntity)
    }

    private func setupStylusInputs(stylus: GCStylus, anchor: AnchorEntity, key: ObjectIdentifier) {
        guard let input = stylus.input else {
            print("stylus is not connected")
            return
        }
        print("✏️[input] started: \(input)")
        
        input.inputStateQueueDepth = 1
        input.inputStateAvailableHandler = { input in
            while let nextState = input.nextInputState() {
                if let primary = input.buttons[.stylusPrimaryButton],
                   primary.pressedInput.isPressed {
                    print("✏️[PrimaryButton] pressed")
                    self.appModel.model.isStylusButtonPressed = true
                    if self.appModel.model.isEraserMode {
                        let entity = anchor.findEntity(named: "StylusTipIndicator")
                        self.appModel.model.recallColor(entity: entity!)
                        self.appModel.model.isEraserMode = false
                    } else {
                        self.appModel.model.isStylusButtonPressed = false
                        
                        // --- ストローク終了・ベジェ化の処理を追加 ---
                        guard self.appModel.model.authoringMode == .draw else { return }
                    }
                }
                if let secondary = input.buttons[.stylusSecondaryButton],
                   let value = secondary.forceInput?.value, value > 0 {
                    print("✏️[SecondaryButton] pressed")
                    let eraserMat = SimpleMaterial(
                        color: UIColor(red: 220/255, green: 220/255, blue: 220/255, alpha: 0.2),
                        isMetallic: true
                    )
                    let entity = anchor.findEntity(named: "StylusTipIndicator")
                    entity!.components.set(
                        ModelComponent(
                            mesh: .generateSphere(radius: 0.01),
                            materials: [eraserMat]
                        )
                    )
                    self.appModel.model.isEraserMode = true
                    self.appModel.model.colorPalletModel.selectedToolName = "eraser"
                    _ = self.appModel.model.recordTime(isBegan: true)
                }
            }
        }
    }

    private func spawnSphere(at anchor: AnchorEntity, color: UIColor, radius: Float) {
        let worldTransform = anchor.transformMatrix(relativeTo: nil)
        let worldPosition = SIMD3<Float>(worldTransform.columns.3.x,
                                          worldTransform.columns.3.y,
                                          worldTransform.columns.3.z)
        
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        sphere.position = worldPosition
        sphere.components.set(InputTargetComponent(allowedInputTypes: [.all]))
        sphere.components.set(CollisionComponent(shapes: [ShapeResource.generateSphere(radius: 0.01)], isStatic: true))

        rootEntity.addChild(sphere)
    }
}
