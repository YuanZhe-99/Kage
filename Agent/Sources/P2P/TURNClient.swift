import Foundation
import Network

protocol TURNClientDelegate: AnyObject {
    func turnClient(_ client: TURNClient, didAllocateRelay address: NWEndpoint)
    func turnClient(_ client: TURNClient, didEncounterError error: Error)
}

class TURNClient {
    weak var delegate: TURNClientDelegate?

    private let serverURL: URL
    private let credentials: TURNCredentials
    private var connection: NWConnection?
    private var relayEndpoint: NWEndpoint?

    init(serverURL: URL, credentials: TURNCredentials) {
        self.serverURL = serverURL
        self.credentials = credentials
    }

    func allocateRelay() async throws -> NWEndpoint {
        let params = NWParameters.udp
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(serverURL.host ?? ""),
            port: NWEndpoint.Port(rawValue: UInt16(serverURL.port ?? 3478)) ?? .init(rawValue: 3478)!
        )

        let connection = NWConnection(to: endpoint, using: params)
        self.connection = connection

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let relayEndpoint = NWEndpoint.hostPort(
                        host: NWEndpoint.Host(self.serverURL.host ?? ""),
                        port: NWEndpoint.Port(rawValue: 443) ?? .init(rawValue: 443)!
                    )
                    self.relayEndpoint = relayEndpoint
                    self.delegate?.turnClient(self, didAllocateRelay: relayEndpoint)
                    continuation.resume(returning: relayEndpoint)
                case .failed(let error):
                    self.delegate?.turnClient(self, didEncounterError: error)
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    func send(data: Data) async throws {
        guard let connection = connection else {
            throw TURNError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receive() async throws -> Data {
        guard let connection = connection else {
            throw TURNError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: TURNError.noDataReceived)
                }
            }
        }
    }

    func refresh() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func deallocate() {
        connection?.cancel()
        connection = nil
        relayEndpoint = nil
    }
}

struct TURNCredentials {
    let username: String
    let password: String
    let realm: String

    init(username: String, password: String, realm: String = "kage") {
        self.username = username
        self.password = password
        self.realm = realm
    }
}

enum TURNError: LocalizedError {
    case notConnected
    case allocationFailed
    case authenticationFailed
    case noDataReceived

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "TURN client is not connected"
        case .allocationFailed:
            return "Failed to allocate relay address"
        case .authenticationFailed:
            return "TURN authentication failed"
        case .noDataReceived:
            return "No data received from TURN server"
        }
    }
}
