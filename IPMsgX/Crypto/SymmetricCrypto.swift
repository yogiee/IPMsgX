// IPMsgX/Crypto/SymmetricCrypto.swift
// AES-256-CBC and Blowfish-128-CBC via CommonCrypto
// Ported from CryptoManager.m:313-494

import Foundation
import CommonCrypto

enum SymmetricCrypto {

    enum Algorithm {
        case aes256
        case blowfish128
    }

    // MARK: - Encrypt

    static func encrypt(data: Data, key: Data, iv: Data, algorithm: Algorithm) -> Data? {
        let (ccAlgorithm, expectedKeySize, blockSize) = algorithmParams(algorithm)

        guard key.count == expectedKeySize else { return nil }

        let bufSize = data.count + blockSize
        var buffer = Data(count: bufSize)
        var outSize = 0

        let status = buffer.withUnsafeMutableBytes { bufPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            ccAlgorithm,
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            bufPtr.baseAddress, bufSize,
                            &outSize
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return buffer.prefix(outSize)
    }

    // MARK: - Decrypt

    static func decrypt(data: Data, key: Data, iv: Data, algorithm: Algorithm) -> Data? {
        let (ccAlgorithm, expectedKeySize, blockSize) = algorithmParams(algorithm)

        guard key.count == expectedKeySize else {
            NSLog("[CRYPTO] SymmetricDecrypt: key size mismatch — got %d, expected %d for %@", key.count, expectedKeySize, String(describing: algorithm))
            return nil
        }

        let bufSize = data.count + blockSize
        var buffer = Data(count: bufSize)
        var outSize = 0

        let status = buffer.withUnsafeMutableBytes { bufPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            ccAlgorithm,
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            bufPtr.baseAddress, bufSize,
                            &outSize
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            NSLog("[CRYPTO] CCCrypt decrypt failed: status=%d (4201=DecodeError, 4202=BufferTooSmall, 4203=AlignmentError) data=%dbytes key=%dbytes iv=%dbytes algo=%@", status, data.count, key.count, iv.count, String(describing: algorithm))
            return nil
        }
        return buffer.prefix(outSize)
    }

    // MARK: - Helpers

    private static func algorithmParams(_ algorithm: Algorithm) -> (CCAlgorithm, Int, Int) {
        switch algorithm {
        case .aes256:
            return (CCAlgorithm(kCCAlgorithmAES), kCCKeySizeAES256, kCCBlockSizeAES128)
        case .blowfish128:
            return (CCAlgorithm(kCCAlgorithmBlowfish), 16, kCCBlockSizeBlowfish)
        }
    }
}
