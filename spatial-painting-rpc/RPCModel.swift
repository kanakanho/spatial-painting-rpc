//
//  Entities.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/12.
//

import Foundation
import simd
import MultipeerConnectivity
import Combine

/// PRC の Method として Entity を定義
enum Method: Codable {
    case error(ErrorEntitiy.Method)
    case coordinateTransformEntity(CoordinateTransformEntity.Method)
    case paintingEntity(PaintingEntity.Method)
}

/// PRC の Param として Entity を定義
enum Param: Codable {
    case error(ErrorEntitiy.Param)
    case coordinateTransformEntity(CoordinateTransformEntity.Param)
    case paintingEntity(PaintingEntity.Param)
    
    /// カスタムエンコード
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .error(let param):
            try container.encode(param, forKey: .error)
        case .coordinateTransformEntity(let param):
            try container.encode(param, forKey: .coordinateTransformEntity)
        case .paintingEntity(let param):
            try container.encode(param, forKey: .paintingEntity)
        }
    }
    
    /// カスタムデコード
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let param = try? container.decode(ErrorEntitiy.Param.self, forKey: .error) {
            self = .error(param)
        } else if let param = try? container.decode(CoordinateTransformEntity.Param.self, forKey: .coordinateTransformEntity) {
            self = .coordinateTransformEntity(param)
        } else if let param = try? container.decode(PaintingEntity.Param.self, forKey: .paintingEntity) {
            self = .paintingEntity(param)
        } else {
            throw DecodingError.dataCorruptedError(forKey: CodingKeys.error, in: container, debugDescription: "Invalid parameter type")
        }
    }
    
    /// カスタムエンコード/デコードのための Key
    private enum CodingKeys: String, CodingKey {
        case error
        case coordinateTransformEntity
        case paintingEntity
    }
}

/// 型安全な RequestSchema
struct RequestSchema: Codable {
    /// 通信の一意な id
    let id: UUID
    /// 通信元の Peer の一意な id
    let peerId: Int
    /// RPC のメソッド
    let method: Method
    /// RPC のメソッドの引数
    let param: Param
    
    /// カスタムデコード
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.peerId = try container.decode(Int.self, forKey: .peerId)
        self.method = try container.decode(Method.self, forKey: .method)
        self.param = try container.decode(Param.self, forKey: .param)
    }
    
    init(id: UUID, peerId: Int, method: Method, param: Param) {
        self.id = id
        self.peerId = peerId
        self.method = method
        self.param = param
    }
    
    init(id: UUID, peerId: Int, method: CoordinateTransformEntity.Method, param: CoordinateTransformEntity.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .coordinateTransformEntity(method)
        self.param = .coordinateTransformEntity(param)
    }
    
    init(peerId: Int, method: CoordinateTransformEntity.Method, param: CoordinateTransformEntity.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .coordinateTransformEntity(method)
        self.param = .coordinateTransformEntity(param)
    }
    
    init(id: UUID, peerId: Int, method: ErrorEntitiy.Method, param: ErrorEntitiy.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .error(method)
        self.param = .error(param)
    }
    
    init(peerId: Int, method: ErrorEntitiy.Method, param: ErrorEntitiy.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .error(method)
        self.param = .error(param)
    }
    
    init(id: UUID, peerId: Int, method: PaintingEntity.Method, param: PaintingEntity.Param) {
        self.id = id
        self.peerId = peerId
        self.method = .paintingEntity(method)
        self.param = .paintingEntity(param)
    }
    
    init(peerId: Int, method: PaintingEntity.Method, param: PaintingEntity.Param) {
        self.id = UUID()
        self.peerId = peerId
        self.method = .paintingEntity(method)
        self.param = .paintingEntity(param)
    }
    
    /// カスタムエンコード
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(peerId, forKey: .peerId)
        try container.encode(method, forKey: .method)
        try container.encode(param, forKey: .param)
    }
    
    /// カスタムエンコード/デコードのための Key
    private enum CodingKeys: String, CodingKey {
        case id
        case peerId
        case method
        case param
    }
}

/// RPC に関連するメソッドの共通の返り値
struct RPCResult {
    /// 成功したかどうか
    let success: Bool
    /// エラーメッセージ
    let errorMessage: String
    
    /// 成功した場合
    init() {
        self.success = true
        self.errorMessage = ""
    }
    
    /// 失敗した場合
    init(_ errorMessage: String) {
        self.success = false
        self.errorMessage = errorMessage
    }
}

/// RPCを管理するクラス
/// このクラスの中で利用できるメソッドのみ、RPCでの呼び出しが可能
/// - Warning: このクラスの中以外のメソッドを呼び出すためにRPCを利用してはいけません
@MainActor
class RPCModel: ObservableObject {
    /// 送信するデータ
    private var sendExchangeDataWrapper = ExchangeDataWrapper()
    /// 受信したデータ
    private var receiveExchangeDataWrapper = ExchangeDataWrapper()
    
    /// 変更を検知して発火させる
    private var cancellable: AnyCancellable?
    
    var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()
    
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    
    init(sendExchangeDataWrapper: ExchangeDataWrapper, receiveExchangeDataWrapper: ExchangeDataWrapper, mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper) {
        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        cancellable = receiveExchangeDataWrapper.$exchangeData.sink { [weak self] exchangeData in
            self?.receiveExchangeDataDidChange(exchangeData)
        }
    }
    
    func receiveExchangeDataDidChange(_ exchangeData: ExchangeData) {
        guard let request = try? jsonDecoder.decode(RequestSchema.self, from: exchangeData.data) else {
            print("Failed to decode request")
            return
        }
        
        _ = receiveRequest(request)
    }
    
    @Published var coordinateTransforms = CoordinateTransforms()
    @Published var painting = Painting()
    
    /// RPC の実行と RPC リクエストの送信
    ///
    /// - Note: このメソッドでは、全ての Peer と共通化して実行したいメソッドを呼び出します
    ///
    /// - Parameters: request: `RequestSchema`
    /// - Returns: `RPCResult`
    func sendRequest(_ request: RequestSchema) -> RPCResult {
//        print("sendRequest")
//        print("sendMethod: \(request.method)")
//        print("sendParam: \(request.param)")
        
        var rpcResult = RPCResult()
        switch (request.method, request.param) {
        case let (.coordinateTransformEntity(.requestTransform),.coordinateTransformEntity(.requestTransform(p))):
            rpcResult = coordinateTransforms.requestTransform(param: p)
        case let (.coordinateTransformEntity(.setTransform),.coordinateTransformEntity(.setTransform(p))):
            rpcResult = coordinateTransforms.setTransform(param: p)
        case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
            rpcResult = coordinateTransforms.setState(param: p)
        case let (.paintingEntity(.finishStroke),.paintingEntity(.finishStroke(p))):
            painting.finishStroke(param: p)
        case let
            (.paintingEntity(.setStrokeColor),.paintingEntity(.setStrokeColor(p))):
            painting.setStrokeColor(param: p)
        case (.paintingEntity(.removeAllStroke),.paintingEntity(.removeAllStroke(_))):
            painting.removeAllStroke()
        case let
            (.paintingEntity(.removeStroke),.paintingEntity(.removeStroke(p))):
            painting.removeStroke(param: p)
        case let (.paintingEntity(.changeFingerLineWidth),.paintingEntity(.changeFingerLineWidth(p))):
            painting.changeFingerLineWidth(param: p)
        case let (.paintingEntity(.finishControlPoint), .paintingEntity(.finishControlPoint(p))):
            painting.finishControlPoint(param: p)
        default:
            return RPCResult("Invalid request")
        }
        // リクエストを送信
        guard let requestData = try? jsonEncoder.encode(request) else {
            return RPCResult("Failed to encode request")
        }
        sendExchangeDataWrapper.setData(requestData)
        return rpcResult
    }
    
    /// RPC の実行と RPC リクエストの送信
    ///
    /// - Note: このメソッドでは、全ての Peer と共通化して実行したいメソッドを呼び出します
    ///
    /// - Parameters:
    ///     - request: `RequestSchema`
    ///         - peerId: `Int`
    /// - Returns: `RPCResult`
    func sendRequest(_ request: RequestSchema, mcPeerId: Int) -> RPCResult {
//        print("sendRequest")
//        print("sendMethod: \(request.method)")
//        print("sendParam: \(request.param)")
        
        var rpcResult = RPCResult()
        switch (request.method, request.param) {
        case let (.coordinateTransformEntity(.requestTransform),.coordinateTransformEntity(.requestTransform(p))):
            rpcResult = coordinateTransforms.requestTransform(param: p)
        case let (.coordinateTransformEntity(.setTransform),.coordinateTransformEntity(.setTransform(p))):
            rpcResult = coordinateTransforms.setTransform(param: p)
        case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
            rpcResult = coordinateTransforms.setState(param: p)
        case (.paintingEntity(.addStrokePoint),.paintingEntity(.addStrokePoint(_))):
            // 自身に対して追加操作を行わない
            break
        case (.paintingEntity(.addStrokes),.paintingEntity(.addStrokes(_))):
            // 自身に対して追加操作を行わない
            break
        case let
            (.paintingEntity(.setStrokeColor),.paintingEntity(.setStrokeColor(p))):
            painting.setStrokeColor(param: p)
        case let (.paintingEntity(.moveControlPoint), .paintingEntity(.moveControlPoint(p))):
            painting.moveControlPoint(param: p)
        default:
            return RPCResult("Invalid request")
        }
        // リクエストを送信
        guard let requestData = try? jsonEncoder.encode(request) else {
            return RPCResult("Failed to encode request")
        }
        sendExchangeDataWrapper.setData(requestData, to: mcPeerId)
        return rpcResult
    }
    
    /// 受信した RPC の実行
    /// - Parameters: request: `RequestSchema`
    /// - Returns: `RPCResult`
    func receiveRequest(_ request: RequestSchema) -> RPCResult {
//        print("receiveRequest")
//        print("ReceiveMethod: \(request.method)")
//        print("ReceiveParam \(request.param)")
        
        var rpcResult = RPCResult()
        switch (request.method, request.param) {
        case let (.coordinateTransformEntity(.requestTransform),.coordinateTransformEntity(.requestTransform(p))):
            rpcResult = coordinateTransforms.requestTransform(param: p)
        case let (.coordinateTransformEntity(.setTransform),.coordinateTransformEntity(.setTransform(p))):
            rpcResult = coordinateTransforms.setTransform(param: p)
        case let (.coordinateTransformEntity(.setState), .coordinateTransformEntity(.setState(p))):
            rpcResult = coordinateTransforms.setState(param: p)
        case let (.paintingEntity(.addStrokePoint),.paintingEntity(.addStrokePoint(p))):
            painting.addStrokePoint(param: p)
        case let (.paintingEntity(.finishStroke),.paintingEntity(.finishStroke(p))):
            painting.finishStroke(param: p)
        case let (.paintingEntity(.addStrokes),.paintingEntity(.addStrokes(p))):
            painting.addStrokes(param: p)
        case let
            (.paintingEntity(.setStrokeColor),.paintingEntity(.setStrokeColor(p))):
            painting.setStrokeColor(param: p)
        case (.paintingEntity(.removeAllStroke),.paintingEntity(.removeAllStroke(_))):
            painting.removeAllStroke()
        case let
            (.paintingEntity(.removeStroke),.paintingEntity(.removeStroke(p))):
            painting.removeStroke(param: p)
        case let (.paintingEntity(.changeFingerLineWidth),.paintingEntity(.changeFingerLineWidth(p))):
            painting.changeFingerLineWidth(param: p)
        case let (.paintingEntity(.moveControlPoint), .paintingEntity(.moveControlPoint(p))):
            painting.moveControlPoint(param: p)
        case let (.paintingEntity(.finishControlPoint), .paintingEntity(.finishControlPoint(p))):
            painting.finishControlPoint(param: p)
        default:
            return RPCResult("Invalid request")
        }
        if !rpcResult.success {
            return error(message: rpcResult.errorMessage, to: request.peerId)
        }
        return rpcResult
    }
    
    /// エラーを送信
    /// - Parameters:
    ///     - message: エラーメッセージ
    ///     - to peerId: 送信先の Peer の UUID
    /// - Returns: `RPCResult`
    func error(message: String, to peerId: Int) -> RPCResult {
        // エラーを送信
        let request = RequestSchema(peerId: peerId, method: .error, param: .error(ErrorParam(errorMessage: message)))
        guard let requestData = try? JSONEncoder().encode(request) else {
            return RPCResult("\"\(message)\" is not send Peer")
        }
        sendExchangeDataWrapper.setData(requestData, to: peerId)
        return RPCResult(message)
    }
}
