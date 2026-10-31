//
//  StrokeComponents.swift
//  spatial-painting-rpc
//

import Foundation
import RealityKit
import UIKit

/// ストロークの見た目
struct StrokeStyleComponent: Component {
    var color: UIColor
    /// The maximum radius of the stroke.
    var maxRadius: Float
    /// ベジェ編集中など、線の内側を見せるために表面をカリングするかどうか
    var isFaceCullingEnabled: Bool = false
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

/// ペイントで使う Component と System の登録
@MainActor
enum PaintingECS {
    static func register() {
        StrokeStyleComponent.registerComponent()
        StrokeMeshComponent.registerComponent()
        StrokeMeshDirty.registerComponent()
        StrokeColliderDirty.registerComponent()
        StrokeColliderComponent.registerComponent()
        BezierPointComponent.registerComponent()
        BezierControlLineComponent.registerComponent()
        StrokeAssetsComponent.registerComponent()
    }
}
