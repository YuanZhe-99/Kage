import Foundation

protocol DataChannelManagerDelegate: AnyObject {
    func dataChannel(_ manager: DataChannelManager, didReceiveData data: Data)
    func dataChannel(_ manager: DataChannelManager, didChangeState state: DataChannelState)
    func dataChannel(_ manager: DataChannelManager, didEncounterError error: Error)
}

enum DataChannelState {
    case disconnected
    case connecting
    case connected
    case closing
    case closed
}

class DataChannelManager {
    weak var delegate: DataChannelManagerDelegate?

    private var channel: Any?
    private var state: DataChannelState = .disconnected

    var isConnected: Bool {
        return state == .connected
    }

    var bufferedAmount: Int {
        return 0
    }

    func connect(to url: URL, with config: DataChannelConfig) async throws {
        state = .connecting
        delegate?.dataChannel(self, didChangeState: state)

        try await Task.sleep(nanoseconds: 1_000_000_000)

        state = .connected
        delegate?.dataChannel(self, didChangeState: state)
    }

    func disconnect() {
        state = .closing
        delegate?.dataChannel(self, didChangeState: state)

        state = .closed
        delegate?.dataChannel(self, didChangeState: state)

        state = .disconnected
        delegate?.dataChannel(self, didChangeState: state)
    }

    func send(data: Data) async throws {
        guard state == .connected else {
            throw DataChannelError.notConnected
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }

    func send(message: DataChannelMessage) async throws {
        let data = try JSONEncoder().encode(message)
        try await send(data: data)
    }

    func setBufferedAmountLowThreshold(_ threshold: Int) {
    }
}

struct DataChannelConfig: Codable {
    let ordered: Bool
    let maxRetransmits: Int?
    let maxPacketLifeTime: Int?
    let proto: String?

    init(ordered: Bool = true, maxRetransmits: Int? = nil, maxPacketLifeTime: Int? = nil, proto: String? = nil) {
        self.ordered = ordered
        self.maxRetransmits = maxRetransmits
        self.maxPacketLifeTime = maxPacketLifeTime
        self.proto = proto
    }
}

struct DataChannelMessage: Codable {
    let type: MessageType
    let payload: Data
    let timestamp: Date

    enum MessageType: String, Codable {
        case videoFrame
        case inputEvent
        case controlCommand
        case heartbeat
    }
}

enum DataChannelError: LocalizedError {
    case notConnected
    case sendFailed(Error)
    case receiveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Data channel is not connected"
        case .sendFailed(let error):
            return "Failed to send data: \(error.localizedDescription)"
        case .receiveFailed(let error):
            return "Failed to receive data: \(error.localizedDescription)"
        }
    }
}
