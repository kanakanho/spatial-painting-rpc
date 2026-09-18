//
//  Logger.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2026/02/05.
//

import Foundation
import GRDB

/// RPC ログの通信方向
enum RPCLogDirection: String, Sendable {
    case send
    case receive
    case resend
}

/// 送受信した RPC リクエストを SQLite に記録する
///
/// - Note: Documents 直下に保存するため、ファイルアプリから取り出せる
final class RPCLogger: Sendable {
    let sqlitePath: URL
    private let dbQueue: DatabaseQueue?

    /// 送受信を止めないように、エンコードと書き込みはこの直列キューで行う
    private let writeQueue = DispatchQueue(label: "spatial-painting-rpc.RPCLogger")

    private let jsonEncoder = JSONEncoder()
    private let isoFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(identifier: "Asia/Tokyo")!)

    private static let createRequestLogTableSQL =
"""
CREATE TABLE IF NOT EXISTS request_log (
    -- 行番号 (再送で同じ request_id が複数行になるため)
    seq INTEGER PRIMARY KEY AUTOINCREMENT,

    -- RequestSchema.id
    request_id TEXT NOT NULL,

    -- 'send' / 'receive' / 'resend'
    direction TEXT CHECK(direction IN ('send', 'receive', 'resend')) NOT NULL,

    -- RPC メソッド名
    method TEXT NOT NULL,

    -- RPC 引数 (JSON文字列として保存)
    param TEXT NOT NULL,

    -- 送信元の Peer (hash と UUID)
    from_peer INTEGER NOT NULL,
    from_peer_uuid TEXT,

    -- 送信先の Peer (ブロードキャストの場合は to_peer = NULL, to_peer_uuid = 'broadcast')
    to_peer INTEGER,
    to_peer_uuid TEXT,

    -- 記録日時 (UNIX 時間と JST の ISO8601)
    created_at REAL NOT NULL,
    created_at_iso TEXT NOT NULL
);
"""

    private static let insertRequestLogSQL =
"""
INSERT INTO request_log (request_id, direction, method, param, from_peer, from_peer_uuid, to_peer, to_peer_uuid, created_at, created_at_iso)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
"""

    init() {
        let documentDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        // 日本時間をString で yyyy-MM-dd_HH-mm-ss 形式で取得
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())

        sqlitePath = documentDirectory.appendingPathComponent("rpc_log_\(dateString).sqlite")

        do {
            let dbQueue = try DatabaseQueue(path: sqlitePath.path)
            try dbQueue.write { db in
                try db.execute(sql: Self.createRequestLogTableSQL)
            }
            self.dbQueue = dbQueue
            print("RPCLogger: logging to \(sqlitePath.path)")
        } catch {
            // ログが取れなくてもアプリは動かす
            print("RPCLogger: failed to initialize database: \(error)")
            self.dbQueue = nil
        }
    }

    /// リクエストを記録する
    /// - Parameters:
    ///   - direction: 通信方向
    ///   - request: 送受信した `RequestSchema`
    ///   - from: 送信元の Peer の hash
    ///   - fromUUID: 送信元の Peer の UUID (不明なら nil)
    ///   - to: 送信先の Peer の hash (ブロードキャストなら nil)
    ///   - toUUID: 送信先の Peer の UUID (不明なら nil)
    func log(direction: RPCLogDirection, request: RequestSchema, from: Int, fromUUID: UUID?, to: Int?, toUUID: UUID?) {
        guard let dbQueue else { return }

        // 時刻は呼び出し時点で確定させる
        let now = Date()

        writeQueue.async { [jsonEncoder, isoFormatStyle] in
            let paramJSON: String
            if let data = try? jsonEncoder.encode(request.param), let json = String(data: data, encoding: .utf8) {
                paramJSON = json
            } else {
                paramJSON = "{}"
            }
            let arguments: StatementArguments = [
                request.id.uuidString,
                direction.rawValue,
                String(describing: request.method),
                paramJSON,
                from,
                fromUUID?.uuidString,
                to,
                to == nil ? "broadcast" : toUUID?.uuidString,
                now.timeIntervalSince1970,
                now.formatted(isoFormatStyle),
            ]

            do {
                try dbQueue.write { db in
                    try db.execute(sql: Self.insertRequestLogSQL, arguments: arguments)
                }
            } catch {
                print("RPCLogger: failed to log request: \(error)")
            }
        }
    }
}
