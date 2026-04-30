import Foundation

protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didReceiveOffer offer: Data, from deviceId: String)
    func signalingClient(_ client: SignalingClient, didReceiveAnswer answer: Data, from deviceId: String)
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: Data, from deviceId: String)
    func signalingClient(_ client: SignalingClient, didEncounterError error: Error)
}

class SignalingClient {
    weak var delegate: SignalingClientDelegate?

    private let serverURL: URL
    private let urlSession: URLSession
    private var heartbeatTimer: Timer?

    init(serverURL: URL) {
        self.serverURL = serverURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
    }

    func register(deviceId: String, publicKey: Data, natType: String) async throws {
        let payload: [String: Any] = [
            "uuid": deviceId,
            "public_key": publicKey.base64EncodedString(),
            "nat_type": natType
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let encodedPayload = payloadData.base64EncodedString()

        let message: [String: Any] = [
            "type": "register",
            "device_id": deviceId,
            "payload": encodedPayload,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let encodedMessage = messageData.base64EncodedString()

        let request = createChatCompletionRequest(content: encodedMessage)
        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SignalingError.registrationFailed
        }
    }

    func sendOffer(_ offer: Data, to targetId: String, from deviceId: String) async throws {
        let payload: [String: Any] = [
            "sdp": offer.base64EncodedString(),
            "type": "offer"
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let encodedPayload = payloadData.base64EncodedString()

        let message: [String: Any] = [
            "type": "offer",
            "device_id": deviceId,
            "target_id": targetId,
            "payload": encodedPayload,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let encodedMessage = messageData.base64EncodedString()

        let request = createChatCompletionRequest(content: encodedMessage)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SignalingError.offerFailed
        }

        try await processResponse(data: data)
    }

    func sendAnswer(_ answer: Data, to targetId: String, from deviceId: String) async throws {
        let payload: [String: Any] = [
            "sdp": answer.base64EncodedString(),
            "type": "answer"
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let encodedPayload = payloadData.base64EncodedString()

        let message: [String: Any] = [
            "type": "answer",
            "device_id": deviceId,
            "target_id": targetId,
            "payload": encodedPayload,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let encodedMessage = messageData.base64EncodedString()

        let request = createChatCompletionRequest(content: encodedMessage)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SignalingError.answerFailed
        }

        try await processResponse(data: data)
    }

    func sendCandidate(_ candidate: Data, to targetId: String, from deviceId: String) async throws {
        let payload: [String: Any] = [
            "candidate": candidate.base64EncodedString()
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let encodedPayload = payloadData.base64EncodedString()

        let message: [String: Any] = [
            "type": "candidate",
            "device_id": deviceId,
            "target_id": targetId,
            "payload": encodedPayload,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let encodedMessage = messageData.base64EncodedString()

        let request = createChatCompletionRequest(content: encodedMessage)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SignalingError.candidateFailed
        }

        try await processResponse(data: data)
    }

    func startHeartbeat(deviceId: String) {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                try? await self?.sendHeartbeat(deviceId: deviceId)
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendHeartbeat(deviceId: String) async throws {
        let message: [String: Any] = [
            "type": "heartbeat",
            "device_id": deviceId,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]

        let messageData = try JSONSerialization.data(withJSONObject: message)
        let encodedMessage = messageData.base64EncodedString()

        let request = createChatCompletionRequest(content: encodedMessage)
        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SignalingError.heartbeatFailed
        }
    }

    private func createChatCompletionRequest(content: String) -> URLRequest {
        let endpoint = serverURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer dummy-key", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": content]
            ],
            "stream": false
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func processResponse(data: Data) async throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return
        }

        guard let decodedData = Data(base64Encoded: content),
              let response = try JSONSerialization.jsonObject(with: decodedData) as? [String: Any],
              let type = response["type"] as? String else {
            return
        }

        switch type {
        case "offer":
            if let payload = response["payload"] as? String,
               let payloadData = Data(base64Encoded: payload),
               let deviceId = response["device_id"] as? String {
                delegate?.signalingClient(self, didReceiveOffer: payloadData, from: deviceId)
            }
        case "answer":
            if let payload = response["payload"] as? String,
               let payloadData = Data(base64Encoded: payload),
               let deviceId = response["device_id"] as? String {
                delegate?.signalingClient(self, didReceiveAnswer: payloadData, from: deviceId)
            }
        case "candidate":
            if let payload = response["payload"] as? String,
               let payloadData = Data(base64Encoded: payload),
               let deviceId = response["device_id"] as? String {
                delegate?.signalingClient(self, didReceiveCandidate: payloadData, from: deviceId)
            }
        default:
            break
        }
    }
}

enum SignalingError: LocalizedError {
    case registrationFailed
    case offerFailed
    case answerFailed
    case candidateFailed
    case heartbeatFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Device registration failed"
        case .offerFailed:
            return "Failed to send offer"
        case .answerFailed:
            return "Failed to send answer"
        case .candidateFailed:
            return "Failed to send ICE candidate"
        case .heartbeatFailed:
            return "Heartbeat failed"
        }
    }
}
