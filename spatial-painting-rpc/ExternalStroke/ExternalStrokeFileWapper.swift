//
//  ExternalFileStorage.swift
//  facetracking-and-overlay
//
//  Created by blueken on 2025/05/24.
//

import ARKit
import RealityKit
import UIKit
import ImageIO

@Observable
class ExternalStrokeFileWapper {
    private let documentDirectory: URL
    private var fileDir: URL
    
    var isFileManagerActive: Bool = false
    private let systemSoundPlayer = SystemSoundPlayer()
    
    var planeNormalVector: SIMD3<Float> = SIMD3<Float>(0,0,0)
    var planePoint: SIMD3<Float> = SIMD3<Float>(0,0,0)
    
    init() {
        self.documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileDir = documentDirectory.appendingPathComponent("StrokeCanvas/")
        // ディレクトリが存在しない場合は作成
        if !FileManager.default.fileExists(atPath: fileDir.path) {
            do {
                try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true, attributes: nil)
                print("Directory created at: \(fileDir.path)")
            } catch {
                print("Error creating directory: \(error)")
            }
        }
    }
    
    /// 外部に保存する
    func writeStroke(strokes : [Stroke], displayScale: CGFloat, planeNormalVector: SIMD3<Float>, planePoint: SIMD3<Float>) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let nowDate = Date()
        let jsonFileURL = fileDir.appendingPathComponent("\(formattedDate(nowDate))/strokes.json")
        let imageFileURL = fileDir.appendingPathComponent("\(formattedDate(nowDate))/thumbnail.png")
        do {
            // 先にディレクトリを作成
            let directoryURL = jsonFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            
            let data = try encoder.encode(strokes)
            try data.write(to: jsonFileURL)
            print("File written to: \(jsonFileURL.path)")
            
            guard let imageData = makePNGData(strokes: strokes, planeNormal: planeNormalVector, planePoint: planePoint, displayScale: displayScale) else {
                print("Error converting image to PNG data")
                return
            }
            try imageData.write(to: imageFileURL)
            print("Image written to: \(imageFileURL.path)")
            systemSoundPlayer.play(systemSound: .cameraShutterSound)
        } catch {
            print("Error writing file: \(error)")
        }
    }
    
    /// ストロークを削除する
    func deleteStroke(in selectedImageURL: URL) {
        // 選択されたディレクトリの URL を取得
        let selectedURL = selectedImageURL.deletingLastPathComponent()
        do {
            // 選択されたディレクトリを削除
            try FileManager.default.removeItem(at: selectedURL)
            print("Deleted directory at: \(selectedURL.path)")
        } catch {
            print("Error deleting directory: \(error)")
        }
    }
    
    /// ストロークから画像を作る
    private func makePNGData(strokes: [Stroke], planeNormal: SIMD3<Float>, planePoint: SIMD3<Float>, displayScale: CGFloat) -> Data? {
        let canvasSize = CGSize(width: 1024, height: 1024)
        /*
         let n = normalize(planeNormal)
         let arbitrary: SIMD3<Float> = abs(n.x) < 0.9 ? [1,0,0] : [0,1,0]
         let u = normalize(cross(n, arbitrary)), v = cross(n, u)
         */
        // planeNormal を正規化
        let n = normalize(planeNormal)
        // ワールドの下向きベクトル
        let worldUp = SIMD3<Float>(0, -1, 0)
        
        // 1) worldUpを平面に落とした「平面内の上向きvを計算
        var v = worldUp - n * dot(worldUp, n)
        // もしほとんどゼロベクトル（planeNormalがworldUpと平行）なら
        if length(v) < 1e-6 {
            // 任意の横方向を使う（平面が水平 or ほぼ水平のときのフォールバック）
            v = normalize(cross(n, SIMD3<Float>(1, 0, 0)))
        } else {
            v = normalize(v)
        }
        
        // 2) X軸方向uは外積で
        let u = normalize(cross(v, n))
        
        // 以降はu,vを使って3D→2D射影
        // 2D射影＋バウンディング計算
        var all2D: [[SIMD2<Float>]] = []
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for stroke in strokes {
            var proj: [SIMD2<Float>] = []
            for p in stroke.points {
                let pProj = p - dot(p - planePoint, n) * n
                let x = dot(pProj - planePoint, u), y = dot(pProj - planePoint, v)
                proj.append([x,y])
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            all2D.append(proj)
        }
        
        // スケーリング
        let inset: CGFloat = 50
        let wF = maxX - minX, hF = maxY - minY
        let scale = min((canvasSize.width - inset*2)/CGFloat(wF),
                        (canvasSize.height - inset*2)/CGFloat(hF))
        
        // CGContext作成
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: Int(canvasSize.width * displayScale),
                height: Int(canvasSize.height * displayScale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.scaleBy(x: displayScale, y: displayScale)
        ctx.setLineCap(.round)
        ctx.setLineWidth(4)
        
        // 描画
        for (idx, stroke) in strokes.enumerated() {
            ctx.setStrokeColor(stroke.activeColor.cgColor)
            let proj = all2D[idx]
            guard proj.count > 1 else { continue }
            ctx.beginPath()
            let first = proj[0]
            ctx.move(to: CGPoint(
                x: CGFloat(first.x - minX)*scale + inset,
                y: CGFloat(maxY - first.y)*scale + inset
            ))
            for pt in proj.dropFirst() {
                ctx.addLine(to: CGPoint(
                    x: CGFloat(pt.x - minX)*scale + inset,
                    y: CGFloat(maxY - pt.y)*scale + inset
                ))
            }
            ctx.strokePath()
        }
        
        guard let cgImg = ctx.makeImage() else { return nil }
        
        // 90°回転
        //let finalImage = rotateCGImage90Clockwise(cgImg) ?? cgImg
        
        // CGImageDestination で PNG データ化
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImg /*finalImage*/, nil)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        return mutableData as Data
    }
    
    /// CGImageを90°時計回りに回転した新しいCGImageを返す
    func rotateCGImage90Clockwise(_ image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        
        guard
            let colorSpace = image.colorSpace,
            let ctx = CGContext(
                data: nil,
                width: h,               // 幅と高さを反転
                height: w,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
            )
        else {
            return nil
        }
        
        // 原点を左下（新コンテキストの (0,w)）に移動
        ctx.translateBy(x: 0, y: CGFloat(w))
        // -90° 回転 (radians)
        ctx.rotate(by: -CGFloat.pi/2)
        // 元画像を描画
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage()
    }
    
    // entity の「前方向（−Z 軸）」をベクトルで得る
    func forwardVector(of entity: Entity) -> SIMD3<Float> {
        // RealityKit では回転が transform.rotation（simd_quatf）に入っている
        let q: simd_quatf = entity.transform.rotation
        
        // ローカル空間の「前方向」ベクトル (0,0,-1) をクォータニオンで回転
        let localForward = SIMD3<Float>(0, 0, -1)
        let worldForward = q.act(localForward)
        
        print("Forward vector: \(worldForward)")
        
        return normalize(worldForward)
    }
    
    /// ディレクトリの一覧を取得する
    func listDirs() -> [URL] {
        do {
            let fileManager = FileManager.default
            let directories = try fileManager.contentsOfDirectory(at: fileDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            // ディレクトリのみをフィルタリング
            let dirs = directories.filter { $0.hasDirectoryPath }
            print("Directories found: \(dirs)")
            return dirs
        } catch {
            print("Error listing files: \(error)")
            return []
        }
    }
    
    /// jsonを取得する
    func readStrokes(in dateStr: String) -> [Stroke] {
        do {
            let jsonFileURL = fileDir.appendingPathComponent("\(dateStr)/strokes.json")
            let data = try Data(contentsOf: jsonFileURL)
            let decoder = JSONDecoder()
            let strokes = try decoder.decode([Stroke].self, from: data)
            return strokes
        }
        catch {
            print("Error reading JSON file: \(error)")
            return []
        }
    }
    
    /// 画像を取得する
    func readImage(in dateStr: String) -> UIImage? {
        let imageFileURL = fileDir.appendingPathComponent("\(dateStr)/thumbnail.png")
        if let imageData = try? Data(contentsOf: imageFileURL) {
            return UIImage(data: imageData)
        } else {
            print("Error reading image file at \(imageFileURL.path)")
            return nil
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}
