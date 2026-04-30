import Foundation
import IOKit

class UUIDGenerator {
    static let shared = UUIDGenerator()

    private let namespaceUUID = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
    private let salt = "kage-context-helper-2024"

    private init() {}

    func generateDeviceUUID() -> String {
        let hardwareInfo = gatherHardwareInfo()
        let combinedString = "\(hardwareInfo.macAddress)-\(hardwareInfo.boardSerial)-\(hardwareInfo.systemSerial)-\(salt)"

        guard let data = combinedString.data(using: .utf8) else {
            return UUID().uuidString
        }

        let hash = sha256(data)
        return uuidv5(namespace: namespaceUUID, hash: hash)
    }

    private func gatherHardwareInfo() -> HardwareInfo {
        let macAddress = getMACAddress() ?? "unknown"
        let boardSerial = getBoardSerialNumber() ?? "unknown"
        let systemSerial = getSystemSerialNumber() ?? "unknown"

        return HardwareInfo(
            macAddress: macAddress,
            boardSerial: boardSerial,
            systemSerial: systemSerial
        )
    }

    private func getMACAddress() -> String? {
        let matching = IOServiceMatching("IOEthernetInterface")
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }

        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            defer { IOObjectRelease(service) }

            if let macProperty = IORegistryEntrySearchCFProperty(
                service,
                kIOServicePlane,
                "IOMACAddress" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            ) as? Data {
                return macAddressString(from: macProperty)
            }
        }

        return nil
    }

    private func macAddressString(from data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private func getBoardSerialNumber() -> String? {
        return getIOPlatformProperty("IOPlatformSerialNumber")
    }

    private func getSystemSerialNumber() -> String? {
        return getIOPlatformProperty("IOPlatformSerialNumber")
    }

    private func getIOPlatformProperty(_ key: String) -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }

        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }

        defer { IOObjectRelease(service) }

        if let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
            return property.takeRetainedValue() as? String
        }

        return nil
    }

    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    private func uuidv5(namespace: UUID, hash: Data) -> String {
        var namespaceBytes = namespace.uuid
        let namespaceData = Data(bytes: &namespaceBytes, count: 16)

        var combined = namespaceData
        combined.append(hash)

        let uuidHash = sha256(combined)

        var uuidBytes = [UInt8](uuidHash.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80

        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))

        return uuid.uuidString
    }
}

private struct HardwareInfo {
    let macAddress: String
    let boardSerial: String
    let systemSerial: String
}

import CommonCrypto
