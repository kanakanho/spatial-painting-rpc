//
//  CoordinateTransformModel.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import Foundation
import simd

enum TransformationMatrixPreparationState: Codable {
    case initial
    case selecting
    case getTransformMatrixHost
    case getTransformMatrixClient
    case confirm
    case prepared
}

class CoordinateTransforms: ObservableObject {
    var coordinateTransformEntity: CoordinateTransformEntity = .init(state: .initial)
    /// 座標の交換を管理するフラグ
    @Published var requestTransform: Bool = false
    ///  座標を交換する回数
    @Published var matrixCount: Int = 0 {
        didSet {
            if matrixCount >= matrixCountLimit {
                coordinateTransformEntity.state = .confirm
            }
        }
    }
    ///  座標を交換する回数の上限
    var matrixCountLimit: Int = 4
    
    /// 交換元の id
    var myPeerId: Int = 0
    /// 交換先の id
    var otherPeerId: Int = 0
    /// 計算が完了したアフィン行列
    @Published var affineMatrixs: [Int: simd_float4x4] = [:]
    
    ///  初期化
    ///  座標交換の工程の1つ目
    /// - Parameter param: `InitPeerParam`
    /// - Returns: `RPCResult`
    func initMyPeer(param: InitMyPeerParam) -> RPCResult {
        // 新しく設定を始める CoordinateTransformEntity を定義
        coordinateTransformEntity = CoordinateTransformEntity(state: .initial)
        myPeerId = param.peerId
        
        return RPCResult()
    }
    
    /// 相手の PeerId を登録
    /// 座標交換の工程の2つ目
    /// - Parameter param: `InitOtherPeerParam`
    /// - Returns: `RPCResult`
    func initOtherPeer(param: InitOtherPeerParam) -> RPCResult {
        otherPeerId = param.peerId
        
        return RPCResult()
    }
    
    ///  初期化
    ///  - Parameter param: `ResetPeerParam`
    ///  - Returns: `RPCResult`
    func resetPeer(param: ResetPeerParam) -> RPCResult {
        // 初期化
        coordinateTransformEntity = CoordinateTransformEntity(state: .initial)
        otherPeerId = 0
        matrixCount = 0
        
        return RPCResult()
    }
    
    /// 座標変換行列の取得を要求
    /// - Parameter param: `RequestTransform`
    /// - Returns: `RPCResult`
    func requestTransform(param: RequestTransformParam) -> RPCResult {
        requestTransform = true
        return RPCResult()
    }
    
    func setTransform(param: SetTransformParam) -> RPCResult {
        if myPeerId == param.peerId {
            if myPeerId > otherPeerId {
                coordinateTransformEntity.A.append(param.matrix)
                matrixCount = coordinateTransformEntity.A.count
            } else {
                coordinateTransformEntity.B.append(param.matrix)
                matrixCount = coordinateTransformEntity.B.count
            }
        } else {
            if myPeerId > otherPeerId {
                coordinateTransformEntity.B.append(param.matrix)
                matrixCount = coordinateTransformEntity.B.count
            } else {
                coordinateTransformEntity.A.append(param.matrix)
                matrixCount = coordinateTransformEntity.A.count
            }
        }
        requestTransform = false
        
        return RPCResult()
    }
    
    ///  A側の Peer に座標変換行列を追加
    ///  - Parameter param: `SetATransformParam`
    ///  - Returns: `RPCResult`
    func setATransform(param: SetATransformParam) -> RPCResult {
        coordinateTransformEntity.A.append(param.A)
        return RPCResult()
    }
    
    ///  B側の Peer に座標変換行列を追加
    ///  - Parameter param: `SetBTransformParam`
    ///  - Returns: `RPCResult`
    func setBTransform(param: SetBTransformParam) -> RPCResult {
        coordinateTransformEntity.B.append(param.B)
        return RPCResult()
    }
    
    ///  座標変換行列の状態を変更
    ///  - Parameter param: `SetStateParam`
    ///  - Returns: `RPCResult`
    func setState(param: SetStateParam) -> RPCResult {
        coordinateTransformEntity.state = param.state
        return RPCResult()
    }
    
    ///  アフィン行列を計算
    ///  - Parameters:
    ///     - A: A側の座標変換行列のリスト
    ///     - B: B側の座標変換行列のリスト
    ///  - Returns: アフィン行列 `simd_float4x4`
    func calculateTransformationMatrix(A: [[[Float]]],B: [[[Float]]]) -> [[Double]] {
        let AMatrix: [[[Double]]] = A.map {
            $0.toDoubleList().transpose4x4
        }
        let BMatrix: [[[Double]]] = B.map {
            $0.toDoubleList().transpose4x4
        }
        return calcAffineMatrix(AMatrix,BMatrix)
    }
    
    ///  アフィン行列を計算
    ///  - Parameter param: `ClacAffineMatrixParam`
    ///  - Returns: `RPCResult`
    func clacAffineMatrix(param: ClacAffineMatrixParam) -> RPCResult {
        let A = coordinateTransformEntity.A
        let B = coordinateTransformEntity.B
        
        // それぞれの要素が4つ存在しなければエラーを返す
        if A.count != 4 || B.count != 4 {
            return RPCResult("座標変換行列は4つ必要です")
        }
        
        // ここで座標変換行列を計算する処理を追加
        let affineMatrix = calculateTransformationMatrix(A: A, B: B)
        coordinateTransformEntity.affineMatrixAtoB = affineMatrix.tosimd_float4x4()
        coordinateTransformEntity.affineMatrixBtoA = inverseMatrix(affineMatrix).tosimd_float4x4()
        return RPCResult()
    }
    
    func getAffineMatrixAtoB(peerId: Int) -> (simd_float4x4,Bool) {
        if coordinateTransformEntity.affineMatrixAtoB == .init() {
            return (.init(), false)
        }
        return (coordinateTransformEntity.affineMatrixAtoB, true)
    }
    
    func setAffineMatrix() {
        if  myPeerId > otherPeerId {
            affineMatrixs[otherPeerId] = coordinateTransformEntity.affineMatrixAtoB
        } else {
            affineMatrixs[otherPeerId] = coordinateTransformEntity.affineMatrixBtoA
        }
    }
    
    func getNextIndexFingerTipPosition() -> SIMD3<Float>? {
        var firstRightFingerMatrix:SIMD3<Float> = .init()
        if myPeerId < otherPeerId {
            firstRightFingerMatrix = coordinateTransformEntity.B[0].tosimd_float4x4().position
        } else {
            print("is not a host")
            return nil
        }
        
        if matrixCount == 1 {
            firstRightFingerMatrix = firstRightFingerMatrix + SIMD3<Float>(0,0.3,0)
        } else if matrixCount == 2 {
            firstRightFingerMatrix = firstRightFingerMatrix + SIMD3<Float>(0.3,0,0)
        } else if matrixCount == 3 {
            firstRightFingerMatrix = firstRightFingerMatrix + SIMD3<Float>(0,0,0.3)
        }
        
        print("firstRightFingerMatrix: \(firstRightFingerMatrix)")
        
        return firstRightFingerMatrix
    }
    
    /// 初期化地点のボールを描画するための座標を取得する関数
    /// - Returns:
    ///     - 失敗した場合に理由を与える
    ///     - 座標
    ///     - A側かどうか
    func initBallTransform() -> (RPCResult, simd_float4x4) {
        if affineMatrixs.isEmpty {
            return (RPCResult("計算し終わったアフィン行列が空です"), .init())
        }
        if myPeerId == 0 || otherPeerId == 0 {
            return (RPCResult("座標を取得するPeerが取得できません"), .init())
        }
        if coordinateTransformEntity.A.isEmpty || coordinateTransformEntity.B.isEmpty {
            return (RPCResult("座標変換行列が取得できません"), .init())
        }
        
        guard let affineMatrix =  affineMatrixs[otherPeerId] else {
            return(RPCResult("座標変換行列が取得できません"), .init())
        }
        
        var fristRightFingerPos: SIMD3<Float> = .init()
        if myPeerId > otherPeerId {
            fristRightFingerPos = coordinateTransformEntity.A[0].tosimd_float4x4().position
        } else {
            fristRightFingerPos = coordinateTransformEntity.B[0].tosimd_float4x4().position
        }
        
        let fristRightFingerMatrix = simd_float4x4(pos: fristRightFingerPos)
        
        return (
            RPCResult(),
            inverseMatrix(affineMatrix.doubleList).tosimd_float4x4() * fristRightFingerMatrix
        )
    }
}


///  座標変換処理を行う構造体
struct CoordinateTransformEntity: RPCEntity {
    /// 座標変換行列のリスト
    var A: [[[Float]]]
    /// 座標変換行列のリスト
    var B: [[[Float]]]
    /// 座標変換行列の状態
    var state: TransformationMatrixPreparationState
    /// A側の座標変換行列からB側の座標変換行列へのアフィン行列
    var affineMatrixAtoB: simd_float4x4
    /// B側の座標変換行列からA側の座標変換行列へのアフィン行列
    var affineMatrixBtoA: simd_float4x4
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.A = try container.decode([[[Float]]].self, forKey: .A)
        self.B = try container.decode([[[Float]]].self, forKey: .B)
        self.state = try container.decode(TransformationMatrixPreparationState.self, forKey: .state)
        self.affineMatrixAtoB = simd_float4x4()
        self.affineMatrixBtoA = simd_float4x4()
    }
    
    init(state: TransformationMatrixPreparationState) {
        self.A = []
        self.B = []
        self.state = state
        self.affineMatrixAtoB = .init()
        self.affineMatrixBtoA = .init()
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(A, forKey: .A)
        try container.encode(B, forKey: .B)
        try container.encode(state, forKey: .state)
    }
    
    private enum CodingKeys: CodingKey {
        case A
        case B
        case state
    }
    
    enum Method: RPCEntityMethod {
        case initMyPeer
        case initOtherPeer
        case resetPeer
        case requestTransform
        case setTransform
        case setATransform
        case setBTransform
        case clacAffineMatrix
        case setState
    }
    
    enum Param: RPCEntityParam {
        case initMyPeer(InitMyPeerParam)
        case initOtherPeer(InitOtherPeerParam)
        case resetPeer(ResetPeerParam)
        case requestTransform(RequestTransformParam)
        case setTransform(SetTransformParam)
        case setATransform(SetATransformParam)
        case setBTransform(SetBTransformParam)
        case clacAffineMatrix(ClacAffineMatrixParam)
        case setState(SetStateParam)
        
        struct InitMyPeerParam: Codable {
            /// アクセス元の peerIdHash
            let peerId: Int
        }
        
        struct InitOtherPeerParam: Codable {
            /// アクセス先の peerIdHash
            let peerId: Int
        }
        
        struct ResetPeerParam: Codable {
            /// アクセス先の peerIdHash
            // let peerId: Int
        }
        
        struct RequestTransformParam: Codable {
            /// アクセス先の peerIdHash
            // let peerId: Int
        }
        
        struct SetTransformParam: Codable {
            /// リクエスト元の peerIdHash
            let peerId: Int
            let matrix: [[Float]]
        }
        
        struct SetATransformParam: Codable {
            /// アクセス先の peerIdHash
            // let peerId: Int
            let A: [[Float]]
        }
        
        struct SetBTransformParam: Codable {
            /// アクセス先の peerIdHash
            // let peerId: Int
            let B: [[Float]]
        }
        
        struct ClacAffineMatrixParam: Codable {
            /// アクセス先の peerIdHash
            // let peerId: Int
        }
        
        struct SetStateParam: Codable {
            /// アクセス先の peerIdHash
            // let peerId: Int
            let state: TransformationMatrixPreparationState
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .initMyPeer(let param):
                try container.encode(param, forKey: .initMyPeer)
            case .initOtherPeer(let param):
                try container.encode(param, forKey: .initOtherPeer)
            case .resetPeer(let param):
                try container.encode(param, forKey: .resetPeer)
            case .requestTransform(let param):
                try container.encode(param, forKey: .requestTransform)
            case .setTransform(let param):
                try container.encode(param, forKey: .setTransform)
            case .setATransform(let param):
                try container.encode(param, forKey: .setATransform)
            case .setBTransform(let param):
                try container.encode(param, forKey: .setBTransform)
            case .clacAffineMatrix(let param):
                try container.encode(param, forKey: .clacAffineMatrix)
            case .setState(let param):
                try container.encode(param, forKey: .setState)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let param = try? container.decode(InitMyPeerParam.self, forKey: .initMyPeer) {
                self = .initMyPeer(param)
            } else if let param = try? container.decode(InitOtherPeerParam.self, forKey: .initOtherPeer) {
                self = .initOtherPeer(param)
            } else if let param = try? container.decode(ResetPeerParam.self, forKey: .resetPeer) {
                self = .resetPeer(param)
            } else if let param = try? container.decode(RequestTransformParam.self, forKey: .requestTransform) {
                self = .requestTransform(param)
            } else if let param = try? container.decode(SetTransformParam.self, forKey: .setTransform) {
                self = .setTransform(param)
            } else if let param = try? container.decode(SetATransformParam.self, forKey: .setATransform) {
                self = .setATransform(param)
            } else if let param = try? container.decode(SetBTransformParam.self, forKey: .setBTransform) {
                self = .setBTransform(param)
            } else if let param = try? container.decode(ClacAffineMatrixParam.self, forKey: .clacAffineMatrix) {
                self = .clacAffineMatrix(param)
            } else if let param = try? container.decode(SetStateParam.self, forKey: .setState) {
                self = .setState(param)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.setATransform, in: container, debugDescription: "Invalid parameter type")
            }
        }
        
        internal enum CodingKeys: CodingKey {
            case initMyPeer
            case initOtherPeer
            case resetPeer
            case requestTransform
            case setTransform
            case setATransform
            case setBTransform
            case clacAffineMatrix
            case setState
        }
    }
}

typealias InitMyPeerParam = CoordinateTransformEntity.Param.InitMyPeerParam
typealias InitOtherPeerParam = CoordinateTransformEntity.Param.InitOtherPeerParam
typealias ResetPeerParam = CoordinateTransformEntity.Param.ResetPeerParam
typealias RequestTransformParam = CoordinateTransformEntity.Param.RequestTransformParam
typealias SetTransformParam = CoordinateTransformEntity.Param.SetTransformParam
typealias SetATransformParam = CoordinateTransformEntity.Param.SetATransformParam
typealias SetBTransformParam = CoordinateTransformEntity.Param.SetBTransformParam
typealias ClacAffineMatrixParam = CoordinateTransformEntity.Param.ClacAffineMatrixParam
typealias SetStateParam = CoordinateTransformEntity.Param.SetStateParam
