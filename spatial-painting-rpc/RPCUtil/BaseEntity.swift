//
//  BaseEntity.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/14.
//

import Foundation

/// RPC で利用する Entity の基底クラス
protocol RPCEntity: Codable, Sendable {
    /// RPC で利用するメソッド
    associatedtype Method: RPCEntityMethod
    /// RPC で利用するメソッドの引数
    associatedtype Param: RPCEntityParam
}

protocol RPCEntityMethod: Codable, Sendable {}

protocol RPCEntityParam: Codable, Sendable {
    /// カスタムエンコード
    func encode(to encoder: Encoder) throws
    /// カスタムデコード
    init(from decoder: Decoder) throws
    /// カスタムエンコード/デコードのための Key
    associatedtype CodingKeys: CodingKey
}
