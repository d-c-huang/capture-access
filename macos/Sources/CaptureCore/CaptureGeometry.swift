import CoreGraphics
import Foundation

public enum CaptureFailure: LocalizedError {
    case invalidSize
    case pngEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidSize: return "���ڳߴ���Ч����ȷ�ϴ����Կɼ���Ȼ������ѡ��"
        case .pngEncoding: return "�޷����� PNG ͼƬ�������½�ͼ��"
        }
    }
}

public struct CaptureSize: Equatable {
    public let width: Int
    public let height: Int
    public let wasReduced: Bool

    /// Bound the allocation while preserving the window's aspect ratio.
    public static func calculate(points: CGSize, scale: CGFloat) throws -> CaptureSize {
        let w = points.width * scale
        let h = points.height * scale
        guard points.width > 0, points.height > 0, scale > 0,
              w.isFinite, h.isFinite, w > 0, h > 0 else {
            throw CaptureFailure.invalidSize
        }
        let maxDimension: CGFloat = 16_384
        let maxPixels: CGFloat = 32_000_000
        // Divide before multiplying, so extraordinarily large inputs don't overflow.
        let dimensionFactor = min(1, maxDimension / w, maxDimension / h)
        let boundedWidth = w * dimensionFactor
        let boundedHeight = h * dimensionFactor
        let areaFactor = min(1, sqrt(maxPixels / (boundedWidth * boundedHeight)))
        let factor = dimensionFactor * areaFactor
        return CaptureSize(
            width: max(1, Int(floor(w * factor))),
            height: max(1, Int(floor(h * factor))),
            wasReduced: factor < 1
        )
    }
}
