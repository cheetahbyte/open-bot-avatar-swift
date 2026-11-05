import CoreGraphics
import Foundation
import OpenBotAvatar

extension AvatarMatrix {
    var transform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
    }
}

extension AvatarColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

/// Draws frames of one prepared avatar with Core Graphics. Equal avatars share their parsed paths.
public final class AvatarPainter: @unchecked Sendable {
    private let paths: [CGPath]
    private let evenOdd: [Bool]

    nonisolated(unsafe) private static let shared = NSCache<PreparedAvatar, AvatarPainter>()

    public init(_ prepared: PreparedAvatar) {
        paths = prepared.paths.map { makePath($0.segments) }
        evenOdd = prepared.paths.map(\.evenOdd)
    }

    public static func cached(_ prepared: PreparedAvatar) -> AvatarPainter {
        if let hit = shared.object(forKey: prepared) { return hit }
        let painter = AvatarPainter(prepared)
        shared.setObject(painter, forKey: prepared)
        return painter
    }

    /// Paints `frame` into `context`, whose transform must map viewBox units to the output.
    /// `matrices` come from `frame.placement()`. Colors default to the frame's own.
    public func paint(_ frame: AvatarFrame, matrices: [AvatarMatrix], in context: CGContext, fill: CGColor? = nil, ink: CGColor? = nil) {
        let fill = fill ?? frame.color.cgColor
        let ink = ink ?? frame.ink.cgColor
        context.setLineCap(.round)
        context.setFillColor(fill)
        context.setStrokeColor(ink)
        for (index, shape) in frame.shapes.enumerated() {
            context.saveGState()
            context.concatenate(matrices[index].transform)
            switch shape {
            case let .slice(_, path, _):
                context.addPath(paths[path])
                context.fillPath(using: evenOdd[path] ? .evenOdd : .winding)
            case let .eye(_, _, mark):
                paintEye(mark, in: context, ink: ink)
            }
            context.restoreGState()
        }
    }

    private func paintEye(_ mark: AvatarEyeMark, in context: CGContext, ink: CGColor) {
        switch mark {
        case let .pill(x, y, width, height, radius):
            let rect = CGRect(x: x, y: y, width: width, height: height)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(ink)
            context.fillPath()
        case let .arc(startX, startY, controlX, controlY, endX, endY, strokeWidth):
            context.move(to: CGPoint(x: startX, y: startY))
            context.addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: controlX, y: controlY))
            context.setLineWidth(strokeWidth)
            context.strokePath()
        }
    }
}

private func makePath(_ segments: [AvatarPathSegment]) -> CGPath {
    let path = CGMutablePath()
    var current = CGPoint.zero
    var start = CGPoint.zero
    for segment in segments {
        switch segment {
        case let .move(x, y):
            current = CGPoint(x: x, y: y)
            start = current
            path.move(to: current)
        case let .line(x, y):
            current = CGPoint(x: x, y: y)
            path.addLine(to: current)
        case let .cubic(x1, y1, x2, y2, x, y):
            current = CGPoint(x: x, y: y)
            path.addCurve(to: current, control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        case let .quadratic(x1, y1, x, y):
            current = CGPoint(x: x, y: y)
            path.addQuadCurve(to: current, control: CGPoint(x: x1, y: y1))
        case let .arc(arc):
            let end = CGPoint(x: arc.x, y: arc.y)
            if let c = arc.center(fromX: current.x, y: current.y) {
                let ellipse = CGAffineTransform(translationX: c.x, y: c.y)
                    .rotated(by: c.rotation)
                    .scaledBy(x: c.rx, y: c.ry)
                path.addRelativeArc(center: .zero, radius: 1, startAngle: c.start, delta: c.delta, transform: ellipse)
            } else {
                path.addLine(to: end)
            }
            current = end
        case .close:
            path.closeSubpath()
            current = start
        }
    }
    return path
}

extension PreparedAvatar {
    /// A still image of the `0 0 100 100` box, `pixels` wide and tall. `fill` and `ink` override the
    /// colors in `options`.
    public func image(_ options: AvatarFrameOptions = AvatarFrameOptions(), pixels: Int, fill: CGColor? = nil, ink: CGColor? = nil) -> CGImage? {
        guard pixels > 0, let context = AvatarBitmap.makeContext(side: pixels) else { return nil }
        let scale = Double(pixels) / 100
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)
        let frame = frame(options)
        AvatarPainter.cached(self).paint(frame, matrices: frame.placement().matrices, in: context, fill: fill, ink: ink)
        return context.makeImage()
    }
}

enum AvatarBitmap {
    static func makeContext(side: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
