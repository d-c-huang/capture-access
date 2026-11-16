import CoreGraphics

/// Handle names use a top-left origin: increasing Y moves toward the bottom.
public enum RegionSelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Editable selection geometry in the displayed image's flipped coordinates.
/// Invalid bounds or selection rectangles return `.zero`; invalid movement or
/// minimum-size values leave the valid, contained selection unchanged.
public enum RegionSelectionGeometry {
    /// Creates a selection in any drag direction, limited to the image bounds.
    /// Clicks and drags smaller than two displayed points are not selections.
    public static func rect(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect? {
        guard valid(bounds), finite(start), finite(end) else { return nil }
        let a = clamped(start, in: bounds)
        let b = clamped(end, in: bounds)
        let result = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                            width: abs(b.x - a.x), height: abs(b.y - a.y))
        return result.width >= 2 && result.height >= 2 ? result : nil
    }

    /// Moves without changing size when the rectangle fits inside the bounds.
    /// A previously off-image rectangle is first fitted to the image, so an
    /// oversized or stale selection cannot escape the current image bounds.
    public static func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        guard let original = contained(rect, in: bounds) else { return .zero }
        guard delta.width.isFinite, delta.height.isFinite else { return original }
        return CGRect(x: clamp(original.minX + delta.width, bounds.minX, bounds.maxX - original.width),
                      y: clamp(original.minY + delta.height, bounds.minY, bounds.maxY - original.height),
                      width: original.width, height: original.height)
    }

    /// Resizes only the handle's edges, keeping the opposite edges anchored.
    /// Crossing the opposite edge stops at the minimum instead of flipping.
    /// If an image edge leaves less space than minimumSize, available space is
    /// the minimum; the anchored edge is never moved to enlarge that space.
    public static func resized(_ rect: CGRect, handle: RegionSelectionHandle, by delta: CGSize,
                               in bounds: CGRect, minimumSize: CGFloat = 2) -> CGRect {
        guard let original = contained(rect, in: bounds) else { return .zero }
        guard delta.width.isFinite, delta.height.isFinite,
              minimumSize.isFinite, minimumSize > 0 else { return original }
        var left = original.minX, top = original.minY
        var right = original.maxX, bottom = original.maxY
        switch handle {
        case .topLeft, .left, .bottomLeft:
            let minimum = min(minimumSize, right - bounds.minX)
            left = clamp(left + delta.width, bounds.minX, right - minimum)
        case .topRight, .right, .bottomRight:
            let minimum = min(minimumSize, bounds.maxX - left)
            right = clamp(right + delta.width, left + minimum, bounds.maxX)
        case .top, .bottom:
            break
        }
        switch handle {
        case .topLeft, .top, .topRight:
            let minimum = min(minimumSize, bottom - bounds.minY)
            top = clamp(top + delta.height, bounds.minY, bottom - minimum)
        case .bottomLeft, .bottom, .bottomRight:
            let minimum = min(minimumSize, bounds.maxY - top)
            bottom = clamp(bottom + delta.height, top + minimum, bounds.maxY)
        case .left, .right:
            break
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func contained(_ rect: CGRect, in bounds: CGRect) -> CGRect? {
        guard valid(rect), valid(bounds) else { return nil }
        let width = min(rect.width, bounds.width), height = min(rect.height, bounds.height)
        return CGRect(x: clamp(rect.minX, bounds.minX, bounds.maxX - width),
                      y: clamp(rect.minY, bounds.minY, bounds.maxY - height),
                      width: width, height: height)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
         rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.size.width > 0 && rect.size.height > 0
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }

    private static func clamped(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: clamp(point.x, bounds.minX, bounds.maxX),
                y: clamp(point.y, bounds.minY, bounds.maxY))
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
