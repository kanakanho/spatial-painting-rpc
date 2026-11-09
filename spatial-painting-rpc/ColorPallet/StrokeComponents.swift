//
//  StrokeComponents.swift
//  spatial-painting-rpc
//

import Foundation
import RealityKit
import simd
import UIKit

/// ストロークの本体
///
/// - Note: データの実体は `StrokeGeometry` にあり、この Component は参照のみを持つ
struct StrokeComponent: Component {
    let id: UUID
    let geometry: StrokeGeometry
}

/// ストロークの見た目
struct StrokeStyleComponent: Component {
    var color: UIColor
    /// The maximum radius of the stroke.
    var maxRadius: Float
    /// ベジェ編集中など、線の内側を見せるために表面をカリングするかどうか
    var isFaceCullingEnabled: Bool = false
}

extension StrokeStyleComponent {
    /// 現在の色とカリング設定を反映したマテリアルを生成する
    func makeMaterial() -> SimpleMaterial {
        var material = SimpleMaterial(color: color, roughness: 1.0, isMetallic: false)
        if isFaceCullingEnabled {
            material.faceCulling = .front
        }
        return material
    }
}

/// メッシュを持つ子 Entity の目印
struct StrokeMeshComponent: Component {}

/// メッシュの再生成待ち
struct StrokeMeshDirty: Component {}

/// 消しゴム用コライダーの再生成待ち
struct StrokeColliderDirty: Component {}

/// ストロークを消しゴムで選択するためのコライダー
struct StrokeColliderComponent: Component {
    let strokeId: UUID
}

/// ベジェの制御点の Entity 群の親
struct BezierPointComponent: Component {
    let pointId: UUID
}

/// 制御点のハンドル同士を結ぶ線
struct BezierControlLineComponent: Component {}

/// ストロークの生成に使うプロトタイプ
///
/// - Note: System には依存を渡せないので、Canvas の root に持たせる
struct StrokeAssetsComponent: Component {
    var eraser: Entity
    var bezierEndPoint: Entity
    var bezierHandle: Entity
}

/// 描画するユーザー
struct PainterComponent: Component {
    let userId: UUID
}

/// ユーザーの筆の設定
struct BrushComponent: Component {
    var color: UIColor = .white
    /// The maximum radius of the stroke.
    var maxRadius: Float = 1E-2
}

/// ユーザーが描画中のストローク
struct DraftStrokeComponent: Component {
    /// 次の点の扱い
    enum Step {
        /// 最初の点
        case ignored
        /// 手の位置が飛んだ
        case jumped
        /// ストロークに追加する
        case accepted
    }
    
    var strokeEntity: Entity?
    var lastPosition: SIMD3<Float> = .zero
    var hasReceivedFirstPoint: Bool = false
    
    /// 次の点を受け取り、状態を更新して扱いを返す
    ///
    /// - Note: 飛びを検出すると `strokeEntity` を手放す。ストローク自体は削除しない
    /// - Parameters:
    ///   - position: 次の点の座標
    ///   - jumpThreshold: 飛びとみなす距離（m）
    mutating func step(to position: SIMD3<Float>, jumpThreshold: Float) -> Step {
        if !hasReceivedFirstPoint {
            hasReceivedFirstPoint = true
            return .ignored
        }
        
        /// lastPosition との距離が一定以上離れている場合は飛びとみなす
        let distance: Float = length(position - lastPosition)
        lastPosition = position
        if distance > jumpThreshold {
            strokeEntity = nil
            return .jumped
        }
        return .accepted
    }
}

/// 位置や大きさをまとめて操作する一時ストロークのグループ
struct StrokeGroupComponent: Component {
    /// 編集モードで選択した元のストローク。ファイルから読み込んだ場合は空
    ///
    /// - Note: 元のストロークが削除されても、データを再利用するために保持する
    var sources: [Entity] = []
}

/// 選択中の制御点（Canvas の root に持たせる）
struct ControlPointSelectionComponent: Component {
    var entity: Entity?
    /// 操作の基準になる位置
    var basePosition: SIMD3<Float> = .zero
}

/// 選択中の制御点の目印
struct SelectedControlPointComponent: Component {}

/// 制御点の見た目の更新待ち
struct ControlPointAppearanceDirty: Component {}

/// ペイントで使う Component と System の登録
@MainActor
enum PaintingECS {
    static func register() {
        StrokeComponent.registerComponent()
        StrokeStyleComponent.registerComponent()
        StrokeMeshComponent.registerComponent()
        StrokeMeshDirty.registerComponent()
        StrokeColliderDirty.registerComponent()
        StrokeColliderComponent.registerComponent()
        BezierPointComponent.registerComponent()
        BezierControlLineComponent.registerComponent()
        StrokeAssetsComponent.registerComponent()
        StrokeGroupComponent.registerComponent()
        ControlPointSelectionComponent.registerComponent()
        SelectedControlPointComponent.registerComponent()
        ControlPointAppearanceDirty.registerComponent()
        PainterComponent.registerComponent()
        BrushComponent.registerComponent()
        DraftStrokeComponent.registerComponent()
        StrokeMeshSystem.registerSystem()
        StrokeColliderSystem.registerSystem()
        ControlPointHighlightSystem.registerSystem()
    }
}
