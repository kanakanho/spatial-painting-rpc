//
//  BezierStrokeData.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2026/09/18.
//

import Foundation
import simd

/// 通信・ファイル保存用のベジェの制御点
///
/// - Note: `BezierStroke.BezierPoint` は RealityKit の Entity を持つため MainActor でしか扱えない。
///   RPC のエンコード・デコードをメインスレッド外で行えるように、値だけを持つこの型で送受信する。
///   JSON のキーは `BezierStroke.BezierPoint` の旧 Codable 実装と同じ。
struct BezierPointData: Codable, Sendable {
    let uuid: UUID
    let strokeId: UUID
    var end: SIMD3<Float>?
    var startControl: SIMD3<Float>?
    var endControl: SIMD3<Float>?

    /// 全ての点にアフィン変換を適用する
    func applying(_ affine: simd_float4x4) -> BezierPointData {
        var data = self
        data.end = end.map { matmul4x4_3x1(affine, $0) }
        data.startControl = startControl.map { matmul4x4_3x1(affine, $0) }
        data.endControl = endControl.map { matmul4x4_3x1(affine, $0) }
        return data
    }
}

/// 通信・ファイル保存用のベジェのストローク
///
/// - Note: JSON のキーと色の表現は `BezierStroke` の旧 Codable 実装と同じ。
struct BezierStrokeData: Codable, Sendable {
    /// 色の成分（値の範囲は 0...1）
    enum ColorComponents: Sendable {
        /// Hue, Saturation, Brightness, Alpha
        case hsba(SIMD4<Float>)
        /// Red, Green, Blue, Alpha（maxRadius を持たない古いデータ）
        case rgba(SIMD4<Float>)
    }

    let uuid: UUID
    var points: [SIMD3<Float>]
    var color: ColorComponents
    var maxRadius: Float
    var bezierPoints: [BezierPointData]

    init(uuid: UUID, points: [SIMD3<Float>], color: ColorComponents, maxRadius: Float, bezierPoints: [BezierPointData]) {
        self.uuid = uuid
        self.points = points
        self.color = color
        self.maxRadius = maxRadius
        self.bezierPoints = bezierPoints
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case points
        case activeColor
        case maxRadius
        case bezierPoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pointArrays = try container.decode([[Float]].self, forKey: .points)
        self.points = pointArrays.map { SIMD3<Float>($0) }

        let colorArray = try container.decode([Float].self, forKey: .activeColor)
        guard colorArray.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: .activeColor, in: container, debugDescription: "Color array must have 4 elements")
        }
        // maxRadius があれば HSBA、なければ RGBA
        if container.contains(.maxRadius) {
            self.color = .hsba(SIMD4<Float>(colorArray))
        } else {
            self.color = .rgba(SIMD4<Float>(colorArray))
        }

        self.maxRadius = try container.decodeIfPresent(Float.self, forKey: .maxRadius) ?? 1E-2
        self.bezierPoints = try container.decodeIfPresent([BezierPointData].self, forKey: .bezierPoints) ?? []
        self.uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid) ?? UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(points.map { [$0.x, $0.y, $0.z] }, forKey: .points)
        // maxRadius を必ず書くので、色は HSBA で書く
        let hsba: SIMD4<Float>
        switch color {
        case .hsba(let value):
            hsba = value
        case .rgba(let value):
            hsba = Self.rgbaToHSBA(value)
        }
        try container.encode([hsba.x, hsba.y, hsba.z, hsba.w], forKey: .activeColor)
        try container.encode(maxRadius, forKey: .maxRadius)
        try container.encode(bezierPoints, forKey: .bezierPoints)
    }

    private static func rgbaToHSBA(_ rgba: SIMD4<Float>) -> SIMD4<Float> {
        let r = rgba.x, g = rgba.y, b = rgba.z
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue: Float = 0
        if delta > 0 {
            if maxValue == r {
                hue = (g - b) / delta
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation: Float = maxValue > 0 ? delta / maxValue : 0
        return SIMD4<Float>(hue, saturation, maxValue, rgba.w)
    }
}
