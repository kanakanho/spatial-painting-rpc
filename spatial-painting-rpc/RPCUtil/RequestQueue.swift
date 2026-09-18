//
//  RequestQueue.swift
//  spatial-painting-rpc
//
//  Created for RPC retry mechanism
//

import Foundation
import Synchronization

/// RPC リクエストの送信先
enum RPCDestination: Sendable, Equatable {
    /// 全ての Peer に送信
    case broadcast
    /// 特定の Peer に送信（Peer の hash）
    case peer(Int)
}

/// A single queued request with retry tracking
struct QueuedRequest: Sendable {
    let request: RequestSchema
    let destination: RPCDestination
    var timestamp: Date
    var retryCount: Int
    let maxRetries: Int

    var shouldRetry: Bool {
        return retryCount < maxRetries
    }
}

/// Thread-safe queue for managing pending RPC requests with retry logic
///
/// - Note: 再送のタイミングの管理は呼び出し側（`RPCTransport`）が `takeRequestsToRetry()` を定期的に呼んで行う
final class RequestQueue: Sendable {
    /// Dictionary of pending requests keyed by request ID
    private let pendingRequests = Mutex<[UUID: QueuedRequest]>([:])

    /// Timeout duration for requests
    let timeout: TimeInterval

    /// Maximum retry attempts
    let maxRetries: Int

    init(timeout: TimeInterval = 1.0, maxRetries: Int = 3) {
        self.timeout = timeout
        self.maxRetries = maxRetries
    }

    /// Add a request to the queue
    func enqueue(_ request: RequestSchema, destination: RPCDestination = .broadcast) {
        let queuedRequest = QueuedRequest(
            request: request,
            destination: destination,
            timestamp: Date(),
            retryCount: 0,
            maxRetries: maxRetries
        )
        pendingRequests.withLock { $0[request.id] = queuedRequest }
    }

    /// Remove a request from the queue (called when ack is received)
    func dequeue(_ requestId: UUID) {
        _ = pendingRequests.withLock { $0.removeValue(forKey: requestId) }
    }

    /// Check if a request is in the queue
    func contains(_ requestId: UUID) -> Bool {
        pendingRequests.withLock { $0[requestId] != nil }
    }

    /// Get the number of pending requests
    var count: Int {
        pendingRequests.withLock { $0.count }
    }

    /// タイムアウトしたリクエストを取り出す
    ///
    /// 再送回数が上限に達したものはキューから削除し、それ以外は再送回数を増やして返す
    /// - Parameter now: 現在時刻
    /// - Returns: 再送するリクエスト
    func takeRequestsToRetry(now: Date = Date()) -> [QueuedRequest] {
        pendingRequests.withLock { pending in
            var requestsToRetry: [QueuedRequest] = []

            for (id, queuedRequest) in pending where now.timeIntervalSince(queuedRequest.timestamp) >= timeout {
                if queuedRequest.shouldRetry {
                    var retried = queuedRequest
                    retried.retryCount += 1
                    retried.timestamp = now
                    pending[id] = retried
                    requestsToRetry.append(retried)
                } else {
                    // Max retries reached, remove from queue
                    pending.removeValue(forKey: id)
                }
            }

            return requestsToRetry
        }
    }

    /// Clear all pending requests
    func clear() {
        pendingRequests.withLock { $0.removeAll() }
    }
}
