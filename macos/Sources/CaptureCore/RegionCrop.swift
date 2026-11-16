import CoreGraphics

/// Maps a drag over a displayed image back to the original image pixels.
/// Both rectangles use a top-left origin, as in a flipped AppKit view.
public enum RegionCrop {
    public static func pixelRect(selection: CGRect, displayRect: CGRect, pixelSize: CGSize) -> CGRect? {
        guard finite(selection), finite(displayRect),
              displayRect.width > 0, displayRect.height > 0,
              pixelSize.width.isFinite, pixelSize.height.isFinite,
              pixelSize.width >= 1, pixelSize.height >= 1,
              pixelSize.width.rounded(.down) == pixelSize.width,
              pixelSize.height.rounded(.down) == pixelSize.height else { return nil }

        let drag = selection.standardized
        guard finite(drag), displayRect.maxX.isFinite, displayRect.maxY.isFinite,
              drag.maxX.isFinite, drag.maxY.isFinite else { return nil }
        let left = max(drag.minX, displayRect.minX)
        let top = max(drag.minY, displayRect.minY)
        let right = min(drag.maxX, displayRect.maxX)
        let bottom = min(drag.maxY, displayRect.maxY)
        // An accidental click or sub-point drag should leave selection open.
        guard right - left >= 1, bottom - top >= 1 else { return nil }

        let scaleX = pixelSize.width / displayRect.width
        let scaleY = pixelSize.height / displayRect.height
        let x0 = ((left - displayRect.minX) * scaleX).rounded(.down)
        let y0 = ((top - displayRect.minY) * scaleY).rounded(.down)
        let x1 = ((right - displayRect.minX) * scaleX).rounded(.up)
        let y1 = ((bottom - displayRect.minY) * scaleY).rounded(.up)
        guard [x0, y0, x1, y1].allSatisfy(\.isFinite) else { return nil }

        let clampedLeft = min(max(x0, 0), pixelSize.width)
        let clampedTop = min(max(y0, 0), pixelSize.height)
        let clampedRight = min(max(x1, 0), pixelSize.width)
        let clampedBottom = min(max(y1, 0), pixelSize.height)
        guard clampedRight > clampedLeft, clampedBottom > clampedTop else { return nil }
        return CGRect(x: clampedLeft, y: clampedTop,
                      width: clampedRight - clampedLeft, height: clampedBottom - clampedTop)
    }

    public static func crop(image: CGImage, selection: CGRect, displayRect: CGRect) -> CGImage? {
        guard let rect = pixelRect(selection: selection, displayRect: displayRect,
                                   pixelSize: CGSize(width: image.width, height: image.height)) else { return nil }
        // CGImage's crop rectangle is in image pixel coordinates with row zero
        // at the top; no AppKit screen-coordinate Y inversion belongs here.
        return image.cropping(to: rect)
    }

    private static func finite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
    }
}
