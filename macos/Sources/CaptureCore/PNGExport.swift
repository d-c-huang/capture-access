import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PNGExport {
    public static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { throw CaptureFailure.pngEncoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureFailure.pngEncoding }
        return data as Data
    }

    public static func suggestedName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "CaptureAccess-\(formatter.string(from: date)).png"
    }
}
