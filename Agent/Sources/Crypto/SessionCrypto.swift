import Foundation
import CryptoKit

class SessionCrypto {
    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    private var sharedSecret: SharedSecret?
    private var symmetricKey: SymmetricKey?

    var publicKey: Data? {
        return privateKey?.rawRepresentation
    }

    init() {
        generateKeyPair()
    }

    func generateKeyPair() {
        privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    func computeSharedSecret(remotePublicKey: Data) throws {
        guard let privateKey = privateKey else {
            throw SessionCryptoError.noLocalKey
        }

        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remotePublicKey)
        sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: remoteKey)
    }

    func deriveSymmetricKey(salt: Data) throws {
        guard let sharedSecret = sharedSecret else {
            throw SessionCryptoError.noSharedSecret
        }

        let saltData = SymmetricKey(data: salt)
        symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: saltData,
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }

    func encrypt(_ data: Data) throws -> EncryptedData {
        guard let key = symmetricKey else {
            throw SessionCryptoError.noSymmetricKey
        }

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        return EncryptedData(
            ciphertext: sealedBox.ciphertext,
            nonce: Data(nonce),
            tag: sealedBox.tag
        )
    }

    func decrypt(_ encryptedData: EncryptedData) throws -> Data {
        guard let key = symmetricKey else {
            throw SessionCryptoError.noSymmetricKey
        }

        let nonce = try AES.GCM.Nonce(data: encryptedData.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedData.ciphertext,
            tag: encryptedData.tag
        )

        return try AES.GCM.open(sealedBox, using: key)
    }

    func generateSalt() -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return salt
    }
}

struct EncryptedData {
    let ciphertext: Data
    let nonce: Data
    let tag: Data

    var combined: Data {
        var result = Data()
        result.append(nonce)
        result.append(ciphertext)
        result.append(tag)
        return result
    }

    init(ciphertext: Data, nonce: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
    }

    init(combined: Data) throws {
        guard combined.count >= 28 else {
            throw SessionCryptoError.invalidEncryptedData
        }

        self.nonce = combined.prefix(12)
        self.tag = combined.suffix(16)
        self.ciphertext = combined.dropFirst(12).dropLast(16)
    }
}

enum SessionCryptoError: LocalizedError {
    case noLocalKey
    case noSharedSecret
    case noSymmetricKey
    case invalidEncryptedData

    var errorDescription: String? {
        switch self {
        case .noLocalKey:
            return "Local key pair not generated"
        case .noSharedSecret:
            return "Shared secret not computed"
        case .noSymmetricKey:
            return "Symmetric key not derived"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        }
    }
}
