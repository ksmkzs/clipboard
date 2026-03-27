import CryptoKit
import Foundation

enum ClipboardDedupeKey {
    static func text(_ text: String) -> String {
        let normalized = normalizedText(text)
        return "txt:\(sha256Hex(for: Data(normalized.utf8)))"
    }

    static func image(_ normalizedImageData: Data) -> String {
        "img:\(sha256Hex(for: normalizedImageData))"
    }

    static func forItem(_ item: ClipboardItem, imageDataLoader: (String) -> Data?) -> String? {
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
