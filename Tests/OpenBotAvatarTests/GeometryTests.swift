import Foundation
import XCTest
@testable import OpenBotAvatar

final class GeometryTests: XCTestCase {
    func testArcChordsStayWithinTheFlatteningTolerance() throws {
        let circle = try XCTUnwrap(flattenPath(parsePath("M21 50A29 29 0 0 1 79 50A29 29 0 0 1 21 50Z")).first)
        forEachEdge([circle]) { a, b in
            let radius = hypot((a.x + b.x) / 2 - 50, (a.y + b.y) / 2 - 50)
            XCTAssertLessThanOrEqual(29 - radius, 0.02 + 1e-9)
        }
    }

    func testBezierChordsAdaptToCurvature() throws {
        let cubic = flattenPath(try parsePath("M10 20C15 110 90 -10 90 80L10 80Z"))
        let quadratic = flattenPath(try parsePath("M10 30Q50 110 90 30L90 90H10Z"))
        for k in 0...1000 {
            let t = Double(k) / 1000, u = 1 - t
            let x = u * u * u * 10 + 3 * u * u * t * 15 + 3 * u * t * t * 90 + t * t * t * 90
            let y = u * u * u * 20 + 3 * u * u * t * 110 - 3 * u * t * t * 10 + t * t * t * 80
            XCTAssertLessThanOrEqual(edgeDistance(cubic, x, y), 0.02 + 1e-9)
            XCTAssertLessThanOrEqual(edgeDistance(quadratic, u * u * 10 + 2 * u * t * 50 + t * t * 90,
                                                 u * u * 30 + 2 * u * t * 110 + t * t * 30), 0.02 + 1e-9)
        }
        let straight = flattenPath(try parsePath("M0 0C20 0 40 0 60 0L60 60H0Z"))
        XCTAssertEqual(straight.first?.count, 5, "Straight cubics need only the minimum two chords")
    }

    func testGentleTurnsBetweenLongEdgesRemainSharp() {
        let loop = [(10.0, 30.0), (50, 22), (90, 30), (90, 70), (50, 62), (10, 70)].map { Point(x: $0.0, y: $0.1) }
        let path = loopsToPath([loop])
        XCTAssertEqual(path.d, "M30 26l20-4 40 8 0 40-40-8-40 8 0-40Z")
        XCTAssertFalse(path.segments.contains { if case .quadratic = $0 { true } else { false } })
    }

    func testSmoothedSvgAndNativeSegmentsUseTheSameSnappedGeometry() throws {
        let circle = (0..<48).map { k in
            let angle = Double(k) * .pi / 24
            return Point(x: 50 + 29 * cos(angle), y: 50 + 29 * sin(angle))
        }
        let square = [Point(x: -0.01, y: -0.03), Point(x: 1.01, y: -0.03),
                      Point(x: 1.01, y: 0.99), Point(x: -0.01, y: 0.99)]
        let outline = SliceOutline(loops: [circle, square])
        XCTAssertTrue(outline.evenOdd)
        XCTAssertTrue(outline.d.contains("q"))
        XCTAssertTrue(outline.d.contains("t"))
        XCTAssertEqual(outline.segments.filter { if case .quadratic = $0 { true } else { false } }.count, 48)
        XCTAssertEqual(outline.segments.filter { $0 == .close }.count, 2)
        XCTAssertEqual(serializePath(try parsePath(outline.d)), serializePath(outline.segments))
        XCTAssertEqual(loopsToPath([square]).d, "M.51-.02l.51 0 0 1.02-1.02 0 0-1.02Z")
    }

    func testCrossSectionFieldsInvertTheSurfaceAndStayContinuousAtTheRim() throws {
        let shape = PartShape.inflated(depth: 10, rxy: 3, rz: 4.25)
        for distance in [0.0, 0.01, 0.4, 1, 2.9, 3] {
            let z = shape.height(0, 0, distance: distance)
            XCTAssertEqual(shape.levelField(0, 0, distance, z), 0, accuracy: 1e-10)
        }
        XCTAssertEqual(shape.levelField(0, 0, -0.2, 0.75), -0.2, accuracy: 1e-12)
        XCTAssertEqual(shape.levelField(0, 0, 0.2, 0.75), 0.2, accuracy: 1e-12)

        let polys = flattenPath(try parsePath("M-10 -8H10V8H-10Z"))
        let profile = try XCTUnwrap(Profile(polys, rows: true, low: -8, high: 8, center: 0))
        let revolved = PartShape.revolved(profile, axis: 0, horizontal: false, volume: 2)
        let z = revolved.height(3, 0, distance: 0)
        XCTAssertEqual(revolved.levelField(3, 0, 0, z), 0, accuracy: 1e-12)
        XCTAssertLessThan(revolved.levelField(11, 0, 0, 0), 0)
    }

    func testInflatedSectionsFollowTheOutlineInsteadOfTheSamplingGrid() throws {
        let polys = flattenPath(try parsePath("M21 50A29 29 0 0 1 79 50A29 29 0 0 1 21 50Z"))
        let shape = PartShape.inflated(depth: 10, rxy: 3, rz: 4.25)
        let grid = DepthGrid(polys, polygonBounds(polys), step: 0.45) { x, y, distance in
            shape.height(x, y, distance: distance)
        }
        for level in [0.75, 2.5, 4.9] {
            let loops = levelLoops(grid, level: level, field: shape.levelField)
            XCTAssertEqual(loops.count, 1)
            let s = (level - 0.75) / 4.25
            let radius = 29 - 3 * (1 - (1 - s * s).squareRoot())
            for point in loops.joined() {
                XCTAssertEqual(hypot(point.x - 50, point.y - 50), radius, accuracy: 0.08)
            }
        }
        let box = CellBox(i0: 40, i1: 70, j0: 40, j1: 70)
        let clipped = levelLoops(grid, level: 0.75, field: shape.levelField, box: box)
        let bounds = polygonBounds(clipped)
        XCTAssertEqual(clipped.count, 1)
        XCTAssertEqual(bounds.x0, grid.x0 + 40 * grid.step, accuracy: 1e-10)
        XCTAssertEqual(bounds.x1, grid.x0 + 70 * grid.step, accuracy: 1e-10)
        XCTAssertEqual(bounds.y0, grid.y0 + 40 * grid.step, accuracy: 1e-10)
        XCTAssertEqual(bounds.y1, grid.y0 + 70 * grid.step, accuracy: 1e-10)
    }

    func testIdenticalSnappedPathsShareOneOutlineAndKeepItsFirstBox() throws {
        for (id, amount) in [("sprout", 0.5), ("barbell", 1.0)] {
            let def = try XCTUnwrap(AvatarCatalog.definition(id: id))
            let volume = buildVolume(eyes: def.eyes, volume: amount, body: try analyzeBody(def.body.path))
            XCTAssertEqual(Set(volume.outlines.map(\.d)).count, volume.outlines.count, id)
            var references: [Int: Int] = [:]
            for slice in volume.parts.flatMap({ $0.zSlices + $0.xSlices }) {
                references[slice.outline, default: 0] += 1
            }
            XCTAssertTrue(references.values.contains { $0 > 1 }, id)
            if id == "sprout" {
                let slices = volume.parts.flatMap(\.xSlices)
                let slice = try XCTUnwrap(slices.first { abs($0.at - 50.458333333333336) < 1e-10 })
                XCTAssertEqual(volume.outlines[slice.outline].box.width, 3.4977671449083054, accuracy: 1e-10)
            }
        }
    }
}
