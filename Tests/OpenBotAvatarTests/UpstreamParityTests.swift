import Foundation
import XCTest
@testable import OpenBotAvatar

final class UpstreamParityTests: XCTestCase {
    func testFixtureOriginAndCatalog() throws {
        let fixture = try upstreamFixture(), origin = try object(fixture["origin"])
        XCTAssertEqual(origin["version"] as? String, "0.3.0")
        XCTAssertEqual(origin["revision"] as? String, "5e64c081971eb296f562544641bad37d40fb36b6")
        let catalog = try object(fixture["catalog"])
        let examples = try objects(catalog["examples"]).map { try definition($0) }
        let gallery = try objects(catalog["gallery"]).map { try definition($0) }
        XCTAssertEqual(AvatarCatalog.examples, examples)
        XCTAssertEqual(AvatarCatalog.gallery, gallery)
        let validated = try Dictionary(uniqueKeysWithValues: objects(catalog["validated"]).map {
            let d = try definition($0)
            return (d.id, d)
        })
        for d in examples + gallery {
            XCTAssertEqual(AvatarCatalog.definition(id: d.id), d, d.id)
            XCTAssertEqual(try d.validated().get(), validated[d.id], d.id)
        }
        for (id, hex) in try object(catalog["colors"]) {
            XCTAssertEqual(AvatarCatalog.color(id: id).hex, try text(hex).lowercased(), id)
        }
        XCTAssertNil(AvatarCatalog.definition(id: "does-not-exist"))
    }

    func testAllStatesMoodsLegacyAndBlendPoses() throws {
        let cases = try objects(upstreamFixture()["poses"])
        XCTAssertEqual(cases.count, 119)
        for test in cases {
            let name = try text(test["name"]), input = try object(test["input"])
            assertJSON(poseJSON(try fixturePose(input)), try object(test["output"]), name)
        }
    }

    func testAnimatorClockAndInterruptedBlendParity() throws {
        for sequence in try objects(upstreamFixture()["animators"]) {
            var animator = AvatarAnimator()
            for (index, test) in try objects(sequence["steps"]).enumerated() {
                let input = try object(test["input"]), expected = try object(test["output"])
                let context = "\(try text(sequence["name"]))[\(index)]"
                if input["reset"] as? Bool == true { animator.reset() }
                let gaze = try fixtureGaze(input["target"])
                let state = (input["state"] as? String).flatMap(AvatarState.init(rawValue:))
                let mood = try XCTUnwrap(AvatarMood(rawValue: input["mood"] as? String ?? input["motion"] as? String ?? "neutral"))
                let reduced = input["reducedMotion"] as? Bool ?? false
                let step = animator.step(.init(now: try number(input["now"]) / 1000, mood: mood,
                    target: gaze.map { AvatarLook(x: $0.x, y: $0.y) }, hold: input["hold"] as? Bool ?? false,
                    reducedMotion: reduced, state: state))
                XCTAssertEqual(step.stateAge, try number(expected["stateAge"]), accuracy: 1e-12, context)
                XCTAssertEqual(step.moving, expected["moving"] as? Bool, context)
                XCTAssertEqual(step.state, state ?? (mood.rawValue == "thinking" ? .thinking : .idle), context)
                if let expectedGaze = expected["gaze"] as? FixtureObject {
                    let actual = try XCTUnwrap(step.gaze, context)
                    assertJSON(["x": actual.x, "y": actual.y, "weight": actual.weight], expectedGaze, "\(context).gaze")
                } else { XCTAssertNil(step.gaze, context) }
                XCTAssertEqual(step.mood.blend != nil, expected["motionBlend"] != nil, "\(context).blend presence")
                let pose = AvatarPose(.init(seed: 123, time: 1.25, mood: step.mood, gaze: step.gaze,
                                            reducedMotion: reduced, state: step.state, stateAge: step.stateAge))
                assertJSON(poseJSON(pose), try object(test["pose"]), "\(context).pose")
            }
        }
    }

    func testRepresentativeFrameGeometryEffectsAndPalettes() throws {
        for test in try objects(upstreamFixture()["frames"]) {
            let name = try text(test["name"]), d = try definition(test["definition"])
            let options = try object(test["options"]), expected = try object(test["output"])
            let avatar = try PreparedAvatar(d, depth: options["depth"] as? Double ?? 6)
            let actual = avatar.frame(try fixtureOptions(options))
            XCTAssertEqual(actual.name, expected["name"] as? String, name)
            XCTAssertEqual(actual.color.hex, expected["color"] as? String, name)
            XCTAssertEqual(actual.ink.hex, expected["ink"] as? String, name)
            assertJSON(matrixJSON(actual.root), try XCTUnwrap(expected["root"]), "\(name).root")
            let shapes = try objects(expected["shapes"])
            XCTAssertEqual(actual.shapes.count, shapes.count, "\(name).paint count")
            let paths = try Dictionary(uniqueKeysWithValues: objects(expected["paths"]).map { (try text($0["id"]), $0) })
            var usedPaths = Set<Int>()
            for (index, pair) in zip(actual.shapes, shapes).enumerated() {
                let (shape, exp) = pair, context = "\(name).shapes[\(index)]"
                assertJSON(matrixJSON(shape.matrix), try XCTUnwrap(exp["matrix"]), "\(context).matrix")
                switch shape {
                case let .slice(key, path, _):
                    XCTAssertEqual(exp["kind"] as? String, "slice", context)
                    XCTAssertEqual(key.description, exp["key"] as? String, context)
                    guard exp["kind"] as? String == "slice" else { continue }
                    let expectedID = try text(exp["path"])
                    let expectedPath = try XCTUnwrap(paths[expectedID])
                    if usedPaths.insert(path).inserted {
                        let actualPath = actual.paths[path]
                        let evenOdd = expectedPath["evenOdd"] as? Bool ?? false
                        XCTAssertEqual(actualPath.evenOdd, evenOdd, context)
                        // Revolved sections can choose neighboring points during 0.04-unit simplification.
                        let simplified = evenOdd && (d.id == "mug" || d.id == "barbell")
                        try assertPath(actualPath.d, text(expectedPath["d"]), context, simplifiedContour: simplified)
                        assertJSON(boxJSON(actualPath.box), try object(expectedPath["box"]), "\(context).box", accuracy: simplified ? 0.04 : 1e-8)
                    }
                case let .eye(index, _, mark):
                    XCTAssertEqual(exp["kind"] as? String, "eye", context)
                    XCTAssertEqual("eye-\(index)", exp["key"] as? String, context)
                    guard exp["kind"] as? String == "eye" else { continue }
                    try assertEye(mark, object(exp["mark"]), context)
                case let .ribbon(index, d, box, _, front, fill, gradient):
                    XCTAssertEqual(exp["kind"] as? String, "ribbon", context)
                    XCTAssertEqual("ribbon-\(index)", exp["key"] as? String, context)
                    guard exp["kind"] as? String == "ribbon" else { continue }
                    XCTAssertEqual(front, exp["front"] as? Bool, context)
                    XCTAssertEqual(fill.hex, exp["fill"] as? String, context)
                    try assertPath(d, text(exp["d"]), context)
                    assertJSON(boxJSON(box), try object(exp["box"]), "\(context).box", accuracy: 1e-8)
                    assertJSON(["x1": gradient.x1, "y1": gradient.y1, "x2": gradient.x2, "y2": gradient.y2,
                                "stops": gradient.stops.map(\.hex)], try object(exp["gradient"]), "\(context).gradient", accuracy: 1e-8)
                }
            }
            XCTAssertEqual(usedPaths.count, paths.count, "\(name).used path count")
            // Prepared body paths remain available even when a mark completely replaces the body.
            XCTAssertGreaterThanOrEqual(actual.paths.count, avatar.paths.count, name)
        }
    }

    func testRepresentativeSVGSerialization() throws {
        var checked = 0
        for test in try objects(upstreamFixture()["frames"]) {
            guard let svg = test["svg"] as? String else { continue }
            let name = try text(test["name"]), options = try object(test["options"])
            let avatar = try PreparedAvatar(definition(test["definition"]), depth: options["depth"] as? Double ?? 6)
            let actual = avatar.svg(try fixtureOptions(options), size: options["size"] as? Double)
            let actualRoot = try readSVG(actual), expectedRoot = try readSVG(svg)
            assertSVGReferences(actualRoot, name)
            try assertSVG(normalizedSVG(actualRoot), normalizedSVG(expectedRoot), name)
            checked += 1
        }
        XCTAssertEqual(checked, 6)
    }

    func testSampledVolumeStacksAndSmootherRims() throws {
        for test in try objects(upstreamFixture()["volumes"]) {
            let d = try definition(test["definition"]), validated = try d.validatedWithBody().get()
            let volume = buildVolume(eyes: d.eyes, volume: 1, body: validated.body)
            let parts = try objects(test["parts"])
            XCTAssertEqual(volume.parts.count, parts.count, d.id)
            for (partIndex, pair) in zip(volume.parts, parts).enumerated() {
                let (part, expected) = pair, context = "\(d.id).part[\(partIndex)]"
                XCTAssertEqual(part.depth, try number(expected["depth"]), accuracy: 1e-9, context)
                assertJSON([part.center.x, part.center.y], try XCTUnwrap(expected["center"]), "\(context).center")
                for stack in try objects(expected["stacks"]) {
                    let stackName = try text(stack["name"])
                    let slices = stackName == "zSlices" ? part.zSlices : part.xSlices
                    XCTAssertEqual(slices.count, stack["count"] as? Int, "\(context).\(stackName)")
                    for sample in try objects(stack["slices"]) {
                        let index = try XCTUnwrap(sample["index"] as? Int)
                        guard index < slices.count else { XCTFail("\(context): missing slice \(index)"); continue }
                        let slice = slices[index], outline = volume.outlines[slice.outline]
                        let label = "\(context).\(stackName)[\(index)]"
                        XCTAssertEqual(slice.at, try number(sample["at"]), accuracy: 1e-9, label)
                        XCTAssertEqual(slice.inset, try number(sample["inset"]), accuracy: 1e-9, label)
                        XCTAssertEqual(outline.evenOdd, sample["evenOdd"] as? Bool, label)
                        let simplified = outline.evenOdd && (d.id == "mug" || d.id == "barbell")
                        try assertPath(outline.d, text(sample["d"]), label, simplifiedContour: simplified)
                        assertJSON(boxJSON(outline.box), try object(sample["box"]), "\(label).box", accuracy: simplified ? 0.04 : 1e-8)
                    }
                }
            }
        }
    }

    private func assertEye(_ mark: AvatarEyeMark, _ expected: FixtureObject, _ context: String) throws {
        var actual = eyeJSON(mark), expected = expected
        XCTAssertEqual(actual["shape"] as? String, expected["shape"] as? String, context)
        if case let .path(d) = mark {
            try assertPath(d, text(expected["d"]), context)
            actual.removeValue(forKey: "d"); expected.removeValue(forKey: "d")
        } else if case .arc = mark {
            let regex = try NSRegularExpression(pattern: "[-+]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)")
            let d = try text(expected.removeValue(forKey: "d"))
            let numbers = regex.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { Double(d[Range($0.range, in: d)!])! }
            let coordinates = try XCTUnwrap(actual.removeValue(forKey: "coordinates") as? [Double])
            assertJSON(coordinates, numbers, "\(context).arc coordinates", accuracy: 0.005000001)
        }
        assertJSON(actual, expected, context)
    }
}
