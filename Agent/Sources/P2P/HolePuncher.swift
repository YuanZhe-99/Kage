import Foundation
import Network

protocol HolePuncherDelegate: AnyObject {
    func holePuncher(_ puncher: HolePuncher, didDiscoverEndpoint endpoint: NWEndpoint)
    func holePuncher(_ puncher: HolePuncher, didEncounterError error: Error)
}

class HolePuncher {
    weak var delegate: HolePuncherDelegate?

    private var connections: [NWConnection] = []
    private var stunServers: [String] = [
        "stun.l.google.com:19302",
        "stun1.l.google.com:19302",
        "stun2.l.google.com:19302"
    ]

    private var externalEndpoint: NWEndpoint?
    private var natType: NATType = .unknown

    func detectNATType() async throws -> NATType {
        var results: [NATType] = []

        for server in stunServers {
            let result = try await probeSTUNServer(server)
            results.append(result)
        }

        let counts = Dictionary(grouping: results, by: { $0 }).mapValues { $0.count }
        natType = counts.max(by: { $0.value < $1.value })?.key ?? .unknown

        return natType
    }

    private func probeSTUNServer(_ server: String) async throws -> NATType {
        try await Task.sleep(nanoseconds: 500_000_000)

        let random = Int.random(in: 0...4)
        switch random {
        case 0: return .open
        case 1: return .fullCone
        case 2: return .restrictedCone
        case 3: return .portRestricted
        default: return .symmetric
        }
    }

    func punchHole(to remoteEndpoint: NWEndpoint, psk: Data) async throws {
        let params = NWParameters.udp
        let connection = NWConnection(to: remoteEndpoint, using: params)

        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let self = self {
                    self.externalEndpoint = remoteEndpoint
                    self.delegate?.holePuncher(self, didDiscoverEndpoint: remoteEndpoint)
                }
            case .failed(let error):
                if let self = self {
                    self.delegate?.holePuncher(self, didEncounterError: error)
                }
            default:
                break
            }
        }

        connection.start(queue: .global())
    }

    func predictPort(from observations: [Int]) -> Int? {
        guard observations.count >= 2 else { return nil }

        let diffs = zip(observations, observations.dropFirst()).map { $1 - $0 }
        let uniqueDiffs = Set(diffs)

        if uniqueDiffs.count == 1, let diff = uniqueDiffs.first {
            return observations.last! + diff
        }

        if let last = observations.last {
            return last + 1
        }

        return nil
    }

    func birthdayAttack(portRange: ClosedRange<Int>, targetIP: String, attempts: Int) async throws -> Int? {
        let ports = Array(portRange)
        let selectedPorts = ports.shuffled().prefix(min(attempts, ports.count))

        for port in selectedPorts {
            try await probePort(port, on: targetIP)
        }

        return selectedPorts.first
    }

    private func probePort(_ port: Int, on host: String) async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    func cleanup() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }
}

enum NATType: String, Codable {
    case unknown
    case open
    case fullCone
    case restrictedCone
    case portRestricted
    case symmetric

    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .open: return "Open (No NAT)"
        case .fullCone: return "Full Cone"
        case .restrictedCone: return "Restricted Cone"
        case .portRestricted: return "Port Restricted"
        case .symmetric: return "Symmetric"
        }
    }

    var p2pDifficulty: String {
        switch self {
        case .unknown: return "Unknown"
        case .open, .fullCone: return "Easy"
        case .restrictedCone, .portRestricted: return "Medium"
        case .symmetric: return "Hard"
        }
    }
}
