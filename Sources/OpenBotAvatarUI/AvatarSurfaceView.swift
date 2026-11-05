import OSLog
import OpenBotAvatar
import QuartzCore
import SwiftUI

#if os(macOS)
    import AppKit
    typealias AvatarPlatformView = NSView
#else
    import UIKit
    typealias AvatarPlatformView = UIView
#endif

/// What a surface shows. Colors are resolved, so a surface follows appearance changes when the
/// SwiftUI view hands it new ones.
struct AvatarSurfaceState: Equatable {
    var definition: AvatarDefinition
    var depth: Double
    var mood: AvatarMood
    var gaze: AvatarGazeBehavior
    var rotation: AvatarViewRotation?
    var reducedMotion: Bool
    var still: Bool
    var fill: CGColor
    var ink: CGColor
}

/// Avatars smaller than this, in points, redraw at 30 Hz: the difference doesn't show, and screens
/// often hold many of them.
private let smallSize: CGFloat = 128
private let log = Logger(subsystem: "OpenBotAvatar", category: "render")

private final class DisplayLinkTarget: NSObject {
    weak var owner: AvatarSurfaceView?

    @MainActor @objc func tick(_ link: CADisplayLink) {
        if let owner { owner.tick() } else { link.invalidate() }
    }
}

/// Paints a frame loop into one bitmap on one layer, so an avatar costs one layer however many
/// slices it shows. The layer overhangs the view by the avatar's reach and ignores input.
final class AvatarSurfaceView: AvatarPlatformView {
    private var state: AvatarSurfaceState?
    private var prepared: PreparedAvatar?
    private var preparing: Task<Void, Never>?
    private var animator = AvatarAnimator()
    private var link: CADisplayLink?
    private let linkTarget = DisplayLinkTarget()
    private let content = CALayer()

    private var bitmap: CGContext?
    private var bitmapKey: BitmapKey?
    private var fit: AvatarSquare?
    private var left = 0
    private var top = 0

    private struct BitmapKey: Equatable {
        var size: CGFloat
        var scale: CGFloat
        var avatar: ObjectIdentifier
    }

    #if os(iOS)
        private var pointerRecognizer: AvatarPointerRecognizer?
    #endif

    init() {
        super.init(frame: .zero)
        linkTarget.owner = self
        content.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "contentsScale": NSNull()]
        #if os(macOS)
            wantsLayer = true
            clipsToBounds = false
            layer?.masksToBounds = false
            layer?.addSublayer(content)
        #else
            isUserInteractionEnabled = false
            backgroundColor = .clear
            clipsToBounds = false
            layer.addSublayer(content)
            registerForTraitChanges([UITraitDisplayScale.self]) { (view: AvatarSurfaceView, _) in view.redraw() }
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AvatarSurfaceView is created in code") }

    func update(_ next: AvatarSurfaceState) {
        guard next != state else { return }
        let geometryChanged = next.definition != state?.definition || next.depth != state?.depth
        state = next
        if geometryChanged { prepare(next) }
        syncPointerTracking()
        redraw()
    }

    private func prepare(_ state: AvatarSurfaceState) {
        preparing?.cancel()
        preparing = nil
        if let ready = PreparedAvatar.cachedIfReady(state.definition, depth: state.depth) {
            install(ready)
            return
        }
        let (definition, depth) = (state.definition, state.depth)
        preparing = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PreparedAvatar.cached(definition, depth: depth) }
            }.value
            guard !Task.isCancelled, let self else { return }
            switch result {
            case let .success(ready):
                self.install(ready)
                self.redraw()
            case let .failure(error):
                log.error("open-bot-avatar: render failed: \(error.localizedDescription, privacy: .public)")
                self.install(nil)
            }
        }
    }

    private func install(_ next: PreparedAvatar?) {
        prepared = next
        animator.reset()
        if next == nil {
            content.contents = nil
            setRunning(false)
        }
    }

    // MARK: Frames

    private var box: (origin: CGPoint, size: CGFloat) {
        let size = min(bounds.width, bounds.height)
        return (CGPoint(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2), size)
    }

    private var isOnScreen: Bool {
        guard let window, !isHiddenOrHasHiddenAncestorOrInvisible else { return false }
        #if os(macOS)
            return window.occlusionState.contains(.visible) && !visibleRect.isEmpty
        #else
            return window.bounds.insetBy(dx: -100, dy: -100).intersects(convert(bounds, to: window))
        #endif
    }

    private var isHiddenOrHasHiddenAncestorOrInvisible: Bool {
        #if os(macOS)
            isHiddenOrHasHiddenAncestor
        #else
            isHidden || alpha == 0
        #endif
    }

    private var contentScale: CGFloat {
        #if os(macOS)
            window?.backingScaleFactor ?? 2
        #else
            traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        #endif
    }

    /// Draws now, whether or not the view is on screen, then keeps going if the avatar is animated.
    fileprivate func redraw() {
        guard window != nil, let state, let prepared, box.size > 0 else {
            setRunning(false)
            return
        }
        setRunning(draw(state, prepared))
    }

    fileprivate func tick() {
        guard let state, let prepared else { return setRunning(false) }
        // Offscreen the link stays up, so the avatar picks up again with no scroll callback.
        if isOnScreen { setRunning(draw(state, prepared)) }
    }

    /// Returns whether more frames are needed.
    private func draw(_ state: AvatarSurfaceState, _ prepared: PreparedAvatar) -> Bool {
        let size = box.size
        guard size > 0 else { return false }
        if state.still {
            var gaze: AvatarGaze?
            if case let .look(look) = state.gaze { gaze = AvatarGaze(x: look.x, y: look.y) }
            let options = AvatarFrameOptions(
                mood: .settled(state.mood), gaze: gaze, view: state.rotation, reducedMotion: true)
            paint(prepared.frame(options), prepared, state)
            return false
        }
        let reduced = state.reducedMotion
        let now = CACurrentMediaTime()
        var hold = false
        if case .hold = state.gaze { hold = true }
        let step = animator.step(AvatarAnimator.Input(
            now: now, mood: state.mood, target: lookTarget(state, prepared), hold: hold, reducedMotion: reduced))
        let options = AvatarFrameOptions(
            time: now, mood: step.mood, gaze: step.gaze, view: state.rotation, reducedMotion: reduced)
        paint(prepared.frame(options, liveSize: size), prepared, state)
        return !reduced || step.moving || state.gaze == .pointer
    }

    private func lookTarget(_ state: AvatarSurfaceState, _ prepared: PreparedAvatar) -> AvatarLook? {
        switch state.gaze {
        case let .look(look):
            return look
        case .pointer:
            guard let pointer = pointerLocation else { return nil }
            let (origin, size) = box
            let eyes = prepared.definition.eyes
            return AvatarFollowState.look(
                at: (pointer.x, pointer.y), box: (origin.x, origin.y, size, size),
                origin: (min(1, max(0, eyes.x / 100)), min(1, max(0, eyes.y / 100))))
        case .idle, .hold:
            return nil
        }
    }

    private func paint(_ frame: AvatarFrame, _ prepared: PreparedAvatar, _ state: AvatarSurfaceState) {
        let (origin, size) = box
        let scale = contentScale
        let unit = Double(size * scale) / 100
        let (matrices, bounds) = frame.placement()
        let key = BitmapKey(size: size, scale: scale, avatar: ObjectIdentifier(prepared))
        let previous = bitmapKey == key ? fit : nil
        let next = AvatarBitmapFit.square(previous: previous, bounds: bounds, cap: prepared.extent)
        if bitmap == nil || previous != next {
            bitmapKey = key
            fit = next
            // Whole device pixels, so the bitmap is never resampled.
            left = Int((next.x * unit).rounded(.down))
            top = Int((next.y * unit).rounded(.down))
            let side = Int((next.size * unit).rounded(.up)) + 1
            bitmap = AvatarBitmap.makeContext(side: side)
            content.contentsScale = scale
            content.frame = CGRect(
                x: origin.x + CGFloat(left) / scale, y: origin.y + CGFloat(top) / scale,
                width: CGFloat(side) / scale, height: CGFloat(side) / scale)
        }
        guard let bitmap else { return }
        bitmap.clear(CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        bitmap.saveGState()
        bitmap.translateBy(x: CGFloat(-left), y: CGFloat(bitmap.height + top))
        bitmap.scaleBy(x: unit, y: -unit)
        AvatarPainter.cached(prepared).paint(frame, matrices: matrices, in: bitmap, fill: state.fill, ink: state.ink)
        bitmap.restoreGState()
        content.contents = bitmap.makeImage()
    }

    private func setRunning(_ running: Bool) {
        guard running, window != nil else {
            link?.invalidate()
            link = nil
            return
        }
        let range = box.size < smallSize ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30) : CAFrameRateRange.default
        if let link {
            if link.preferredFrameRateRange != range { link.preferredFrameRateRange = range }
            return
        }
        #if os(macOS)
            let next = displayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.tick))
        #else
            let next = CADisplayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.tick))
        #endif
        next.preferredFrameRateRange = range
        next.add(to: .main, forMode: .common)
        link = next
    }

    // MARK: Pointer

    /// The pointer in this view's coordinates (y down), nil when there is none.
    private var pointerLocation: CGPoint? {
        guard let window else { return nil }
        #if os(macOS)
            let mouse = NSEvent.mouseLocation
            guard NSApp?.isActive == true, window.frame.contains(mouse) else { return nil }
            return convert(window.convertPoint(fromScreen: mouse), from: nil)
        #else
            return pointerRecognizer?.location.map { convert($0, from: window) }
        #endif
    }

    private func syncPointerTracking() {
        #if os(iOS)
            let wanted = window.flatMap { state?.gaze == .pointer && state?.still == false ? $0 : nil }
            guard wanted != pointerRecognizer?.view else { return }
            pointerRecognizer?.release()
            pointerRecognizer = wanted.map(AvatarPointerRecognizer.retained)
        #endif
    }

    // MARK: Layout

    #if os(macOS)
        override var isFlipped: Bool { true }
        // Clicks and hovers belong to the views around the avatar.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            redraw()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            redraw()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            redraw()
        }
    #else
        override func layoutSubviews() {
            super.layoutSubviews()
            redraw()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncPointerTracking()
            redraw()
        }
    #endif
}
