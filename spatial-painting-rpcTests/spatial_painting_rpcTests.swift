//
//  spatial_painting_rpcTests.swift
//  spatial-painting-rpcTests
//
//  Created by blueken on 2025/05/12.
//

import Testing
import Foundation
@testable import spatial_painting_rpc

struct spatial_painting_rpcTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

@MainActor
struct RequestQueueTests {
    
    @Test func testEnqueueDequeue() async throws {
        let queue = RequestQueue(timeout: 5.0, maxRetries: 3)
        
        let request = RequestSchema(
            peerId: 1,
            method: .error,
            param: .error(ErrorParam(errorMessage: "test"))
        )
        
        // Test enqueue
        queue.enqueue(request)
        #expect(queue.contains(request.id))
        #expect(queue.count == 1)
        
        // Test dequeue
        queue.dequeue(request.id)
        #expect(!queue.contains(request.id))
        #expect(queue.count == 0)
    }
    
    @Test func testClear() async throws {
        let queue = RequestQueue(timeout: 5.0, maxRetries: 3)
        
        // Add multiple requests
        for i in 0..<5 {
            let request = RequestSchema(
                peerId: i,
                method: .error,
                param: .error(ErrorParam(errorMessage: "test \(i)"))
            )
            queue.enqueue(request)
        }
        
        #expect(queue.count == 5)
        
        // Clear all
        queue.clear()
        #expect(queue.count == 0)
    }
}

@MainActor
struct AcknowledgmentEntityTests {
    
    @Test func testAckParamCoding() async throws {
        let requestId = UUID()
        let param = AckParam(requestId: requestId)
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(param)
        #expect(!data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AckParam.self, from: data)
        #expect(decoded.requestId == requestId)
    }
    
    @Test func testAcknowledgmentEntityParamCoding() async throws {
        let requestId = UUID()
        let param = AcknowledgmentEntity.Param.ack(AckParam(requestId: requestId))
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(param)
        #expect(!data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AcknowledgmentEntity.Param.self, from: data)
        
        if case let .ack(ackParam) = decoded {
            #expect(ackParam.requestId == requestId)
        } else {
            Issue.record("Failed to decode acknowledgment param")
        }
    }
}

@MainActor
struct RPCModelAcknowledgmentTests {
    
    @Test func testRequestSchemaCodingWithAck() async throws {
        let requestId = UUID()
        let request = RequestSchema(
            id: requestId,
            peerId: 123,
            method: .acknowledgment(.ack),
            param: .acknowledgment(.ack(AckParam(requestId: requestId)))
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        #expect(!data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RequestSchema.self, from: data)
        
        #expect(decoded.id == requestId)
        #expect(decoded.peerId == 123)
        
        // Verify method and param
        if case .acknowledgment(.ack) = decoded.method,
           case let .acknowledgment(.ack(ackParam)) = decoded.param {
            #expect(ackParam.requestId == requestId)
        } else {
            Issue.record("Failed to decode request with acknowledgment")
        }
    }
}
