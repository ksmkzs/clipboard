import CryptoKit
import Foundation

enum ClipboardDedupeKey {
    private static let largeTextThreshold = 256 * 1024
    private static let sampleChunkLength = 8192

    static func text(_ text: String) -> String {
        let utf8Count = text.utf8.count
        if utf8Count <= largeTextThreshold {
            let normalized = normalizedText(text)
            return "txt:\(sha256Hex(for: Data(normalized.utf8)))"
        }

        let prefixSample = normalizedText(String(text.prefix(sampleChunkLength)))
        let suffixSample = normalizedText(String(text.suffix(sampleChunkLength)))
        let fingerprint = "\(utf8Count)|\(prefixSample)|\(suffixSample)"
        return "txt-large:\(sha256Hex(for: Data(fingerprint.utf8)))"
    }

    static func image(_ normalizedImageData: Data) -> String {
        "img:\(sha256Hex(for: normalizedImageData))"
    }

    static func forItem(_ item: ClipboardItem, imageDataLoader: (String) -> Data?) -> String? {
        if let dedupeKey = item.dedupeKey, !dedupeKey.isEmpty {
            return dedupeKey
        }

        switch item.type {
        case .text:
            guard let textContent = item.textContent else {
                return nil
            }
            return text(textContent)
        case .image:
            guard let fileName = item.imageFileName,
                  let imageData = imageDataLoader(fileName) else {
                return nil
            }
            return image(imageData)
        }
    }

    static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
