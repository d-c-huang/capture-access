import CoreGraphics

public enum CaptureImageValidation {
    /// Inspect alpha at the original resolution so tiny visible details are not
    /// lost by downsampling. RGB values alone cannot identify an empty image.
    public static func isFullyTransparent(_ image: CGImage) throws -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else {
            throw CaptureFailure.imageValidation
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let alpha = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            for x in 0..<image.width where alpha[y * context.bytesPerRow + x * 2 + 1] != 0 {
                return false
            }
        }
        return true
    }
}
