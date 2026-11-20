import CoreGraphics
import XCTest
@testable import OpenBotAvatar
@testable import OpenBotAvatarUI

final class AvatarPainterTests: XCTestCase {
    private let identity = AvatarMatrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

    private func bitmap(_ frame: AvatarFrame, prepared: PreparedAvatar) throws -> CGContext {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        AvatarPainter(prepared).paint(frame, matrices: frame.placement().matrices, in: context)
        return context
    }

    private func pixel(_ context: CGContext, x: Int, y: Int) throws -> [UInt8] {
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (0..<4).map { bytes[offset + $0] }
    }

    func testRibbonPainterUsesGradientRatherThanFlatFallback() throws {
        let prepared = try PreparedAvatar(try XCTUnwrap(AvatarCatalog.definition(id: "mug")))
        let red = AvatarColor(red: 255, green: 0, blue: 0)
        let blue = AvatarColor(red: 0, green: 0, blue: 255)
        let gradient = AvatarRibbonGradient(x1: 10, y1: 50, x2: 90, y2: 50, stops: [red, blue])
        let frame = AvatarFrame(name: "Gradient", color: .defaultBody, ink: .defaultEyes, paths: [], root: identity,
                                shapes: [.ribbon(index: 0, d: "M10 10H90V90H10Z", box: AvatarBox(x: 10, y: 10, width: 80, height: 80),
                                                 matrix: identity, front: true, fill: .defaultBody, gradient: gradient)])
        let context = try bitmap(frame, prepared: prepared)
        let left = try pixel(context, x: 20, y: 50), right = try pixel(context, x: 80, y: 50)
        XCTAssertGreaterThan(Int(left[0]) - Int(left[2]), 120)
        XCTAssertGreaterThan(Int(right[2]) - Int(right[0]), 120)
        XCTAssertEqual(left[3], 255)
        XCTAssertEqual(right[3], 255)
        XCTAssertEqual(try pixel(context, x: 5, y: 50)[3], 0, "Gradient stays clipped to its ribbon")
    }

    func testFilledMorphEyeIsPaintedInInk() throws {
        let prepared = try PreparedAvatar(try XCTUnwrap(AvatarCatalog.definition(id: "mug")))
        let ink = AvatarColor(red: 10, green: 220, blue: 40)
        let frame = AvatarFrame(name: "Eye", color: .defaultBody, ink: ink, paths: [], root: identity,
                                shapes: [.eye(index: 0, matrix: identity, mark: .path(d: "M20 20H80V80H20Z"))])
        let context = try bitmap(frame, prepared: prepared)
        let center = try pixel(context, x: 50, y: 50)
        XCTAssertEqual(Int(center[0]), 10, accuracy: 1)
        XCTAssertEqual(Int(center[1]), 220, accuracy: 1)
        XCTAssertEqual(Int(center[2]), 40, accuracy: 1)
        XCTAssertEqual(center[3], 255)
        XCTAssertEqual(try pixel(context, x: 10, y: 50)[3], 0)
    }

    func testReplacementMarksUseDynamicFramePaths() throws {
        let prepared = try PreparedAvatar(try XCTUnwrap(AvatarCatalog.definition(id: "mug")))
        for state in [AvatarState.thinking, .blocked] {
            let frame = prepared.frame(AvatarFrameOptions(reducedMotion: true, state: state))
            XCTAssertFalse(frame.shapes.isEmpty)
            XCTAssertTrue(frame.shapes.allSatisfy {
                if case let .slice(key, path, _) = $0 { return key.part < 0 && path >= prepared.paths.count }
                return false
            })
            let context = try bitmap(frame, prepared: prepared)
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let opaque = (0..<10000).filter { bytes[$0 * 4 + 3] > 128 }.count
            XCTAssertGreaterThan(opaque, 50, "\(state) must draw its mark")
            XCTAssertLessThan(opaque, 2000, "\(state) must not draw the old body")
        }
    }

    func testResolvedGrayscaleAndRGBColorsReachPaletteInputs() throws {
        let gray = try XCTUnwrap(AvatarColor(cgColor: CGColor(gray: 0.5, alpha: 1)))
        XCTAssertEqual(gray.red, gray.green)
        XCTAssertEqual(gray.green, gray.blue)
        let color = AvatarColor(red: 30, green: 160, blue: 220)
        XCTAssertEqual(AvatarColor(cgColor: color.cgColor), color)
    }
}
