//
//  ExportInportView.swift
//  spatial-painting-single
//
//  Created by blueken on 2025/06/24.
//

import SwiftUI

struct ExternalStrokeView: View {
    @EnvironmentObject private var appModel: AppModel
    
    @Environment(\.displayScale) private var displayScale: CGFloat
    
    var externalStrokeFileWapper: ExternalStrokeFileWapper = ExternalStrokeFileWapper()
    
    @State private var imageURLs: [URL] = []
    @State private var selectedURL: URL?
    
    @State var fileList: [String] = []
    @State var selectedFile: String = ""
    
    @State private var isLoading: Bool = false
    @State private var isDeleteMode: Bool = false
    
    var body: some View {
        VStack {
            if isDeleteMode {
                VStack(spacing: 0) {
                    // サムネイルグリッド
                    ThumbnailDeleteGridView(
                        imageURLs: $imageURLs,
                        selectedURL: $selectedURL
                    )
                    // 選択中のファイルを下部に表示
                    if let url = selectedURL {
                        let comps = url.pathComponents
                        Text("Selected: \(comps[comps.count - 2])")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
                //.onAppear(perform: loadThumbnails)
                .ignoresSafeArea(edges: .bottom)
                
                // ファイル読み込み
                Button("Delete File") {
                    // 選択されたファイルを削除
                    if let selectedImageURL = selectedURL {
                        appModel.externalStrokeFileWapper.deleteStroke(in: selectedImageURL)
                    }
                    fileList = appModel.externalStrokeFileWapper.listDirs().map { $0.lastPathComponent }.sorted(by: >)
                    imageURLs = loadThumbnails()
                    selectedURL = nil
                }
                .padding(.bottom, 20)
            } else {
                // 保存
                Button("Save Stroke") {
                    appModel.externalStrokeFileWapper.writeStroke(strokes: appModel.rpcModel.painting.paintingCanvas.strokes, displayScale: displayScale, planeNormalVector: .one, planePoint: .one)
                    fileList = appModel.externalStrokeFileWapper.listDirs().map { $0.lastPathComponent }.sorted(by: >)
                    imageURLs = loadThumbnails()
                    if fileList.count == 1 {
                        selectedFile = fileList[0]
                    }
                }
                .padding(.top, 20)
                
                VStack(spacing: 0) {
                    // サムネイルグリッド
                    ThumbnailGridView(
                        imageURLs: $imageURLs,
                        selectedURL: $selectedURL
                    )
                    // 選択中のファイルを下部に表示
                    if let url = selectedURL {
                        let comps = url.pathComponents
                        Text("Selected: \(comps[comps.count - 2])")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                
                // ファイル読み込み
                Toggle("Load Stroke Mode", isOn: $isLoading)
                    .toggleStyle(.button)
                    .padding(.bottom, 20)
                    .onChange(of: isLoading) {
                        if isLoading {
                            if let comps = selectedURL?.pathComponents {
                                selectedFile = comps[comps.count - 2]
                            }
                            if !selectedFile.isEmpty {
                                appModel.rpcModel.painting.paintingCanvas.addTmpStrokes(appModel.externalStrokeFileWapper.readStrokes(in: selectedFile))
                            }
                        } else {
                            appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
                        }
                    }
                
                // ロードしたデータの確定
                Button("Confirm Loaded Stroke") {
                    for (id,affineMatrix) in appModel.rpcModel.coordinateTransforms.affineMatrixs {
                        let transformedStrokes = appModel.rpcModel.painting.paintingCanvas.tmpStrokes.map({ (stroke: Stroke) in
                            // points 全てにアフィン変換を適用
                            let tmpRootTransfromPoints: [SIMD4<Float>] = stroke.points.map { (point: SIMD3<Float>) in
                                return stroke.entity.transformMatrix(relativeTo: nil) * SIMD4<Float>(point, 1.0)
                            }
                            let transformedPoints = tmpRootTransfromPoints.map { (point: SIMD4<Float>) in
                                matmul4x4_4x1(affineMatrix, point)
                            }
                            return Stroke(uuid: UUID(), points: transformedPoints, color: stroke.activeColor, maxRadius: stroke.maxRadius)
                        })
                        _ = appModel.rpcModel.sendRequest(
                            .init(
                                peerId: appModel.mcPeerIDUUIDWrapper.mine.hash,
                                method: .addStrokes,
                                param: .addStrokes(.init(strokes: transformedStrokes))
                            ),
                            mcPeerId: id
                        )
                    }
                    appModel.rpcModel.painting.paintingCanvas.confirmTmpStrokes()
                    // isLoading を false にしてロードモードを終了
                    isLoading = false
                }
                .padding(.bottom, 20)
                .disabled(!appModel.rpcModel.painting.paintingCanvas.tmpStrokes.isEmpty)
                
            }
            Toggle("Delete Mode", isOn: $isDeleteMode)
                .toggleStyle(.button)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            
        }
        .onAppear() {
            fileList = appModel.externalStrokeFileWapper.listDirs().map { $0.lastPathComponent }.sorted(by: >)
            imageURLs = loadThumbnails()
            externalStrokeFileWapper.planeNormalVector = appModel.model.planeNormalVector
            externalStrokeFileWapper.planePoint = appModel.model.planePoint
        }
        .onDisappear {
            isLoading = false
            appModel.rpcModel.painting.paintingCanvas.clearTmpStrokes()
        }
    }
    
    /// Documents/StrokeCanvas 以下をスキャンして thumbnail.png を集める
    private func loadThumbnails() -> [URL] {
        let docDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let canvasDir = docDir.appendingPathComponent("StrokeCanvas", isDirectory: true)
        
        var urls: [URL] = []
        
        for dir in fileList {
            let thumb = canvasDir.appendingPathComponent(dir+"/thumbnail.png")
            if FileManager.default.fileExists(atPath: thumb.path) {
                urls.append(thumb)
            }
        }
        return urls
    }
}

/// サムネイル一覧＋選択ビュー
struct ThumbnailGridView: View {
    @Binding var imageURLs: [URL]    // サムネイル画像ファイルの URL 一覧
    @Binding var selectedURL: URL?   // 選択中の画像 URL
    
    // Adaptive サイズのカラムレイアウト
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(imageURLs, id: \.self) { url in
                    if let cg = loadCGImage(from: url) {
                        Button {
                            selectedURL = url
                        } label: {
                            Image(decorative: cg, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipped()
                                .overlay(
                                    // 選択中はアクセントカラーで枠線
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(selectedURL == url
                                                ? Color.accentColor
                                                : Color.clear,
                                                lineWidth: 4
                                               )
                                )
                        }
                        .buttonStyle(.plain) // フォーカス可能に
                    }
                }
            }
            .padding()
        }
    }
    
    /// URL から CGImage を生成
    private func loadCGImage(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let src  = CGImageSourceCreateWithData(data as CFData, nil),
              let img  = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        return img
    }
}

/// サムネイル一覧＋選択ビュー
struct ThumbnailDeleteGridView: View {
    @Binding var imageURLs: [URL]    // サムネイル画像ファイルの URL 一覧
    @Binding var selectedURL: URL?   // 選択中の画像 URL
    
    // Adaptive サイズのカラムレイアウト
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(imageURLs, id: \.self) { url in
                    if let cg = loadCGImage(from: url) {
                        Button {
                            selectedURL = url
                        } label: {
                            Image(decorative: cg, scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipped()
                                .overlay(
                                    // 選択中はアクセントカラーで枠線
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(selectedURL == url
                                                ? Color.red
                                                : Color.clear,
                                                lineWidth: 4
                                               )
                                )
                        }
                        .buttonStyle(.plain) // フォーカス可能に
                    }
                }
            }
            .padding()
        }
    }
    
    /// URL から CGImage を生成
    private func loadCGImage(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let src  = CGImageSourceCreateWithData(data as CFData, nil),
              let img  = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        return img
    }
}

#Preview(windowStyle: .automatic) {
    ExternalStrokeView()
        .environmentObject(AppModel())
}
