import Foundation
import Security

class KeyManager {
    static let shared = KeyManager()

    private let keyTag = "com.kage.contexthelper.keys.signing"
    private let keychainService = "com.kage.contexthelper"

    private init() {}

    func generateKeyPair() throws -> (publicKey: Data, privateKey: Data) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyManagerError.publicKeyExtractionFailed
        }

        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }

        return (publicKey: publicKeyData, privateKey: privateKeyData)
    }

    func getPrivateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            throw KeyManagerError.keyNotFound
        }

        return item as! SecKey
    }

    func deleteKeyPair() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.deletionFailed(status)
        }
    }

    func sign(data: Data) throws -> Data {
        let privateKey = try getPrivateKey()

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw error!.takeRetainedValue() as Error
        }

        return signature
    }

    func verify(signature: Data, for data: Data, publicKey: SecKey) -> Bool {
        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            signature as CFData,
            &error
        )

        return result
    }

    func storeInSecureEnclave(data: Data, identifier: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.storageFailed(status)
        }
    }

    func retrieveFromSecureEnclave(identifier: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyManagerError.retrievalFailed(status)
        }

        return data
    }
}

enum KeyManagerError: LocalizedError {
    case publicKeyExtractionFailed
    case keyNotFound
    case deletionFailed(OSStatus)
    case storageFailed(OSStatus)
    case retrievalFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .publicKeyExtractionFailed:
            return "Failed to extract public key from private key"
        case .keyNotFound:
            return "Private key not found in keychain"
        case .deletionFailed(let status):
            return "Failed to delete key pair: \(status)"
        case .storageFailed(let status):
            return "Failed to store data in Secure Enclave: \(status)"
        case .retrievalFailed(let status):
            return "Failed to retrieve data from Secure Enclave: \(status)"
        }
    }
}
