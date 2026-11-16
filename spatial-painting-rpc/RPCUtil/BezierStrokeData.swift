//
//  BezierStrokeData.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2026/09/18.
//

import Foundation
import simd

/// ベジェの制御点の種類
enum BezierPointType: CaseIterable, Codable, Sendable {
    case end
    case startControl
    case endControl
}

/// 通信・ファイル保存用のベジェの制御点
///
/// - Note: JSON のキーは `BezierStroke.BezierPoint` の旧 Codable 実装と同じ。
struct BezierPointData: Codable, Sendable {
    let uuid: UUID
    let strokeId: UUID
    var end: SIMD3<Float>? = nil
    var startControl: SIMD3<Float>? = nil
    var endControl: SIMD3<Float>? = nil

    /// 点を指定した種類の位置に設定する
    ///
    /// - Note: `end` が未設定のときは `.end` のみ受け付ける。ハンドルの片方を動かすと反対側は `end` を中心に点対称に動き、
    ///   `end` を動かすと両方のハンドルが追従する
    /// - Parameters:
    ///   - point: 設定する点の座標
    ///   - pn: 設定する点の種類
    mutating func add(point: SIMD3<Float>, pn: BezierPointType) {
        guard let end = end else {
            if pn == .end {
                self.end = point
            }
            return
        }
        
        switch pn {
        case .endControl:
            endControl = point
            startControl = end + (end - point)
        case .startControl:
            startControl = point
            endControl = end + (end - point)
        case .end:
            let diff = end - point
            self.end = point
            
            if let startControl = startControl,
               let endControl = endControl {
                self.startControl = startControl - diff
                self.endControl = endControl - diff
            }
        }
    }

    /// 全ての点にアフィン変換を適用する
    func applying(_ affine: simd_float4x4) -> BezierPointData {
        var data = self
        data.end = end.map { matmul4x4_3x1(affine, $0) }
        data.startControl = startControl.map { matmul4x4_3x1(affine, $0) }
        data.endControl = endControl.map { matmul4x4_3x1(affine, $0) }
        return data
    }
}

extension [BezierPointData] {
    /// アフィン変換を適用した送信用のデータ
    func transferData(affine: simd_float4x4) -> [BezierPointData] {
        return self.map { $0.applying(affine) }
    }
    
    /// 連続する 2 つの制御点から作る 3 次ベジェのセグメント
    var beziers: [[SIMD3<Float>]] {
        var beziers: [[SIMD3<Float>]] = []
        
        if self.count < 2 { return beziers }
        
        // 2つの BezierPointData から それぞれ end,control を取得して、4つのリストにする
        for i in 0..<(self.count - 1) {
            let startPoint = self[i]
            let endPoint = self[i + 1]
            
            // P0: startPoint.end (始点アンカー)
            // P1: startPoint.endControl (始点から伸びるハンドル)
            // P2: endPoint.startControl (終点に向かうハンドル)
            // P3: endPoint.end (終点アンカー)
            let list: [SIMD3<Float>] = [
                startPoint.end,
                startPoint.endControl,
                endPoint.startControl,
                endPoint.end
            ].compactMap { $0 }
            
            // 4つの点が揃っている場合のみセグメントとして追加する
            if list.count == 4 {
                beziers.append(list)
            }
        }
        
        return beziers
    }
}

extension [[SIMD3<Float>]] {
    /// ベジェのセグメント [firstPoint, ctrl1, ctrl2, lastPoint] を制御点のデータに変換する
    func toBezierPointData(strokeId: UUID) -> [BezierPointData] {
        // 4点ない場合は消す
        if self.count < 3 {
            return []
        }
        
        guard let end = self.first?[0],
              let endControl = self.first?[1] else { return [] }
        
        var startPoint = BezierPointData(uuid: UUID(), strokeId: strokeId)
        startPoint.add(point: end, pn: .end)
        startPoint.add(point: endControl, pn: .endControl)
        
        var bezierPoints: [BezierPointData] = [startPoint]
        
        for points in self {
            var bezierPoint = BezierPointData(uuid: UUID(), strokeId: strokeId)
            bezierPoint.add(point: points[3], pn: .end)
            bezierPoint.add(point: points[2], pn: .startControl)
            
            bezierPoints.append(bezierPoint)
        }
        return bezierPoints
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
