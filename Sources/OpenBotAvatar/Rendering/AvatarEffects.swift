import Foundation

/// Pure effect geometry from open-bot-avatar 0.3.0 (5e64c081971eb296f562544641bad37d40fb36b6).
/// Coordinates are viewBox units; time is seconds and sweep is signed radians.
struct RibbonPiece: Sendable {
    var d: String
    var front: Bool
    var box: AvatarBox
    var ribbon: Int
    /// The stretch of the ribbon, tail (0) to head (1), and its endpoint centres.
    var along: (Double, Double)
    var from: Point
    var to: Point
}

/// A hoop's centre and the body's reach in either direction along a line through it.
struct Rim: Sendable {
    var cx: Double
    var cy: Double
    var at: @Sendable (Double) -> Double
    var max: Double
}

private let design = 228.541
private let body = 80.0
private let unit = body / design
private let rimMargin = 2.0
private let ring = 38.8 * (116 / 114.2705)
private let rimSteps = 180
private let hoopTilt = 0.386
private let hoopRoll = 0.157
private let hoopJitter = 0.24
private let hoopTiltJitter = 0.08
private let ladder = 38.0
private let arc = (2.2, 3.4)
private let follow = (0.74, 0.94)
private let drift = (0.5, 1.1)
private let widen = 2.5
private let startAngle = 0.18
private let sizeFew = (8.0, 10.5)
private let sizeFour = (6.6, 8.6)
private let sizeMany = (5.6, 7.4)
private let workLanes = (3.0, 5.0)
private let brush = 1.7 * 1.98
private let farWidth = 0.72
private let growSeconds = 0.34
private let stagger = (0.055, 0.105)
private let sweepRate = (6.3, 15.0)
private let sweepLongest = 4.0
private let lanesPerHoop = 3
private let hoops = 3
private let samples = 24
private let stretch = 6
private let sliverAngle = 0.02
private let capSamples = 7

private func mix(_ range: (Double, Double), _ u: Double) -> Double {
    range.0 + (range.1 - range.0) * u
}

private func sizeFor(_ count: Int) -> (Double, Double) {
    count <= 3 ? sizeFew : count == 4 ? sizeFour : sizeMany
}

private func reachAlong(_ outlines: [[[Point]]], _ cx: Double, _ cy: Double, _ angle: Double) -> Double {
    let ux = cos(angle), uy = sin(angle)
    var far = 0.0
    for polys in outlines {
        for poly in polys {
            for i in poly.indices {
                let p = poly[i], q = poly[(i + 1) % poly.count]
                let ex = q.x - p.x, ey = q.y - p.y
                let den = ux * ey - uy * ex
                if abs(den) < 1e-12 { continue }
                let t = ((p.x - cx) * ey - (p.y - cy) * ex) / den
                let s = ((p.x - cx) * uy - (p.y - cy) * ux) / den
                if s >= 0 && s <= 1 { far = max(far, abs(t)) }
            }
        }
    }
    return far
}

func rimOf(_ outlines: [[[Point]]], cx: Double, cy: Double) -> Rim {
    let at: @Sendable (Double) -> Double = { reachAlong(outlines, cx, cy, $0) }
    let far = (0..<rimSteps).map { at(Double($0) * .pi / Double(rimSteps)) }.max() ?? 0
    // Allow for a spike between the one-degree samples.
    return Rim(cx: cx, cy: cy, at: at, max: far * 1.02)
}

/// Measure all the leans and stretches each state takes, without moving the hoop's centre.
func ribbonRims(_ polys: [[Point]], bounds b: AvatarBounds) -> (work: Rim, cage: Rim) {
    let cx = b.center.x, cy = b.center.y
    let bx = b.center.x, by = b.y1
    func posed(_ rolls: [Double], _ scalesY: [Double]) -> [[[Point]]] {
        var outlines: [[[Point]]] = []
        for roll in rolls {
            let r = roll * .pi / 180, c = cos(r), sn = sin(r)
            for k in scalesY {
                outlines.append(polys.map { poly in
                    poly.map { p in
                        let lx = bx + c * (p.x - bx) - sn * (p.y - by)
                        let ly = by + sn * (p.x - bx) + c * (p.y - by)
                        return Point(x: cx + 1.01 * (lx - cx), y: cy + k * (ly - cy))
                    }
                })
            }
        }
        return outlines
    }
    return (
        rimOf(posed([2.4, 4.5, 6.6], [0.98, 1]), cx: cx, cy: cy),
        rimOf(posed([-1.7, 0, 1.7], [0.99, 1.055]), cx: cx, cy: cy))
}

/// Follow the body's lift and stretch about its base, but not its roll or sway.
func ribbonsFollow(_ rim: Rim, pose: AvatarPose, bounds b: AvatarBounds) -> Rim {
    var moved = rim
    let bx = b.center.x, by = b.y1
    moved.cx = bx + pose.scaleX * (rim.cx - bx)
    moved.cy = by + pose.scaleY * (rim.cy - by) + pose.lift
    return moved
}

func ribbonReach(_ rimMax: Double? = nil) -> (radius: Double, width: Double, band: Double) {
    let width = sizeFew.1 * brush * unit
    let base = rimMax.map { $0 + rimMargin } ?? ring
    return (base + (ladder + widen * sweepLongest) * unit, width, width / 2)
}

/// Filled ribbon outlines, split at layer changes and into overlapping gradient stretches.
/// `time` is retained for upstream parity; geometry is placed from `sweep` alone.
func ribbonPieces(
    _ b: AvatarBounds, presence: Double, seed: UInt32, time _: Double,
    sweep: Double = 0, cage: Double = 0, rim: Rim? = nil
) -> [RibbonPiece] {
    let k = clamp(presence, 0, 1), more = cage >= 0.5 ? 1 : 0
    if k <= 0.01 { return [] }
    let cx = rim?.cx ?? b.center.x, cy = rim?.cy ?? b.center.y
    let rolls = (0..<hoops).map {
        hoopRoll + Double($0) * .pi / Double(hoops) + (AvatarNoise.value(seed, 450 + $0) - 0.5) * hoopJitter
    }
    let cageRing = rim.map { rim in (rolls.map { rim.at($0) }.max() ?? 0) + rimMargin } ?? ring
    let dir = sweep < 0 ? -1.0 : 1.0
    let since = abs(sweep) / mix(sweepRate, Double(more))
    var pieces: [RibbonPiece] = []
    for i in 0..<(more > 0 ? hoops : 1) {
        let roll = rolls[i]
        let tilt = hoopTilt + (AvatarNoise.value(seed, 460 + i) - 0.5) * hoopTiltJitter
        let base = more > 0 ? cageRing : rim.map { $0.at(roll) + rimMargin } ?? ring
        let lanes = i != 0 || more > 0 ? lanesPerHoop : Int(roundHalfUp(mix(workLanes, AvatarNoise.value(seed, 47))))
        for l in 0..<lanes {
            func n(_ m: Int) -> Double { AvatarNoise.value(seed, 500 + (i * lanesPerHoop + l) * 11 + m) }
            let order = more > 0 ? l * hoops + i : l
            let at = Double(order) * mix(stagger, n(7))
            let life = since - at
            if life <= 0 { continue }
            let before = since > 0 ? abs(sweep) * (at / since) : 0
            let flat = sin(tilt), depth = cos(tilt)
            let cr = cos(roll), sr = sin(roll)
            let r = base + Double(l) * ladder * unit / Double(lanes - 1) + mix((0, widen), n(2)) * unit * life
            let travel = (abs(sweep) - before) * mix(follow, n(3)) + mix(drift, n(4)) * life
            let head = dir * (before + travel - startAngle * n(5))
            let ret = 1 - clamp(k * 1.25, 0, 1)
            let length = min(mix(arc, n(6)), travel) * (1 - ret * ret * (3 - 2 * ret))
            if length <= 0.02 { continue }
            let size = mix(sizeFor(lanes), n(8)) * Double(1 - more) + mix(sizeMany, n(8)) * Double(more)
            let nearHead = clamp(cos(head) * depth, 0, 1)
            var full = size * brush * unit * (farWidth + (1 - farWidth) * nearHead)
                * smoothstep(life / growSeconds) * (1 - 0.72 * ret * ret)
            func lamAt(_ u: Double) -> Double { head - dir * length * (1 - u) }
            func point(_ lam: Double) -> Point {
                let a = sin(lam), y = -cos(lam) * flat
                return Point(x: cx + r * (a * cr - y * sr), y: cy + r * (a * sr + y * cr))
            }
            func along(_ lam: Double) -> Double { 1 - (head - lam) / (dir * length) }
            let sliver = sliverAngle / length
            var ss = (0...samples).map { Double($0) / Double(samples) }
            let lo = min(head, head - dir * length), hi = max(head, head - dir * length)
            var sideIndex = ceil((lo - .pi / 2) / .pi)
            while .pi / 2 + sideIndex * .pi < hi {
                let u = along(.pi / 2 + sideIndex * .pi)
                for d in [-sliver, 0, sliver] where u + d > 0 && u + d < 1 { ss.append(u + d) }
                sideIndex += 1
            }
            ss.sort()
            let near = ss.map { cos(lamAt($0) + dir * 1e-6) > 0 }
            var mid: [Point] = [], halfs: [Double] = [], norm: [Point] = [], bend: [Double] = []
            for u in ss {
                let lam = lamAt(u)
                let nx = sin(lam) * flat, ny = -cos(lam)
                let nl = hypot(nx, ny)
                let ux = nx / (nl == 0 ? 1 : nl), uy = ny / (nl == 0 ? 1 : nl)
                mid.append(point(lam))
                norm.append(Point(x: ux * cr - uy * sr, y: ux * sr + uy * cr))
                halfs.append(0.5 + 0.5 * u)
                let c = cos(lam), sn = sin(lam)
                bend.append(r * pow(c * c + flat * flat * sn * sn, 1.5) / flat)
            }
            let last = ss.count - 1
            var onScreen = 0.0
            for j in 1...last { onScreen += hypot(mid[j].x - mid[j - 1].x, mid[j].y - mid[j - 1].y) }
            full = min(full, 0.34 * onScreen)
            for j in 0...last { halfs[j] = min(halfs[j] * (full / 2), 0.9 * bend[j]) }
            func side(_ j: Int, _ sign: Double) -> Point {
                Point(x: mid[j].x + sign * norm[j].x * halfs[j], y: mid[j].y + sign * norm[j].y * halfs[j])
            }
            func cap(_ j: Int, _ ahead: Bool) -> [Point] {
                let o = ahead ? mid[j - 1] : mid[j + 1]
                var tx = ahead ? mid[j].x - o.x : o.x - mid[j].x
                var ty = ahead ? mid[j].y - o.y : o.y - mid[j].y
                let tl = hypot(tx, ty)
                tx /= tl == 0 ? 1 : tl
                ty /= tl == 0 ? 1 : tl
                let nx = norm[j].x, ny = norm[j].y, h = halfs[j]
                return (1..<capSamples).map { c in
                    let t = .pi * Double(c) / Double(capSamples)
                    let e = ahead ? cos(t) : -cos(t), g = ahead ? sin(t) : -sin(t)
                    return Point(x: mid[j].x + (nx * e + tx * g) * h, y: mid[j].y + (ny * e + ty * g) * h)
                }
            }
            var from = 0
            for j in 1...last {
                let turns = j < last && near[j] != near[from]
                if j < last && !turns && j - from < stretch { continue }
                let to = j, behind = !near[from]
                let end = to < last && (!turns || behind) ? to + 1 : to
                let start = from > 0 && behind && near[from - 1] ? from - 1 : from
                var pts = (start...end).map { side($0, 1) }
                if end == last { pts.append(contentsOf: cap(last, true)) }
                for q in stride(from: end, through: start, by: -1) { pts.append(side(q, -1)) }
                if start == 0 { pts.append(contentsOf: cap(0, false)) }
                var bounds = AvatarBounds()
                for p in pts { bounds.add((p.x, p.y)) }
                pieces.append(RibbonPiece(
                    d: "M" + pts.map { "\(rounded2($0.x)) \(rounded2($0.y))" }.joined(separator: "L") + "Z",
                    front: near[from], box: bounds.box, ribbon: i * lanesPerHoop + l,
                    along: (ss[from], ss[to]), from: mid[from], to: mid[to]))
                from = j
            }
        }
    }
    return pieces
}

/// A fixed outline about its own centre, positioned and scaled for this frame.
struct MarkPart: Sendable {
    var shape: String
    var d: String
    var box: AvatarBox
    var x: Double
    var y: Double
    /// Rotation about the whole mark's centre, in radians.
    var turn: Double
    var scale: Double
}

private func circle(_ r: Double) -> String {
    "M\(rounded2(r)) 0A\(rounded2(r)) \(rounded2(r)) 0 1 1 \(rounded2(-r)) 0A\(rounded2(r)) \(rounded2(r)) 0 1 1 \(rounded2(r)) 0Z"
}

private func capsule(_ w: Double, _ h: Double) -> String {
    let r = w / 2, y = h / 2 - r
    return "M\(rounded2(-r)) \(rounded2(-y))A\(rounded2(r)) \(rounded2(r)) 0 0 1 \(rounded2(r)) \(rounded2(-y))L\(rounded2(r)) \(rounded2(y))A\(rounded2(r)) \(rounded2(r)) 0 0 1 \(rounded2(-r)) \(rounded2(y))Z"
}

func markParts(_ b: AvatarBounds, bang: Double, dots: Double, seed: UInt32, time: Double, still: Bool) -> [MarkPart] {
    let cx = b.center.x, cy = b.center.y
    let u = clamp(min(b.width, b.height), 34, 78)
    let t = still ? 0 : time + AvatarNoise.value(seed, 9) * 10
    var parts: [MarkPart] = []
    func grown(_ weight: Double) -> Double { smoothstep((clamp(weight, 0, 1) - 0.45) / 0.55) }
    let gb = grown(bang)
    if gb > 0 {
        let barW = 0.21 * u, barH = 0.5 * u, dot = 0.115 * u, gap = 0.1 * u
        let total = barH + gap + 2 * dot
        let p = still ? 1 : (t.truncatingRemainder(dividingBy: 2.6) + 2.6).truncatingRemainder(dividingBy: 2.6) / 2.6
        let alarm = p < 0.3 ? p / 0.3 : 1
        let jump = still ? 0 : sin(.pi * alarm)
        let turn = still ? 0 : 0.2 * sin((.pi * 2) * 3 * alarm) * (1 - alarm)
        let lift = -0.09 * u * jump
        let barY = -total / 2 + barH / 2, dotY = total / 2 - dot
        parts.append(MarkPart(
            shape: "bar", d: capsule(barW, barH), box: AvatarBox(x: -barW / 2, y: -barH / 2, width: barW, height: barH),
            x: cx, y: cy + (barY + lift) * gb, turn: turn, scale: gb))
        parts.append(MarkPart(
            shape: "dot", d: circle(dot), box: AvatarBox(x: -dot, y: -dot, width: 2 * dot, height: 2 * dot),
            x: cx, y: cy + (dotY + lift * 0.45) * gb, turn: turn, scale: gb))
    }
    let gd = grown(dots)
    if gd > 0 {
        let r = 0.1 * u, step = 0.31 * u
        for i in 0..<3 {
            let p = still ? 0 : ((t - Double(i) * 0.17).truncatingRemainder(dividingBy: 1.25) + 1.25)
                .truncatingRemainder(dividingBy: 1.25) / 1.25
            let hop = p < 0.4 ? sin(.pi * (p / 0.4)) : 0
            parts.append(MarkPart(
                shape: "dot3", d: circle(r), box: AvatarBox(x: -r, y: -r, width: 2 * r, height: 2 * r),
                x: cx + Double(i - 1) * step * gd, y: cy - 0.16 * u * hop * gd, turn: 0, scale: gd * (1 + 0.12 * hop)))
        }
    }
    return parts
}

func bodyScale(bang: Double, dots: Double) -> Double {
    1 - smoothstep(clamp(bang + dots, 0, 1) / 0.55)
}
