//
//  Extension.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import ARKit
import RealityKit
import simd

extension SIMD3 {
    // Initialize Float4 with SIMD3<Float> inputs.
    init(_ float4: SIMD4<Scalar>) {
        self.init()
        
        x = float4.x
        y = float4.y
        z = float4.z
    }
}

extension simd_float4x4 {
    /// The value to access the identity of Float4x4.
    static var identity: simd_float4x4 {
        matrix_identity_float4x4
    }
}

/// Create a mathematical clamp.
func clamp(_ valueX: Float, min minV: Float, max maxV: Float) -> Float {
    return min(maxV, max(minV, valueX))
}


extension simd_float3 {
    var list: [Float] {
        return [x, y, z]
    }
}

extension simd_float4 {
    var codable: [Float] {
        return [x, y, z, w]
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        self[SIMD3(0, 1, 2)]
    }
}


extension simd_float4x4 {
    var codable: [[Float]] {
        return [columns.0.codable, columns.1.codable, columns.2.codable, columns.3.codable]
    }
}

extension simd_float4x4 {
    var position: SIMD3<Float> {
        self.columns.3.xyz
    }
    
    init(pos: SIMD3<Float>) {
        self.init([
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(pos.x, pos.y, pos.z, 1)
        ])
    }
    
    init?(floatListStr: [String]) {
        let values = floatListStr.compactMap(Float.init)
        if values.count != 16 { return nil }
        
        self.init([
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        ])
    }
    
    var floatList: [[Float]] {
        return [
            [self.columns.0.x, self.columns.0.y, self.columns.0.z, self.columns.0.w],
            [self.columns.1.x, self.columns.1.y, self.columns.1.z, self.columns.1.w],
            [self.columns.2.x, self.columns.2.y, self.columns.2.z, self.columns.2.w],
            [self.columns.3.x, self.columns.3.y, self.columns.3.z, self.columns.3.w]
        ]
    }
    
    var doubleList: [[Double]] {
        return [
            [Double(self.columns.0.x), Double(self.columns.0.y), Double(self.columns.0.z), Double(self.columns.0.w)],
            [Double(self.columns.1.x), Double(self.columns.1.y), Double(self.columns.1.z), Double(self.columns.1.w)],
            [Double(self.columns.2.x), Double(self.columns.2.y), Double(self.columns.2.z), Double(self.columns.2.w)],
            [Double(self.columns.3.x), Double(self.columns.3.y), Double(self.columns.3.z), Double(self.columns.3.w)]
        ]
    }
}

extension Float {
    func toDouble() -> Double {
        Double(self)
    }
}

extension Double {
    func toFloat() -> Float {
        Float(self)
    }
}

extension [[Double]] {
    var transpose4x4: [[Double]] {
        var result = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                result[i][j] = self[j][i]
            }
        }
        return result
    }
    
    func tosimd_float4x4() -> simd_float4x4 {
        return simd_float4x4([
            SIMD4<Float>(self[0][0].toFloat(), self[0][1].toFloat(), self[0][2].toFloat(), self[0][3].toFloat()),
            SIMD4<Float>(self[1][0].toFloat(), self[1][1].toFloat(), self[1][2].toFloat(), self[1][3].toFloat()),
            SIMD4<Float>(self[2][0].toFloat(), self[2][1].toFloat(), self[2][2].toFloat(), self[2][3].toFloat()),
            SIMD4<Float>(self[3][0].toFloat(), self[3][1].toFloat(), self[3][2].toFloat(), self[3][3].toFloat())
        ])
    }
    
    var isIncludeNaN: Bool {
        for row in self {
            for value in row {
                if value.isNaN {
                    return true
                }
            }
        }
        return false
    }
}

extension [[Float]] {
    func tosimd_float4x4() -> simd_float4x4 {
        return simd_float4x4([
            SIMD4<Float>(self[0][0], self[0][1], self[0][2], self[0][3]),
            SIMD4<Float>(self[1][0], self[1][1], self[1][2], self[1][3]),
            SIMD4<Float>(self[2][0], self[2][1], self[2][2], self[2][3]),
            SIMD4<Float>(self[3][0], self[3][1], self[3][2], self[3][3])
        ])
    }
    
    func toDoubleList() -> [[Double]] {
        return self.map { $0.map { Double($0) } }
    }
}

//extension Array where Element == Stroke {
//    /// point が count 以下のストロークを取り除いた配列を返す
//    func removingShortStrokes(minPoints: Int = 3) -> [Stroke] {
//        return self.filter { $0.points.count >= minPoints }
//    }
//}

extension Array where Element == BezierStroke {
    /// point が count 以下のストロークを取り除いた配列を返す
    func removingShortStrokes(minPoints: Int = 3) -> [BezierStroke] {
        return self.filter { $0.points.count >= minPoints }
    }
}
