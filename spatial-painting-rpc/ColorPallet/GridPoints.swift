//
//  GridPoints.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/11/16.
//

import Foundation
import simd

final class GridPoints {
    struct GridCellKey: Hashable {
        let x, y, z: Int
    }
    
    typealias PointData = (uuid: UUID, position: SIMD3<Float>)
    typealias SpatialGrid = [GridCellKey: [PointData]]
    
    var spatialGrid: SpatialGrid = [:]
    var uuidToKey: [UUID: GridCellKey] = [:]
    
    let cellSize: Float
    
    init(cellSize: Float = 0.1) {
        self.cellSize = cellSize
    }
    
    /**
     * コントロールポイント群から空間グリッドにポイントを追加します。
     * - Parameters:
     * - controlPoints: UUIDをキー、SIMD3<Float>を値とする辞書形式のコントロールポイント群
     */
    func addPoints(from controlPoints: [(uuid: UUID, position: SIMD3<Float>)]) {
        for point in controlPoints {
            let key = GridCellKey(
                x: Int(floor(point.position.x / cellSize)),
                y: Int(floor(point.position.y / cellSize)),
                z: Int(floor(point.position.z / cellSize))
            )
            
            spatialGrid[key, default: []].append(point)
            uuidToKey[point.uuid] = key
        }
    }
    
    /**
     * コントロールポイント群から空間グリッドにポイントを追加します。
     * - Parameters:
     * - controlPoints: UUIDをキー、SIMD3<Float>を値とする辞書形式のコントロールポイント群
     */
    func addPoints(from controlPoints: [BezierStroke.BezierPoint]) {
        for point in controlPoints {
            if let end = point.end,
               let startControl = point.startControl,
               let endControl = point.endControl {
                let endKey = GridCellKey(
                    x: Int(floor(end.x / cellSize)),
                    y: Int(floor(end.y / cellSize)),
                    z: Int(floor(end.z / cellSize))
                )
                let endPoiint: PointData = (uuid: point.endID, position: end)
                spatialGrid[endKey, default: []].append(endPoiint)
                uuidToKey[endPoiint.uuid] = endKey
                
                let startControlKey = GridCellKey(
                    x: Int(floor(startControl.x / cellSize)),
                    y: Int(floor(startControl.y / cellSize)),
                    z: Int(floor(startControl.z / cellSize))
                )
                let startControlPoint: PointData = (uuid: point.startControlID, position: startControl)
                spatialGrid[startControlKey, default: []].append(startControlPoint)
                uuidToKey[startControlPoint.uuid] = startControlKey
                
                let endControlKey = GridCellKey(
                    x: Int(floor(endControl.x / cellSize)),
                    y: Int(floor(endControl.y / cellSize)),
                    z: Int(floor(endControl.z / cellSize))
                )
                let endControlPoint: PointData = (uuid: point.endControlID, position: endControl)
                spatialGrid[endControlKey, default: []].append(endControlPoint)
                uuidToKey[endControlPoint.uuid] = endControlKey
            }
        }
    }
    
    /**
        * ポイントを削除する
     */
    func removePoints(from points: [BezierStroke.BezierPoint]) {
        for point in points {
            removePoint(from: point.endID)
            removePoint(from: point.startControlID)
            removePoint(from: point.endControlID)
        }
    }

    /**
        * ポイントを削除する
     */
    func removePoint(from uuid: UUID) {
        guard let key = uuidToKey[uuid],
              var pointsInCell = spatialGrid[key] else {
            return
        }
        
        pointsInCell.removeAll { $0.uuid == uuid }
        spatialGrid[key] = pointsInCell.isEmpty ? nil : pointsInCell
        uuidToKey.removeValue(forKey: uuid)
        
        if spatialGrid[key]?.isEmpty == true {
            spatialGrid.removeValue(forKey: key)
        }
    }
    
    /**
     * 空間グリッドを使用して、指定した地点の一定範囲内にある【最も近い】ポイントを検索します。
     *
     * - Parameters:
     * - queryPoint: 検索の中心地点
     * - radius: 検索半径
     * - Returns: 範囲内に見つかった最も近いSIMD3<Float>。見つからない場合はnil。
     */
    func findNearestPointInRadius( // メソッド名を変更して意図を明確にする案
        queryPoint: SIMD3<Float>,
        radius: Float,
    ) -> SIMD3<Float>? {
        var minDistanceSquared = radius * radius
        var closestPoint: SIMD3<Float>? = nil
        
        let minBounds = queryPoint - SIMD3<Float>(repeating: radius)
        let maxBounds = queryPoint + SIMD3<Float>(repeating: radius)
        
        let minKey = GridCellKey(
            x: Int(floor(minBounds.x / cellSize)),
            y: Int(floor(minBounds.y / cellSize)),
            z: Int(floor(minBounds.z / cellSize))
        )
        let maxKey = GridCellKey(
            x: Int(floor(maxBounds.x / cellSize)),
            y: Int(floor(maxBounds.y / cellSize)),
            z: Int(floor(maxBounds.z / cellSize))
        )
        
        for x in minKey.x...maxKey.x {
            for y in minKey.y...maxKey.y {
                for z in minKey.z...maxKey.z {
                    let key = GridCellKey(x: x, y: y, z: z)
                    
                    if let pointsInCell = spatialGrid[key] {
                        for point in pointsInCell {
                            let distSq = distance_squared(queryPoint, point.position)
    
                            if distSq < minDistanceSquared {
                                minDistanceSquared = distSq
                                closestPoint = point.position
                            }
                        }
                    }
                }
            }
        }
        
        return closestPoint
    }
}
