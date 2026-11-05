import Foundation

/// Eyes sit this far above the surface so they never touch the body planes.
private let eyeLift = 1.5
/// Minimum facing of the surface under an eye for it to be drawn.
private let eyeFacing = 0.22
/// The hop, and the share of a point's distance from the base that roll and squash can move it.
private let poseLift = 4.0
private let poseSway = 0.2
/// Closest on-screen spacing, points, between cross-sections a small live avatar keeps.
private let sliceGap = 0.75

/// A validated definition with its volume built, ready to produce frames. Building is the expensive
/// step and frames are cheap, so keep one per definition and depth; `cached` does that for you.
public final class PreparedAvatar: Sendable {
    /// `depth` value for the natural inferred volume.
    public static let defaultDepth = 6.0
    private static let maxDepth = 14.0

    /// The normalized definition.
    public let definition: AvatarDefinition
    public let depth: Double
    /// Seeds the avatar's motion, so equal ids move alike.
    public let seed: UInt32
    public let paths: [AvatarFramePath]
    /// A square that holds the avatar at every view and pose.
    public let extent: AvatarSquare

    let volume: Volume
    private let gazeLimits: GazeRange

    /// Throws `AvatarValidationError` if the definition is invalid.
    public init(_ definition: AvatarDefinition, depth: Double = PreparedAvatar.defaultDepth) throws {
        let normalized = try definition.validated().get()
        let depth = Self.normalizedDepth(depth)
        let body: BodyAnalysis
        do {
            body = try analyzeBody(normalized.body.path)
        } catch {
            throw AvatarValidationError(errors: ["body.path: \((error as? PathError)?.message ?? "\(error)")"])
        }
        var volume = buildVolume(normalized, volume: depth / Self.defaultDepth, body: body)
        let hash = AvatarNoise.hash("\(normalized.id)|\(normalized.body.path)|\(numberText(depth))")
        let prefix = "oba-\(String(hash, radix: 36))"

        var table: [AvatarFramePath] = []
        var indices: [String: Int] = [:]
        func intern(_ slice: inout VolumeSlice) {
            if let index = indices[slice.d] {
                slice.pathIndex = index
                return
            }
            slice.pathIndex = table.count
            indices[slice.d] = table.count
            table.append(AvatarFramePath(
                id: "\(prefix)-\(table.count)", d: slice.d, segments: slice.segments, evenOdd: slice.evenOdd, box: slice.box))
        }
        for p in volume.parts.indices {
            for s in volume.parts[p].zSlices.indices { intern(&volume.parts[p].zSlices[s]) }
            for s in volume.parts[p].xSlices.indices { intern(&volume.parts[p].xSlices[s]) }
        }

        self.definition = normalized
        self.depth = depth
        self.volume = volume
        seed = AvatarNoise.hash(normalized.id)
        paths = table
        var drawnEyes = normalized.eyes
        drawnEyes.scale = volume.eyeScale
        gazeLimits = gazeRange(body.polys, drawnEyes)

        let b = volume.bounds
        let center = b.center
        let reach = max(volume.parts.map(\.depth).max() ?? 0, 0) + 2 * eyeLift
        let radius = (b.width * b.width + b.height * b.height + reach * reach).squareRoot() / 2
        let half = radius + poseLift + poseSway * (radius + b.maxY - center.y)
        extent = AvatarSquare(x: center.x - half, y: center.y - half, size: 2 * half)
    }

    static func normalizedDepth(_ depth: Double) -> Double {
        roundHalfUp(clamp(depth.isFinite ? depth : defaultDepth, 0, maxDepth) * 2) / 2
    }

    /// One frame. With `liveSize` (the rendered width in points) slices that would sit under a pixel
    /// apart are skipped, which small live avatars want and custom renderers may not.
    public func frame(_ options: AvatarFrameOptions = AvatarFrameOptions(), liveSize: Double? = nil) -> AvatarFrame {
        let pose = AvatarPose(AvatarPose.Input(
            seed: seed, time: options.time.isFinite ? options.time : 0, mood: options.mood, gaze: options.gaze,
            reducedMotion: options.reducedMotion, view: options.view))
        let b = volume.bounds
        let pivot = b.center
        let basis = ViewBasis(yaw: pose.yaw, pitch: pose.pitch)
        let stack = basis.activeStack
        let eyesX = definition.eyes.x, eyesY = definition.eyes.y

        // Screen shift per unit of depth, and the smallest on-screen size of an in-plane inset:
        // z-slices hidden behind the core add nothing to the silhouette or the paint.
        let sweep = hypot(basis.sinYaw, basis.cosYaw * basis.sinPitch)
        let insetScale = min(abs(basis.cosYaw), abs(basis.cosPitch))
        let px = liveSize.flatMap { $0.isFinite && $0 > 0 ? roundHalfUp($0) : nil } ?? 0
        let gap = px > 0 ? sliceGap * 100 / px : 0

        var items: [(depth: Double, shape: AvatarFrameShape)] = []
        items.reserveCapacity(128)
        for (i, part) in volume.parts.enumerated() {
            let (slices, sideways) = stack == .z ? (part.zSlices, false) : (part.xSlices, true)
            let anchor = i == volume.eyePart ? Point(x: eyesX, y: eyesY) : part.center
            var last = -Double.infinity
            for (j, slice) in slices.enumerated() {
                let core = slice.axis == .z && slice.at == 0 && slice.inset == 0
                let kept = core || j == 0 || j == slices.count - 1 || slice.at - last >= gap
                if kept { last = slice.at }
                let hidden = slice.axis == .z && slice.inset > 0 && abs(slice.at) * sweep <= slice.inset * insetScale
                if !kept || hidden { continue }
                // Depth keys are taken under the eyes for the eye part, so only depth decides eye-vs-body order there.
                let depth = sideways
                    ? basis.depth(x: slice.at, y: anchor.y, z: 0, pivot: pivot)
                    : basis.depth(x: anchor.x, y: anchor.y, z: slice.at, pivot: pivot)
                let matrix = sideways ? basis.sidePlane(x0: slice.at, pivot: pivot) : basis.plane(z: slice.at, pivot: pivot)
                let key = AvatarSliceKey(part: i, sideways: sideways, index: j)
                items.append((depth, .slice(key: key, path: slice.pathIndex, matrix: matrix)))
            }
        }
        // Painted on the surface; each eye goes once the surface under it turns away.
        for index in 0..<2 where volume.eyeNormals[index].allSatisfy({ basis.facing($0) > eyeFacing }) {
            let z = volume.eyeZ[index] + eyeLift
            let depth = basis.depth(x: eyesX, y: eyesY, z: z, pivot: pivot) + 1e-6
            items.append((depth, .eye(index: index, matrix: basis.plane(z: z, pivot: pivot), mark: eyeMark(index, pose))))
        }
        // Stable like the engine's sort: ties keep their drawing order.
        let order = items.indices.sorted { items[$0].depth != items[$1].depth ? items[$0].depth < items[$1].depth : $0 < $1 }
        return AvatarFrame(
            name: definition.name, color: options.color, ink: options.eyeColor, paths: paths,
            root: rootMatrix(pose), shapes: order.map { items[$0].shape })
    }

    private func eyeMark(_ index: Int, _ pose: AvatarPose) -> AvatarEyeMark {
        let scale = volume.eyeScale
        let w = EyeMetrics.width * scale, h = EyeMetrics.height * scale
        let dx = pose.gazeX * (pose.gazeX >= 0 ? gazeLimits.right : gazeLimits.left) * EyeMetrics.gazeX * scale
        let dy = pose.gazeY * (pose.gazeY >= 0 ? gazeLimits.down : gazeLimits.up) * EyeMetrics.gazeY * scale
        let center = eyeCenters(definition.eyes)[index]
        let x = center.x + dx, y = center.y + dy
        if pose.eyeShape == .happy {
            let halfWidth = w * HappyArc.halfWidth, base = y + h * HappyArc.base
            return .arc(
                startX: x - halfWidth, startY: base, controlX: x, controlY: y - h * HappyArc.peak,
                endX: x + halfWidth, endY: base, strokeWidth: w * HappyArc.stroke)
        }
        let squint = index == 0 ? pose.squintLeft : pose.squintRight
        // Lids close toward a point below center.
        let open = max(h * max(0.09, (1 - pose.blink) * (1 - squint * 0.4)), w * 0.55)
        let shift = (h - open) * 0.18
        return .pill(x: x - w / 2, y: y + shift - open / 2, width: w, height: open, radius: min(w, open) / 2)
    }

    private func rootMatrix(_ pose: AvatarPose) -> AvatarMatrix {
        let b = volume.bounds
        let r = pose.roll * .pi / 180
        let rotation = AvatarMatrix(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), e: 0, f: 0)
        let squash = AvatarMatrix(a: pose.scaleX, b: 0, c: 0, d: pose.scaleY, e: 0, f: 0)
        return AvatarMatrix.translation(0, pose.lift)
            .concatenating(rotation.concatenating(squash).about((b.minX + b.maxX) / 2, b.maxY))
    }
}

extension PreparedAvatar {
    private struct CacheKey: Hashable {
        var definition: AvatarDefinition
        var depth: Double
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [CacheKey: PreparedAvatar] = [:]
        private var order: [CacheKey] = []
        private let limit = 64

        func value(_ key: CacheKey) -> PreparedAvatar? {
            lock.withLock { entries[key] }
        }

        func insert(_ value: PreparedAvatar, _ key: CacheKey) {
            lock.withLock {
                if entries.updateValue(value, forKey: key) == nil { order.append(key) }
                if order.count > limit { entries[order.removeFirst()] = nil }
            }
        }
    }

    private static let cache = Cache()

    /// The shared prepared avatar for a definition and depth, if it has been built. Never blocks on
    /// geometry, so it suits the main thread.
    public static func cachedIfReady(_ definition: AvatarDefinition, depth: Double = defaultDepth) -> PreparedAvatar? {
        cache.value(CacheKey(definition: definition, depth: normalizedDepth(depth)))
    }

    /// The shared prepared avatar for a definition and depth, built on first use.
    public static func cached(_ definition: AvatarDefinition, depth: Double = defaultDepth) throws -> PreparedAvatar {
        let key = CacheKey(definition: definition, depth: normalizedDepth(depth))
        if let hit = cache.value(key) { return hit }
        let prepared = try PreparedAvatar(definition, depth: depth)
        cache.insert(prepared, key)
        return prepared
    }
}
