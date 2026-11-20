import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import OpenBotAvatar

typealias FixtureObject = [String: Any]

func upstreamFixture() throws -> FixtureObject {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "upstream-0.3.0", withExtension: "json"))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? FixtureObject)
}

func object(_ value: Any?) throws -> FixtureObject { try XCTUnwrap(value as? FixtureObject) }
func objects(_ value: Any?) throws -> [FixtureObject] { try XCTUnwrap(value as? [FixtureObject]) }
func number(_ value: Any?) throws -> Double { try XCTUnwrap(value as? Double) }
func text(_ value: Any?) throws -> String { try XCTUnwrap(value as? String) }

func definition(_ value: Any?) throws -> AvatarDefinition {
    try JSONDecoder().decode(AvatarDefinition.self, from: JSONSerialization.data(withJSONObject: object(value)))
}

func fixtureGaze(_ value: Any?) throws -> AvatarGaze? {
    guard let v = value as? FixtureObject else { return nil }
    return AvatarGaze(x: try number(v["x"]), y: try number(v["y"]), weight: v["weight"] as? Double ?? 1)
}

func fixtureView(_ value: Any?) throws -> AvatarViewRotation? {
    guard let v = value as? FixtureObject else { return nil }
    return AvatarViewRotation(yaw: try number(v["yaw"]), pitch: try number(v["pitch"]))
}

func fixtureMood(_ input: FixtureObject, blendKey: String = "blend") throws -> AvatarMoodState {
    let legacy = input["motion"] as? String
    let mood = try XCTUnwrap(AvatarMood(rawValue: input["mood"] as? String ?? legacy ?? "neutral"))
    let state = input["state"] as? String
    let blend = input[blendKey] as? FixtureObject
    let from: AvatarMoodState?
    if let blend {
        if let motion = blend["from"] as? String {
            from = .settled(try XCTUnwrap(AvatarMood(rawValue: motion)))
        } else {
            from = try fixtureMood(object(blend["from"]))
        }
    } else { from = nil }
    // Exercise the original public enum cases as well as the state-aware cases.
    if state == nil, input["mood"] == nil, legacy != nil {
        if let from, let blend { return .easing(mood, from: from, t: try number(blend["t"])) }
        return .settled(mood)
    }
    let resolved = try XCTUnwrap(AvatarState(rawValue: state ?? (legacy == "thinking" ? "thinking" : "idle")))
    return AvatarMoodState(state: resolved, mood: mood, age: input["age"] as? Double,
                           from: from, t: blend?["t"] as? Double ?? 1)
}

func fixturePose(_ input: FixtureObject) throws -> AvatarPose {
    AvatarPose(AvatarPose.Input(
        seed: UInt32(try number(input["seed"])), time: try number(input["time"]),
        mood: try fixtureMood(input), gaze: try fixtureGaze(input["gaze"]),
        reducedMotion: input["reducedMotion"] as? Bool ?? false, view: try fixtureView(input["view"]),
        state: (input["state"] as? String).flatMap(AvatarState.init(rawValue:)), stateAge: input["stateAge"] as? Double))
}

func fixtureOptions(_ input: FixtureObject) throws -> AvatarFrameOptions {
    AvatarFrameOptions(
        color: (input["color"] as? String).flatMap(AvatarColor.init(hex:)) ?? .defaultBody,
        eyeColor: (input["eyeColor"] as? String).flatMap(AvatarColor.init(hex:)) ?? .defaultEyes,
        time: input["time"] as? Double ?? 0, mood: try fixtureMood(input, blendKey: "motionBlend"),
        gaze: try fixtureGaze(input["gaze"]), view: try fixtureView(input["view"]),
        reducedMotion: input["reducedMotion"] as? Bool ?? false,
        state: (input["state"] as? String).flatMap(AvatarState.init(rawValue:)), stateAge: input["stateAge"] as? Double)
}

func poseJSON(_ p: AvatarPose) -> FixtureObject {
    ["yaw": p.yaw, "pitch": p.pitch, "roll": p.roll, "lift": p.lift, "sx": p.scaleX, "sy": p.scaleY,
     "gazeX": p.gazeX, "gazeY": p.gazeY, "blink": p.blink, "squintL": p.squintLeft, "squintR": p.squintRight,
     "eyes": ["arc": p.eyes.arc, "slit": p.eyes.slit], "ribbons": p.ribbons, "cage": p.cage,
     "sweep": p.sweep, "bang": p.bang, "dots": p.dots]
}

func matrixJSON(_ m: AvatarMatrix) -> [Double] { [m.a, m.b, m.c, m.d, m.e, m.f] }
func boxJSON(_ b: AvatarBox) -> FixtureObject { ["x": b.x, "y": b.y, "w": b.width, "h": b.height] }

/// Compare independent upstream numbers, not a second invocation of the Swift implementation.
func assertJSON(_ actual: Any, _ expected: Any, _ context: String, accuracy: Double = 1e-9,
                file: StaticString = #filePath, line: UInt = #line) {
    if let a = actual as? FixtureObject, let e = expected as? FixtureObject {
        XCTAssertEqual(Set(a.keys), Set(e.keys), context, file: file, line: line)
        for key in e.keys.sorted() {
            if let av = a[key], let ev = e[key] { assertJSON(av, ev, "\(context).\(key)", accuracy: accuracy, file: file, line: line) }
        }
    } else if let a = actual as? [Any], let e = expected as? [Any] {
        XCTAssertEqual(a.count, e.count, context, file: file, line: line)
        for (i, pair) in zip(a, e).enumerated() { assertJSON(pair.0, pair.1, "\(context)[\(i)]", accuracy: accuracy, file: file, line: line) }
    } else if let a = actual as? NSNumber, let e = expected as? NSNumber {
        XCTAssertEqual(a.doubleValue, e.doubleValue, accuracy: accuracy, context, file: file, line: line)
    } else if let a = actual as? String, let e = expected as? String {
        XCTAssertEqual(a, e, context, file: file, line: line)
    } else {
        XCTFail("\(context): incompatible values \(actual) and \(expected)", file: file, line: line)
    }
}

private func pathTokens(_ d: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "[A-Za-z]|[-+]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?")
    return regex.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range, in: d)!]) }
}

/// Paths are serialized to 0.01 units. Keep command structure and coordinates strict except
/// for independently simplified contour loops, whose documented error budget is 0.04 units.
func assertPath(_ actual: String, _ expected: String, _ context: String, simplifiedContour: Bool = false,
                file: StaticString = #filePath, line: UInt = #line) throws {
    if actual == expected { return }
    let a = pathTokens(actual), e = pathTokens(expected)
    if a.count == e.count, zip(a, e).allSatisfy({ pair in
        if let av = Double(pair.0), let ev = Double(pair.1) { return abs(av - ev) <= 1e-9 }
        return pair.0 == pair.1
    }) { return }
    guard simplifiedContour else {
        XCTFail("\(context): path commands or coordinates differ", file: file, line: line)
        return
    }
    let ap = flattenPath(try parsePath(actual)), ep = flattenPath(try parsePath(expected))
    XCTAssertEqual(ap.count, ep.count, "\(context): contour topology", file: file, line: line)
    func directed(_ from: [[Point]], _ to: [[Point]]) -> Double {
        var worst = 0.0
        for point in from.flatMap({ $0 }) {
            var best = Double.infinity
            forEachEdge(to) { p, q in
                let dx = q.x - p.x, dy = q.y - p.y, length = dx * dx + dy * dy
                let t = length == 0 ? 0 : min(1, max(0, ((point.x - p.x) * dx + (point.y - p.y) * dy) / length))
                best = min(best, hypot(point.x - p.x - t * dx, point.y - p.y - t * dy))
            }
            worst = max(worst, best)
        }
        return worst
    }
    // 0.04 simplification + at most sqrt(2)*0.01 differential coordinate rounding.
    XCTAssertLessThanOrEqual(max(directed(ap, ep), directed(ep, ap)), 0.055, context, file: file, line: line)
}

func eyeJSON(_ mark: AvatarEyeMark) -> FixtureObject {
    switch mark {
    case let .path(d): return ["shape": "path", "d": d]
    case let .pill(x, y, width, height, radius):
        return ["shape": "pill", "x": x, "y": y, "width": width, "height": height, "radius": radius]
    case let .arc(sx, sy, cx, cy, ex, ey, width):
        // Upstream's public arc path is rounded to two decimal places; compare that field separately.
        return ["shape": "arc", "coordinates": [sx, sy, cx, cy, ex, ey], "strokeWidth": width]
    }
}

final class SVGNode {
    let name: String
    var attributes: [String: String]
    var children: [SVGNode] = []
    var text = ""
    init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
}

private final class SVGReader: NSObject, XMLParserDelegate {
    var root: SVGNode?
    var stack: [SVGNode] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        let node = SVGNode(name, attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { stack.removeLast() }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
}

func assertSVGReferences(_ root: SVGNode, _ context: String) {
    var defined: [String] = [], used = Set<String>()
    func visit(_ node: SVGNode, inDefs: Bool) {
        if inDefs, node.name == "path", let id = node.attributes["id"] { defined.append(id) }
        if node.name == "use", let href = node.attributes["href"] { used.insert(String(href.dropFirst())) }
        for child in node.children { visit(child, inDefs: inDefs || node.name == "defs") }
    }
    visit(root, inDefs: false)
    XCTAssertEqual(defined.count, Set(defined).count, "\(context): duplicate SVG path ids")
    XCTAssertEqual(Set(defined), used, "\(context): SVG defs must contain exactly the referenced body and mark paths")
}

func readSVG(_ svg: String) throws -> SVGNode {
    let parser = XMLParser(data: Data(svg.utf8)), reader = SVGReader()
    parser.delegate = reader
    XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "SVG parse failed")
    return try XCTUnwrap(reader.root)
}

/// Definition ids and definition order aren't part of the visual contract. Resolve references
/// instead; retain every painting node, gradient stop, transform, and accessibility attribute.
func normalizedSVG(_ root: SVGNode) -> FixtureObject {
    var definitions: [String: SVGNode] = [:]
    func collect(_ node: SVGNode) {
        if let id = node.attributes["id"] { definitions[id] = node }
        node.children.forEach(collect)
    }
    collect(root)
    func normalize(_ node: SVGNode) -> FixtureObject {
        var attrs: FixtureObject = node.attributes.filter { $0.key != "id" }
        if let href = node.attributes["href"], let path = definitions[String(href.dropFirst())] {
            attrs["href"] = normalize(path)
        }
        if let fill = node.attributes["fill"], fill.hasPrefix("url(#"), fill.hasSuffix(")"),
           let gradient = definitions[String(fill.dropFirst(5).dropLast())] {
            attrs["fill"] = normalize(gradient)
        }
        return ["tag": node.name, "attributes": attrs, "text": node.text,
                "children": node.children.filter { $0.name != "defs" }.map(normalize)]
    }
    return normalize(root)
}

func assertSVG(_ actual: Any, _ expected: Any, _ context: String) throws {
    if let a = actual as? FixtureObject, let e = expected as? FixtureObject {
        XCTAssertEqual(Set(a.keys), Set(e.keys), context)
        for key in e.keys.sorted() {
            if let av = a[key], let ev = e[key] { try assertSVG(av, ev, "\(context).\(key)") }
        }
    } else if let a = actual as? [Any], let e = expected as? [Any] {
        XCTAssertEqual(a.count, e.count, context)
        for (i, pair) in zip(a, e).enumerated() { try assertSVG(pair.0, pair.1, "\(context)[\(i)]") }
    } else if context.hasSuffix(".d"), let a = actual as? String, let e = expected as? String {
        try assertPath(a, e, context)
    } else if context.hasSuffix(".transform"), let a = actual as? String, let e = expected as? String {
        // SVG rounds the four linear terms to 0.0001 and translations to 0.01.
        let an = pathTokens(a).compactMap(Double.init), en = pathTokens(e).compactMap(Double.init)
        assertJSON(an, en, context, accuracy: 0.000100001)
    } else {
        assertJSON(actual, expected, context)
    }
}
