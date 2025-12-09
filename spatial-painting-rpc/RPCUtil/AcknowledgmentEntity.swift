//
//  AcknowledgmentEntity.swift
//  spatial-painting-rpc
//
//  Created for RPC retry mechanism
//

import Foundation

/// RPC acknowledgment entity for tracking successful request completion
struct AcknowledgmentEntity: RPCEntity {
    enum Method: RPCEntityMethod {
        case ack
    }
    
    enum Param: RPCEntityParam {
        case ack(AckParam)
        
        /// カスタムエンコード
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .ack(let param):
                try container.encode(param, forKey: .ack)
            }
        }
        
        /// カスタムデコード
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let param = try? container.decode(AckParam.self, forKey: .ack) {
                self = .ack(param)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.ack, in: container, debugDescription: "Invalid parameter type")
            }
        }
        
        /// カスタムエンコード/デコードのための Key
        enum CodingKeys: String, CodingKey {
            case ack
        }
    }
}

/// Acknowledgment parameter containing the original request ID
struct AckParam: Codable {
    /// The ID of the request being acknowledged
    let requestId: UUID
}
