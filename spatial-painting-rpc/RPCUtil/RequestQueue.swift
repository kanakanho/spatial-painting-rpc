//
//  RequestQueue.swift
//  spatial-painting-rpc
//
//  Created for RPC retry mechanism
//

import Foundation

/// A single queued request with retry tracking
struct QueuedRequest {
    let request: RequestSchema
    var timestamp: Date
    var retryCount: Int
    let maxRetries: Int
    
    var shouldRetry: Bool {
        return retryCount < maxRetries
    }
}

/// Thread-safe queue for managing pending RPC requests with retry logic
@MainActor
class RequestQueue: ObservableObject {
    /// Dictionary of pending requests keyed by request ID
    private var pendingRequests: [UUID: QueuedRequest] = [:]
    
    /// Timeout duration for requests
    private let timeout: TimeInterval
    
    /// Maximum retry attempts
    private let maxRetries: Int
    
    /// Timer for periodic retry checks
    private var retryTimer: Timer?
    
    /// Callback for retrying requests
    var onRetry: ((RequestSchema) -> Void)?
    
    init(timeout: TimeInterval = 5.0, maxRetries: Int = 3) {
        self.timeout = timeout
        self.maxRetries = maxRetries
        startRetryTimer()
    }
    
    deinit {
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    /// Add a request to the queue
    func enqueue(_ request: RequestSchema) {
        let queuedRequest = QueuedRequest(
            request: request,
            timestamp: Date(),
            retryCount: 0,
            maxRetries: maxRetries
        )
        pendingRequests[request.id] = queuedRequest
    }
    
    /// Remove a request from the queue (called when ack is received)
    func dequeue(_ requestId: UUID) {
        pendingRequests.removeValue(forKey: requestId)
    }
    
    /// Check if a request is in the queue
    func contains(_ requestId: UUID) -> Bool {
        return pendingRequests[requestId] != nil
    }
    
    /// Get the number of pending requests
    var count: Int {
        return pendingRequests.count
    }
    
    /// Start the retry timer
    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForRetries()
            }
        }
    }
    
    /// Stop the retry timer
    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    /// Check for requests that need to be retried
    private func checkForRetries() {
        let now = Date()
        var requestsToRetry: [UUID] = []
        var requestsToRemove: [UUID] = []
        
        for (id, queuedRequest) in pendingRequests {
            let elapsed = now.timeIntervalSince(queuedRequest.timestamp)
            
            if elapsed >= timeout {
                if queuedRequest.shouldRetry {
                    requestsToRetry.append(id)
                } else {
                    // Max retries reached, remove from queue
                    requestsToRemove.append(id)
                    print("Request \(id) max retries reached, removing from queue")
                }
            }
        }
        
        // Remove requests that have exceeded max retries
        for id in requestsToRemove {
            pendingRequests.removeValue(forKey: id)
        }
        
        // Retry requests that have timed out
        for id in requestsToRetry {
            if var queuedRequest = pendingRequests[id] {
                queuedRequest.retryCount += 1
                queuedRequest.timestamp = now
                pendingRequests[id] = queuedRequest
                
                print("Retrying request \(id) (attempt \(queuedRequest.retryCount)/\(maxRetries))")
                onRetry?(queuedRequest.request)
            }
        }
    }
    
    /// Clear all pending requests
    func clear() {
        pendingRequests.removeAll()
    }
}
