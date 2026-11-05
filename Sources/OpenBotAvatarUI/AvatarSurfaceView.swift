import OSLog
import OpenBotAvatar
import QuartzCore

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

    var followsPointer: Bool { gaze == .pointer && !still }
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

/// Runs an avatar's frame loop: prepares the geometry off the main thread, steps the animator and
/// paints to an `AvatarCanvas`. Pauses out of view and ignores input.
final class AvatarSurfaceView: AvatarPlatformView {
    private var state: AvatarSurfaceState?
    private var prepared: PreparedAvatar?
    private var preparing: Task<Void, Never>?
    private var animator = AvatarAnimator()
    private var canvas = AvatarCanvas()
    private var pointer = AvatarPointer()
    private var link: CADisplayLink?
    private let linkTarget = DisplayLinkTarget()

    init() {
        super.init(frame: .zero)
        linkTarget.owner = self
        clipsToBounds = false
        #if os(macOS)
            wantsLayer = true
            layer?.masksToBounds = false
            layer?.addSublayer(canvas.layer)
        #else
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.addSublayer(canvas.layer)
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
        syncPointer()
        redraw()
    }

    private func prepare(_ state: AvatarSurfaceState) {
        preparing?.cancel()
        preparing = nil
        if let ready = PreparedAvatar.cachedIfReady(state.definition, depth: state.depth) {
            prepared = ready
            return
        }
        let (definition, depth) = (state.definition, state.depth)
        preparing = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let ready = try PreparedAvatar.cached(definition, depth: depth)
                    _ = AvatarPainter.cached(ready)
                    return ready
                }
            }.value
            guard !Task.isCancelled, let self else { return }
            switch result {
            case let .success(ready):
                self.prepared = ready
                self.redraw()
            case let .failure(error):
                log.error("open-bot-avatar: render failed: \(error.localizedDescription, privacy: .public)")
                self.prepared = nil
                self.canvas.clear()
                self.setRunning(false)
            }
        }
    }

    private func syncPointer() {
        pointer.follow(in: state?.followsPointer == true ? window : nil)
    }

    // MARK: Frames

    /// `AvatarView` keeps this view square.
    private var size: CGFloat { bounds.width }

    /// Draws now, whether or not the view is on screen, then keeps going if the avatar is animated.
    private func redraw() {
        setRunning(window != nil && size > 0 && draw())
    }

    fileprivate func tick() {
        // Offscreen the link stays up, so the avatar picks up again with no scroll callback.
        if isOnScreen { setRunning(draw()) }
    }

    /// Returns whether more frames are needed.
    private func draw() -> Bool {
        guard let state, let prepared else { return false }
        if state.still {
            var gaze: AvatarGaze?
            if case let .look(look) = state.gaze { gaze = AvatarGaze(x: look.x, y: look.y) }
            let options = AvatarFrameOptions(mood: .settled(state.mood), gaze: gaze, view: state.rotation, reducedMotion: true)
            paint(prepared.frame(options), prepared, state)
            return false
        }
        let now = CACurrentMediaTime()
        let step = animator.step(AvatarAnimator.Input(
            now: now, mood: state.mood, target: lookTarget(state, prepared), hold: state.gaze == .hold,
            reducedMotion: state.reducedMotion))
        let options = AvatarFrameOptions(
            time: now, mood: step.mood, gaze: step.gaze, view: state.rotation, reducedMotion: state.reducedMotion)
        paint(prepared.frame(options, liveSize: size), prepared, state)
        return !state.reducedMotion || step.moving || state.followsPointer
    }

    private func lookTarget(_ state: AvatarSurfaceState, _ prepared: PreparedAvatar) -> AvatarLook? {
        switch state.gaze {
        case let .look(look):
            return look
        case .pointer:
            guard let location = pointer.location(in: self) else { return nil }
            return AvatarFollowState.look(at: (location.x, location.y), box: (0, 0, size, size), origin: prepared.lookOrigin)
        case .idle, .hold:
            return nil
        }
    }

    private func paint(_ frame: AvatarFrame, _ prepared: PreparedAvatar, _ state: AvatarSurfaceState) {
        canvas.paint(frame, of: prepared, size: size, scale: contentScale, fill: state.fill, ink: state.ink)
    }

    private func setRunning(_ running: Bool) {
        guard running else {
            link?.invalidate()
            link = nil
            return
        }
        let range = size < smallSize ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30) : CAFrameRateRange.default
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

    // MARK: Platform

    #if os(macOS)
        private var isOnScreen: Bool {
            guard let window, !isHiddenOrHasHiddenAncestor else { return false }
            return window.occlusionState.contains(.visible) && !visibleRect.isEmpty
        }

        private var contentScale: CGFloat { window?.backingScaleFactor ?? 1 }

        override var isFlipped: Bool { true }
        // Clicks and hovers belong to the views around the avatar.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            redraw()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncPointer()
            redraw()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            redraw()
        }
    #else
        private var isOnScreen: Bool {
            guard let window, sequence(first: self as UIView, next: \.superview).allSatisfy({ !$0.isHidden && $0.alpha > 0 }) else {
                return false
            }
            return window.bounds.insetBy(dx: -100, dy: -100).intersects(convert(bounds, to: window))
        }

        private var contentScale: CGFloat { traitCollection.displayScale }

        override func layoutSubviews() {
            super.layoutSubviews()
            redraw()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncPointer()
            redraw()
        }
    #endif
}
