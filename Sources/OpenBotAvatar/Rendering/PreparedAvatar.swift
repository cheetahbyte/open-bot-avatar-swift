import Foundation

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

    private let volume: Volume

    /// Throws `AvatarValidationError` if the definition is invalid.
    public init(_ definition: AvatarDefinition, depth: Double = PreparedAvatar.defaultDepth) throws {
        let validated = try definition.validatedWithBody().get()
        let normalized = validated.definition
        let depth = Self.normalizedDepth(depth)
        let volume = buildVolume(eyes: normalized.eyes, volume: depth / Self.defaultDepth, body: validated.body)
        let hash = AvatarNoise.hash("\(normalized.id)|\(normalized.body.path)|\(numberText(depth))")
        let prefix = "oba-\(String(hash, radix: 36))"

        self.definition = normalized
        self.depth = depth
        self.volume = volume
        seed = AvatarNoise.hash(normalized.id)
        paths = volume.outlines.enumerated().map { index, outline in
            AvatarFramePath(id: "\(prefix)-\(index)", d: outline.d, segments: outline.segments, evenOdd: outline.evenOdd, box: outline.box)
        }

        let b = volume.bounds
        let center = b.center
        let reach = (volume.parts.map(\.depth).max() ?? 0) + 2 * EyeMetrics.lift
        let radius = (b.width * b.width + b.height * b.height + reach * reach).squareRoot() / 2
        let half = radius + AvatarPose.maxLift + AvatarPose.maxSway * (radius + b.y1 - center.y)
        extent = AvatarSquare(x: center.x - half, y: center.y - half, size: 2 * half)
    }

    static func normalizedDepth(_ depth: Double) -> Double {
        roundHalfUp(clamp(depth.isFinite ? depth : defaultDepth, 0, maxDepth) * 2) / 2
    }

    /// Where the look starts, as a fraction of the avatar's box: the middle of the eyes.
    package var lookOrigin: (x: Double, y: Double) {
        (clamp(definition.eyes.x / viewBoxSize, 0, 1), clamp(definition.eyes.y / viewBoxSize, 0, 1))
    }

    /// One frame. With `liveSize` (the rendered width in points) slices that would sit under a pixel
    /// apart are skipped, which small live avatars want and custom renderers may not.
    public func frame(_ options: AvatarFrameOptions = AvatarFrameOptions(), liveSize: Double? = nil) -> AvatarFrame {
        let pose = AvatarPose(AvatarPose.Input(
            seed: seed, time: options.time, mood: options.mood, gaze: options.gaze,
            reducedMotion: options.reducedMotion, view: options.view))
        let b = volume.bounds
        let pivot = b.center
        let basis = ViewBasis(yaw: pose.yaw, pitch: pose.pitch)
        let sideways = basis.showsSide
        let eyesX = definition.eyes.x, eyesY = definition.eyes.y

        let px = liveSize.flatMap { $0.isFinite && $0 > 0 ? roundHalfUp($0) : nil } ?? 0
        let gap = px > 0 ? sliceGap * viewBoxSize / px : 0

        var items: [(depth: Double, shape: AvatarFrameShape)] = []
        items.reserveCapacity(128)
        for (i, part) in volume.parts.enumerated() {
            let slices = sideways ? part.xSlices : part.zSlices
            let anchor = i == volume.eyePart ? Point(x: eyesX, y: eyesY) : part.center
            var last = -Double.infinity
            for (j, slice) in slices.enumerated() {
                let kept = slice.isCore || j == 0 || j == slices.count - 1 || slice.at - last >= gap
                if kept { last = slice.at }
                if !kept || basis.hides(inset: slice.inset, z: slice.at) { continue }
                let depth = sideways
                    ? basis.depth(x: slice.at, y: anchor.y, z: 0, pivot: pivot)
                    : basis.depth(x: anchor.x, y: anchor.y, z: slice.at, pivot: pivot)
                let matrix = sideways ? basis.sidePlane(x0: slice.at, pivot: pivot) : basis.plane(z: slice.at, pivot: pivot)
                let key = AvatarSliceKey(part: i, sideways: sideways, index: j)
                items.append((depth, .slice(key: key, path: slice.outline, matrix: matrix)))
            }
        }
        for index in 0..<2 where volume.face.isVisible(index, in: basis) {
            let z = volume.face.planeZ[index]
            let depth = basis.depth(x: eyesX, y: eyesY, z: z, pivot: pivot) + 1e-6
            items.append((depth, .eye(index: index, matrix: basis.plane(z: z, pivot: pivot), mark: volume.face.mark(index, pose))))
        }
        // JavaScript's sort is stable, so ties keep their drawing order to match its output.
        let order = items.indices.sorted { items[$0].depth != items[$1].depth ? items[$0].depth < items[$1].depth : $0 < $1 }
        return AvatarFrame(
            name: definition.name, color: options.color, ink: options.eyeColor, paths: paths,
            root: rootMatrix(pose), shapes: order.map { items[$0].shape })
    }

    private func rootMatrix(_ pose: AvatarPose) -> AvatarMatrix {
        let b = volume.bounds
        let r = pose.roll * .pi / 180
        let rotation = AvatarMatrix(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), e: 0, f: 0)
        let squash = AvatarMatrix(a: pose.scaleX, b: 0, c: 0, d: pose.scaleY, e: 0, f: 0)
        return AvatarMatrix.translation(0, pose.lift)
            .concatenating(rotation.concatenating(squash).about(b.center.x, b.y1))
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

        func value(_ key: CacheKey) -> PreparedAvatar? {
            lock.withLock { entries[key] }
        }

        func insert(_ value: PreparedAvatar, _ key: CacheKey) {
            lock.withLock {
                if entries.updateValue(value, forKey: key) == nil { order.append(key) }
                if order.count > PreparedAvatar.cacheLimit { entries[order.removeFirst()] = nil }
            }
        }
    }

    /// How many prepared avatars stay shared. Painters are cached to the same limit, because each
    /// keeps its avatar alive.
    package static let cacheLimit = 64

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
