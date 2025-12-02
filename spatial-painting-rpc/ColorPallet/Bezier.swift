//
//  Beiser.swift
//  sample
//
//  Created by blueken on 2025/09/24.
//

import Foundation
import simd
import RealityKit

func beziers2Points(beziers: [[SIMD3<Float>]], resolution: Int = 16) -> [SIMD3<Float>] {
    var points: [SIMD3<Float>] = []
    
    // beziers配列が空、または解像度が低すぎる場合は、空の配列を返す
    guard !beziers.isEmpty, resolution > 1 else {
        return []
    }
    
    // enumerated() を使って、現在のセグメントが最後かどうかを判定する
    for (index, bezier) in beziers.enumerated() {
        let isLastSegment = index == beziers.count - 1
        
        // isLastSegmentがtrueの場合（最後のセグメント）、終点まで含める (resolution回ループ)
        // isLastSegmentがfalseの場合（途中のセグメント）、終点を含めない (resolution - 1回ループ)
        // これにより、セグメント間の点の重複を防ぐ
        let loopCount = isLastSegment ? resolution : resolution - 1
        
        for i in 0..<loopCount {
            // t は 0.0 から 1.0 の間の値
            let t = Float(i) / Float(resolution - 1)
            let point = cubicBezierPoint3D(
                p0: bezier[0],
                p1: bezier[1],
                p2: bezier[2],
                p3: bezier[3],
                t: t
            )
            points.append(point)
        }
    }
    
    return points
}

//func beziers2Points(beziers: [[SIMD3<Float>]], resolution: Int = 8) -> [SIMD3<Float>] {
//    var points: [SIMD3<Float>] = []
//    
//    for bezier in beziers {
//        for i in 0..<resolution {
//            let t: Float = Float(i) / Float(resolution - 1)
//            let point = cubicBezierPoint3D(
//                p0: bezier[0],
//                p1: bezier[1],
//                p2: bezier[2],
//                p3: bezier[3],
//                t: t
//            )
//            points.append(point)
//        }
//    }
//    
//    if let lastSegment = beziers.last {
//        points.append(lastSegment[3])
//    }
//    
//    guard points.count > 1 else {
//        return []
//    }
//    
//    return points
//}

func beziers2Points(beziers: [[SIMD3<Double>]]) -> [SIMD3<Double>] {
    var points: [SIMD3<Double>] = []
    let resolution = 8
    
    for bezier in beziers {
        for i in 0..<resolution {
            let t: Double = Double(i) / Double(resolution - 1)
            let point = cubicBezierPoint3D(
                p0: bezier[0],
                p1: bezier[1],
                p2: bezier[2],
                p3: bezier[3],
                t: t
            )
            points.append(point)
        }
    }
    
    if let lastSegment = beziers.last {
        points.append(lastSegment[2])
    }
    
    guard points.count > 1 else {
        return []
    }
    
    return points
}


func points2Beziers(strokeId: UUID, points: [SIMD3<Float>], bezierEndPoint: Entity, bezierHandle: Entity, max_error: Float = 0.00001) -> [BezierStroke.BezierPoint] {
    let fittedBeziers: [[SIMD3<Float>]] = BezierFitter.fitCurve(points: points, maxError: max_error)
    let bezierPoints: [BezierStroke.BezierPoint] = fittedBeziers.toBezierStrokeBezierPoint(strokeId: strokeId, bezierEndPoint: bezierEndPoint, bezierHandle: bezierHandle)
    return bezierPoints
}

// MARK: - ベジェ点評価

func cubicBezierPoint3D(p0: SIMD3<Double>, p1: SIMD3<Double>, p2: SIMD3<Double>, p3: SIMD3<Double>, t: Double) -> SIMD3<Double> {
    let u = 1 - t
    return u * u * u * p0
         + 3 * u * u * t * p1
         + 3 * u * t * t * p2
         + t * t * t * p3
}

func cubicBezierPoint3D(p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    let u = 1 - t
    return u * u * u * p0
         + 3 * u * u * t * p1
         + 3 * u * t * t * p2
         + t * t * t * p3
}

// 点の種類をenumで定義し、それぞれに必要な値を関連値として持たせる
enum BezierPoint {
    // 2次ベジェ曲線用の点（アンカーポイントのみ）
    case second(endpoint: SIMD3<Float>)
    
    // 3次ベジェ曲線用の点（アンカーポイントと制御点）
    case third(endpoint: SIMD3<Float>, inner: SIMD3<Float>)
    
    // どの種類の点でも共通してendpointにアクセスできるように算出プロパティを用意
    var endpoint: SIMD3<Float> {
        switch self {
        case .second(let endpoint):
            return endpoint
        case .third(let endpoint, _):
            return endpoint
        }
    }
    
    // innerはthirdの場合のみ意味を持つ
    // secondの場合はendpoint自身を返すことで、元のコードの挙動を再現
    var inner: SIMD3<Float> {
        switch self {
        case .second(let endpoint):
            return endpoint // 制御点が存在しないので、アンカーポイントを返す
        case .third(_, let inner):
            return inner
        }
    }
    
    var endpointBoundingBoxCube: BoundingBoxCube {
        var corners: [BoundingBoxCube.Corner:SIMD3<Float>] = [:]
        for corner in BoundingBoxCube.Corner.allCases {
            let offset = SIMD3<Float>(
                (corner.rawValue & 1) == 0 ? -0.1 : 0.1,
                (corner.rawValue & 2) == 0 ? -0.1 : 0.1,
                (corner.rawValue & 4) == 0 ? -0.1 : 0.1
            )
            corners[corner] = self.endpoint + offset
        }
        return BoundingBoxCube(corners: corners)
    }
    
    var innerBoundingBoxCube: BoundingBoxCube {
        var corners: [BoundingBoxCube.Corner:SIMD3<Float>] = [:]
        for corner in BoundingBoxCube.Corner.allCases {
            let offset = SIMD3<Float>(
                (corner.rawValue & 1) == 0 ? -0.1 : 0.1,
                (corner.rawValue & 2) == 0 ? -0.1 : 0.1,
                (corner.rawValue & 4) == 0 ? -0.1 : 0.1
            )
            corners[corner] = self.inner + offset
        }
        return BoundingBoxCube(corners: corners)
    }
    
    var endPointMesh: MeshResource {
        return MeshResource.generateBox(
            width: endpointBoundingBoxCube.corners[.maxXMaxYMaxZ]!.x - endpointBoundingBoxCube.corners[.minXMinYMinZ]!.x,
            height: endpointBoundingBoxCube.corners[.maxXMaxYMaxZ]!.y - endpointBoundingBoxCube.corners[.minXMinYMinZ]!.y,
            depth: endpointBoundingBoxCube.corners[.maxXMaxYMaxZ]!.z - endpointBoundingBoxCube.corners[.minXMinYMinZ]!.z
        )
    }
    
    var innerMesh: MeshResource {
        return MeshResource.generateBox(
            width: innerBoundingBoxCube.corners[.maxXMaxYMaxZ]!.x - innerBoundingBoxCube.corners[.minXMinYMinZ]!.x,
            height: innerBoundingBoxCube.corners[.maxXMaxYMaxZ]!.y - innerBoundingBoxCube.corners[.minXMinYMinZ]!.y,
            depth: innerBoundingBoxCube.corners[.maxXMaxYMaxZ]!.z - innerBoundingBoxCube.corners[.minXMinYMinZ]!.z
        )
    }
    
    var endPoint2InnerMesh: MeshResource {
        // endPoint と inner を結んだ線分のメッシュ
        let corners: [BoundingBoxCube.Corner:SIMD3<Float>] = [
            .minXMinYMinZ: self.endpoint + SIMD3<Float>(-0.05, -0.05, -0.05),
            .maxXMinYMinZ: self.endpoint + SIMD3<Float>( 0.05, -0.05, -0.05),
            .minXMaxYMinZ: self.endpoint + SIMD3<Float>(-0.05,  0.05, -0.05),
            .maxXMaxYMinZ: self.endpoint + SIMD3<Float>( 0.05,  0.05, -0.05),
            .minXMinYMaxZ: self.inner + SIMD3<Float>(-0.05, -0.05, -0.05),
            .maxXMinYMaxZ: self.inner + SIMD3<Float>( 0.05, -0.05, -0.05),
            .minXMaxYMaxZ: self.inner + SIMD3<Float>(-0.05,  0.05, -0.05),
            .maxXMaxYMaxZ: self.inner + SIMD3<Float>( 0.05,  0.05, -0.05)
        ]
        let boundingBox = BoundingBoxCube(corners: corners)
        do {
            return try MeshResource.generateBox(corner: boundingBox)
        } catch {
            return .generateBox(size: 0.1)
        }
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
}

/// ベジェ曲線の計算をまとめた構造体。
public struct Bezier {
    /// 3次ベジェ曲線をパラメータtで評価します。
    /// B(t) = (1-t)^3 P0 + 3(1-t)^2 t P1 + 3(1-t) t^2 P2 + t^3 P3
    /// - Parameters:
    ///   - controlPoints: 4つの制御点 [P0, P1, P2, P3]。
    ///   - t: パラメータ (通常0から1の範囲)。
    /// - Returns: 曲線上の点。
    public static func q(controlPoints: [SIMD3<Float>], t: Float) -> SIMD3<Float> {
        let tx = 1.0 - t
        let pA = controlPoints[0] * pow(tx, 3)
        let pB = controlPoints[1] * (3 * pow(tx, 2) * t)
        let pC = controlPoints[2] * (3 * tx * pow(t, 2))
        let pD = controlPoints[3] * pow(t, 3)
        return pA + pB + pC + pD
    }

    /// 3次ベジェ曲線の一次導関数をパラメータtで評価します。
    /// B'(t) = 3(1-t)^2(P1-P0) + 6(1-t)t(P2-P1) + 3t^2(P3-P2)
    /// - Parameters:
    ///   - controlPoints: 4つの制御点 [P0, P1, P2, P3]。
    ///   - t: パラメータ。
    /// - Returns: 曲線上の点における接線ベクトル。
    public static func qprime(controlPoints: [SIMD3<Float>], t: Float) -> SIMD3<Float> {
        let tx = 1.0 - t
        let pA = (controlPoints[1] - controlPoints[0]) * (3 * pow(tx, 2))
        let pB = (controlPoints[2] - controlPoints[1]) * (6 * tx * t)
        let pC = (controlPoints[3] - controlPoints[2]) * (3 * pow(t, 2))
        return pA + pB + pC
    }

    /// 3次ベジェ曲線の二次導関数をパラメータtで評価します。
    /// B''(t) = 6(1-t)(P2-2P1+P0) + 6t(P3-2P2+P1)
    /// - Parameters:
    ///   - controlPoints: 4つの制御点 [P0, P1, P2, P3]。
    ///   - t: パラメータ。
    /// - Returns: 曲線上の点における曲率に関連するベクトル。
    public static func qprimeprime(controlPoints: [SIMD3<Float>], t: Float) -> SIMD3<Float> {
        let pA: SIMD3<Float> = (controlPoints[2] - 2 * controlPoints[1] + controlPoints[0]) * (6 * (1.0 - t))
        let pB: SIMD3<Float> = (controlPoints[3] - 2 * controlPoints[2] + controlPoints[1]) * (6 * t)
        return pA + pB
    }
}

/// 点群にベジェ曲線をフィットさせるための構造体。
struct BezierFitter {

    /// フィッティングの進捗状況を通知するためのデータ構造。
    public struct ProgressData {
        public let bezierCurve: [SIMD3<Float>]
        public let points: [SIMD3<Float>]
        public let parameters: [Float]
        public let maxError: Float
        public let splitPointIndex: Int
    }
    
    /// 進捗状況を通知するためのコールバッククロージャの型エイリアス。
    public typealias ProgressCallback = (ProgressData) -> Void

    /// 一連の点に1つまたは複数のベジェ曲線をフィットさせます。
    /// - Parameters:
    ///   - points: フィットさせる点の配列。
    ///   - maxError: 許容される最大二乗誤差。
    ///   - progressCallback: フィッティングの各イテレーションの進捗を通知するコールバック。
    /// - Returns: フィットしたベジェ曲線の制御点の配列の配列。
    public static func fitCurve(points: [SIMD3<Float>], maxError: Float,
                                progressCallback: ProgressCallback? = nil) -> [[SIMD3<Float>]] {
        guard !points.isEmpty else {
            print("Error: First argument must be a non-empty list of points.")
            return []
        }

        // 近すぎる重複点を除去
        var uniquePoints = [SIMD3<Float>]()
        if let first = points.first {
            uniquePoints.append(first)
            for i in 1..<points.count {
                if distance(points[i], points[i-1]) >= 1e-9 {
                    uniquePoints.append(points[i])
                }
            }
        }
        
        guard uniquePoints.count >= 2 else {
            return []
        }

        let leftTangent = createTangent(from: uniquePoints[1], to: uniquePoints[0])
        let rightTangent = createTangent(from: uniquePoints[uniquePoints.count - 2], to: uniquePoints.last!)

        return fitCubic(points: uniquePoints, leftTangent: leftTangent, rightTangent: rightTangent, error: maxError, progressCallback: progressCallback)
    }

    /// 点群のサブセットに再帰的にベジェ曲線をフィットさせます。
    private static func fitCubic(points: [SIMD3<Float>], leftTangent: SIMD3<Float>, rightTangent: SIMD3<Float>, error: Float, progressCallback: ProgressCallback?) -> [[SIMD3<Float>]] {
        let maxIterations = 20

        // 点が2つしかない場合は、直線的なベジェ曲線を作成
        if points.count == 2 {
            let dist = distance(points[0], points[1]) / 3.0
            let bezCurve = [
                points[0],
                points[0] + leftTangent * dist,
                points[1] + rightTangent * dist,
                points[1]
            ]
            return [bezCurve]
        }
        
        // 弦長に基づいて点をパラメータ化
        let u = chordLengthParameterize(points: points)
        var (bezCurve, maxError, splitPoint) = generateAndReport(
            points: points, paramsOrig: u, paramsPrime: u,
            leftTangent: leftTangent, rightTangent: rightTangent,
            progressCallback: progressCallback
        )

        // エラーが許容範囲内なら、この曲線を採用
        if maxError < error {
            return [bezCurve]
        }

        // エラーが大きい場合、パラメータを再計算して改善を試みる
        if maxError < error * error {
            var uPrime = u
            var prevErr = maxError
            var prevSplit = splitPoint

            for _ in 0..<maxIterations {
                uPrime = reparameterize(bezierCurve: bezCurve, points: points, parameters: uPrime)
                (bezCurve, maxError, splitPoint) = generateAndReport(
                    points: points, paramsOrig: u, paramsPrime: uPrime,
                    leftTangent: leftTangent, rightTangent: rightTangent,
                    progressCallback: progressCallback
                )
                if maxError < error {
                    return [bezCurve]
                }
                
                // 収束判定
                if splitPoint == prevSplit {
                    let errChange = maxError / prevErr
                    if (0.9999 < errChange && errChange < 1.0001) {
                        break
                    }
                }
                prevErr = maxError
                prevSplit = splitPoint
            }
        }

        // 改善が見られない場合、最もエラーの大きい点で曲線を分割
        var beziers: [[SIMD3<Float>]] = []
        var centerVector = points[splitPoint - 1] - points[splitPoint + 1]

        if length_squared(centerVector) < 1e-9 {
            let vPrev = points[splitPoint - 1] - points[splitPoint]
            let vNext = points[splitPoint + 1] - points[splitPoint]
            
            // 3点が同一直線上にある場合の処理
            if length_squared(vPrev) > 1e-9 {
                var axisVec = SIMD3<Float>(1.0, 0.0, 0.0)
                if length_squared(cross(vPrev, axisVec)) < 1e-9 {
                    axisVec = SIMD3<Float>(0.0, 1.0, 0.0)
                }
                centerVector = cross(vPrev, axisVec)
            } else if length_squared(vNext) > 1e-9 {
                var axisVec = SIMD3<Float>(1.0, 0.0, 0.0)
                if length_squared(cross(vNext, axisVec)) < 1e-9 {
                    axisVec = SIMD3<Float>(0.0, 1.0, 0.0)
                }
                centerVector = cross(vNext, axisVec)
            } else {
                centerVector = SIMD3<Float>(1.0, 0.0, 0.0)
            }
        }
        
        let normCenterVector = normalize(centerVector)
        let toCenterTangent = normCenterVector
        let fromCenterTangent = -normCenterVector

        let leftPoints = Array(points[...splitPoint])
        beziers.append(contentsOf: fitCubic(points: leftPoints, leftTangent: leftTangent, rightTangent: toCenterTangent, error: error, progressCallback: progressCallback))
        
        let rightPoints = Array(points[splitPoint...])
        beziers.append(contentsOf: fitCubic(points: rightPoints, leftTangent: fromCenterTangent, rightTangent: rightTangent, error: error, progressCallback: progressCallback))
        
        return beziers
    }

    /// ベジェ曲線を生成し、最大誤差を計算して報告します。
    private static func generateAndReport(points: [SIMD3<Float>], paramsOrig: [Float], paramsPrime: [Float],
                                           leftTangent: SIMD3<Float>, rightTangent: SIMD3<Float>,
                                           progressCallback: ProgressCallback?) -> (curve: [SIMD3<Float>], maxError: Float, splitPoint: Int) {
        
        let bezCurve = generateBezier(points: points, parameters: paramsPrime, leftTangent: leftTangent, rightTangent: rightTangent)
        let (maxError, splitPoint) = computeMaxError(points: points, bez: bezCurve, parameters: paramsOrig)

        if let callback = progressCallback {
            callback(ProgressData(
                bezierCurve: bezCurve,
                points: points,
                parameters: paramsOrig,
                maxError: maxError,
                splitPointIndex: splitPoint
            ))
        }
        
        return (bezCurve, maxError, splitPoint)
    }

    /// 最小二乗法を用いてベジェ曲線の制御点を生成します。
    private static func generateBezier(points: [SIMD3<Float>], parameters: [Float],
                                       leftTangent: SIMD3<Float>, rightTangent: SIMD3<Float>) -> [SIMD3<Float>] {
        guard let firstPoint = points.first, let lastPoint = points.last else { return [] }

        var A = [[SIMD3<Float>]](repeating: [.zero, .zero], count: parameters.count)
        for (i, u) in parameters.enumerated() {
            let ux = 1.0 - u
            A[i][0] = leftTangent * (3 * u * pow(ux, 2))
            A[i][1] = rightTangent * (3 * ux * pow(u, 2))
        }

        var c00:Float = 0.0, c01:Float = 0.0, c11:Float = 0.0
        var x0:Float = 0.0, x1:Float = 0.0

        for (i, p) in points.enumerated() {
            let a = A[i]
            c00 += dot(a[0], a[0])
            c01 += dot(a[0], a[1])
            c11 += dot(a[1], a[1])

            let u = parameters[i]
            let qDegenerate = firstPoint * (1.0 - u) + lastPoint * u
            let tmp = p - qDegenerate
            
            x0 += dot(a[0], tmp)
            x1 += dot(a[1], tmp)
        }
        let c10 = c01

        let detC0C1 = c00 * c11 - c10 * c01
        let detC0X = c00 * x1 - c10 * x0
        let detXC1 = x0 * c11 - x1 * c01

        let alphaL = abs(detC0C1) < 1e-9 ? 0.0 : detXC1 / detC0C1
        let alphaR = abs(detC0C1) < 1e-9 ? 0.0 : detC0X / detC0C1

        let segLength = distance(firstPoint, lastPoint)
        let epsilon = 1.0e-6 * segLength

        let ctrl1: SIMD3<Float>
        let ctrl2: SIMD3<Float>

        if alphaL < epsilon || alphaR < epsilon {
            ctrl1 = firstPoint + leftTangent * (segLength / 3.0)
            ctrl2 = lastPoint + rightTangent * (segLength / 3.0)
        } else {
            ctrl1 = firstPoint + leftTangent * alphaL
            ctrl2 = lastPoint + rightTangent * alphaR
        }
        
        return [firstPoint, ctrl1, ctrl2, lastPoint]
////        return [one, two]
    }
    
    /// ニュートン・ラフソン法を用いてパラメータを再計算します。
    private static func reparameterize(bezierCurve: [SIMD3<Float>], points: [SIMD3<Float>], parameters: [Float]) -> [Float] {
        return zip(points, parameters).map { (p, u) in
            newtonRaphsonRootFind(bez: bezierCurve, point: p, u: u)
        }
    }

    /// ニュートン・ラフソン法で、点に最も近い曲線上のパラメータuを見つけます。
    private static func newtonRaphsonRootFind(bez: [SIMD3<Float>], point: SIMD3<Float>, u: Float) -> Float {
        let d = Bezier.q(controlPoints: bez, t: u) - point
        let qprime = Bezier.qprime(controlPoints: bez, t: u)
        let numerator = dot(d, qprime)
        
        let qprimeprime = Bezier.qprimeprime(controlPoints: bez, t: u)
        let denominator = dot(qprime, qprime) + dot(d, qprimeprime)
        
        return abs(denominator) < 1e-9 ? u : u - (numerator / denominator)
    }

    /// 弦長に基づいて点群をパラメータ化します (0から1の範囲)。
    private static func chordLengthParameterize(points: [SIMD3<Float>]) -> [Float] {
        var distances = [Float](repeating: 0.0, count: points.count)
        for i in 1..<points.count {
            distances[i] = distances[i-1] + distance(points[i], points[i-1])
        }
        
        guard let totalLength = distances.last, totalLength > 0 else {
            return (0..<points.count).map { Float($0) / Float(points.count - 1) }
        }
        
        return distances.map { $0 / totalLength }
    }

    /// 点群とベジェ曲線との間の最大二乗誤差を計算します。
    private static func computeMaxError(points: [SIMD3<Float>], bez: [SIMD3<Float>], parameters: [Float]) -> (maxDist: Float, splitPoint: Int) {
        var maxDist: Float = 0.0
        var splitPoint = points.count / 2
        
        let tDistMap = mapTToRelativeDistances(bez: bez, parts: 10)

        for (i, (point, param)) in zip(points, parameters).enumerated() {
            let t = findT(bez: bez, param: param, tDistMap: tDistMap)
            let v = Bezier.q(controlPoints: bez, t: t) - point
            let dist = length_squared(v) // 二乗距離を使用

            if dist > maxDist {
                maxDist = dist
                splitPoint = i
            }
        }
        return (maxDist, splitPoint)
    }

    /// ベジェ曲線のパラメータtと相対的な弧長の対応表を作成します。
    private static func mapTToRelativeDistances(bez: [SIMD3<Float>], parts: Int) -> [Float] {
        var distances: [Float] = [0.0]
        var bTPrev = bez[0]
        
        for i in 1...parts {
            let t: Float = Float(i) / Float(parts)
            let bTCurr = Bezier.q(controlPoints: bez, t: t)
            distances.append(distances.last! + distance(bTCurr, bTPrev))
            bTPrev = bTCurr
        }
        
        guard let totalLength = distances.last, totalLength > 0 else {
            return distances
        }
        
        return distances.map { $0 / totalLength }
    }

    /// 弧長のパラメータからベジェ曲線のパラメータtを近似的に見つけます。
    private static func findT(bez: [SIMD3<Float>], param: Float, tDistMap: [Float]) -> Float {
        if param < 0 { return 0.0 }
        if param > 1 { return 1.0 }

        let parts = tDistMap.count - 1
        
        for i in 1...parts {
            if param <= tDistMap[i] {
                let tMin = Float(i - 1) / Float(parts)
                let tMax = Float(i) / Float(parts)
                let lenMin = tDistMap[i-1]
                let lenMax = tDistMap[i]
                
                guard lenMax > lenMin else { return tMin }

                let t = (param - lenMin) / (lenMax - lenMin) * (tMax - tMin) + tMin
                return t
            }
        }
        
        return 1.0
    }

    /// 2点間の正規化された接線ベクトルを作成します。
    private static func createTangent(from pointA: SIMD3<Float>, to pointB: SIMD3<Float>) -> SIMD3<Float> {
        let vec = pointA - pointB
        return normalize(vec)
    }
}
