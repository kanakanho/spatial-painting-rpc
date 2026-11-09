//
//  StrokeGeometry.swift
//  spatial-painting-rpc
//

import simd

/// ストロークの形状データ
///
/// - Note: 点列を Component の値で持つと、変更のたびに配列全体がコピーされる。
///   Component には参照のみを持たせ、データはこのクラスの中でその場で更新する。
///   `points` は描画中は入力、ベジェ化後は `bezierPoints` からの派生データとして扱う。
@MainActor
final class StrokeGeometry {
    /// `resamplePoints` で 1 セグメントあたりに生成する点の数
    static let resolution: Int = 16

    /// The collection of points in 3D space that represent the stroke.
    var points: [SIMD3<Float>]
    var bezierPoints: [BezierPointData]

    init(points: [SIMD3<Float>] = [], bezierPoints: [BezierPointData] = []) {
        self.points = points
        self.bezierPoints = bezierPoints
    }

    /// ベジェから `points` を再サンプリングする
    ///
    /// - Note: ベジェのセグメントがない場合は `points` を変更しない
    func resamplePoints() {
        let beziers: [[SIMD3<Float>]] = bezierPoints.beziers
        guard !beziers.isEmpty else { return }

        points = beziers2Points(beziers: beziers, resolution: Self.resolution)

        /// 最後の点を追加
        if let last: SIMD3<Float> = points.last {
            points.append(last)
        }
    }
}
