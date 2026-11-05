import OpenBotAvatar
import QuartzCore

/// One bitmap on one layer, so an avatar costs one layer however many slices it shows. The bitmap
/// covers what the frames actually paint, and the layer overhangs the view by that much.
@MainActor
struct AvatarCanvas {
    let layer = CALayer()

    private var bitmap: CGContext?
    private var layout: Layout?
    private var left = 0
    private var top = 0

    private struct Layout {
        var prepared: PreparedAvatar
        var size: CGFloat
        var scale: CGFloat
        var fit: AvatarSquare
    }

    init() {
        layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "contentsScale": NSNull()]
    }

    /// Paints `frame` so the viewBox fills a `size`-point square at the superlayer's origin.
    mutating func paint(_ frame: AvatarFrame, of prepared: PreparedAvatar, size: CGFloat, scale: CGFloat, fill: CGColor, ink: CGColor) {
        let unit = Double(size * scale) / viewBoxSize
        let (matrices, bounds) = frame.placement()
        var previous: AvatarSquare?
        if let layout, layout.prepared === prepared, layout.size == size, layout.scale == scale { previous = layout.fit }
        let fit = AvatarBitmapFit.square(previous: previous, bounds: bounds, cap: prepared.extent)
        if bitmap == nil || previous != fit {
            layout = Layout(prepared: prepared, size: size, scale: scale, fit: fit)
            // Whole device pixels, so the bitmap is never resampled.
            left = Int((fit.x * unit).rounded(.down))
            top = Int((fit.y * unit).rounded(.down))
            let side = Int((fit.size * unit).rounded(.up)) + 1
            bitmap = AvatarBitmap.makeContext(side: side)
            layer.contentsScale = scale
            layer.frame = CGRect(
                x: CGFloat(left) / scale, y: CGFloat(top) / scale, width: CGFloat(side) / scale, height: CGFloat(side) / scale)
        }
        guard let bitmap else { return }
        bitmap.clear(CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        bitmap.saveGState()
        AvatarBitmap.mapViewBox(in: bitmap, unit: unit, left: left, top: top)
        AvatarPainter.cached(prepared).paint(frame, matrices: matrices, in: bitmap, fill: fill, ink: ink)
        bitmap.restoreGState()
        layer.contents = bitmap.makeImage()
    }

    mutating func clear() {
        layer.contents = nil
        bitmap = nil
        layout = nil
    }
}
