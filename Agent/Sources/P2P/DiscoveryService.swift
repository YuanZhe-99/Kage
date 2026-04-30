import Foundation

protocol DiscoveryServiceDelegate: AnyObject {
    func discoveryService(_ service: DiscoveryService, didDiscoverDevice device: DeviceInfo)
    func discoveryService(_ service: DiscoveryService, didLoseDevice deviceId: String)
    func discoveryService(_ service: DiscoveryService, didEncounterError error: Error)
}

class DiscoveryService {
    weak var delegate: DiscoveryServiceDelegate?

    private let signalingClient: SignalingClient
    private var knownDevices: [String: DeviceInfo] = [:]
    private var discoveryTimer: Timer?

    init(signalingClient: SignalingClient) {
        self.signalingClient = signalingClient
    }

    func startDiscovery() {
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                await self?.refreshDeviceList()
            }
        }
    }

    func stopDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    func registerDevice(deviceId: String, publicKey: Data, natType: NATType) async throws {
        try await signalingClient.register(
            deviceId: deviceId,
            publicKey: publicKey,
            natType: natType.rawValue
        )
    }

    func lookupDevice(deviceId: String) async throws -> DeviceInfo {
        try await Task.sleep(nanoseconds: 500_000_000)

        if let device = knownDevices[deviceId] {
            return device
        }

        throw DiscoveryError.deviceNotFound
    }

    func connectToDevice(deviceId: String) async throws {
        let device = try await lookupDevice(deviceId: deviceId)

        let offer = Data("offer_placeholder".utf8)
        try await signalingClient.sendOffer(offer, to: deviceId, from: device.uuid)
    }

    private func refreshDeviceList() async {
    }

    func addDevice(_ device: DeviceInfo) {
        knownDevices[device.uuid] = device
        delegate?.discoveryService(self, didDiscoverDevice: device)
    }

    func removeDevice(_ deviceId: String) {
        knownDevices.removeValue(forKey: deviceId)
        delegate?.discoveryService(self, didLoseDevice: deviceId)
    }
}

struct DeviceInfo: Codable {
    let uuid: String
    let publicKey: Data
    let natType: NATType
    let lastSeen: Date
    let isOnline: Bool

    init(uuid: String, publicKey: Data, natType: NATType = .unknown, lastSeen: Date = Date(), isOnline: Bool = true) {
        self.uuid = uuid
        self.publicKey = publicKey
        self.natType = natType
        self.lastSeen = lastSeen
        self.isOnline = isOnline
    }
}

enum DiscoveryError: LocalizedError {
    case deviceNotFound
    case connectionFailed
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Device not found"
        case .connectionFailed:
            return "Failed to connect to device"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}
