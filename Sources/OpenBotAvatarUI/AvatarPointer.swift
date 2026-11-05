import OpenBotAvatar

#if os(macOS)
    import AppKit

    /// Where the pointer is. The mouse can be read at any time, so following holds no state.
    @MainActor
    struct AvatarPointer {
        func follow(in window: NSWindow?) {}

        /// The pointer in `view`'s coordinates, nil when it's outside the active window.
        func location(in view: NSView) -> CGPoint? {
            guard let window = view.window, NSApp?.isActive == true else { return nil }
            let mouse = NSEvent.mouseLocation
            guard window.frame.contains(mouse) else { return nil }
            return view.convert(window.convertPoint(fromScreen: mouse), from: nil)
        }
    }
#else
    import UIKit

    /// Where the pointer is, watched through the window's shared recognizer while following.
    @MainActor
    struct AvatarPointer {
        private var recognizer: AvatarPointerRecognizer?

        /// Follows the pointer in `window`, or stops when it's nil.
        mutating func follow(in window: UIWindow?) {
            guard window != recognizer?.view else { return }
            recognizer?.release()
            recognizer = window.map(AvatarPointerRecognizer.retained)
        }

        /// The pointer in `view`'s coordinates, nil when there is none.
        func location(in view: UIView) -> CGPoint? {
            guard let window = view.window else { return nil }
            return recognizer?.location.map { view.convert($0, from: window) }
        }
    }

    /// Watches touches and hovers anywhere in a window without taking part in gesture handling, so
    /// avatars can look at a finger that is scrolling something else. One per window, shared by every
    /// following avatar and removed after the last one lets go.
    private final class AvatarPointerRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private var tracked: UITouch?
        private var touch: CGPoint?
        private var hover: CGPoint?
        private var users = 0
        private var hoverRecognizer: UIHoverGestureRecognizer?

        /// The pointer in window coordinates.
        var location: CGPoint? { touch ?? hover }

        static func retained(by window: UIWindow) -> AvatarPointerRecognizer {
            let existing = window.gestureRecognizers?.lazy.compactMap { $0 as? AvatarPointerRecognizer }.first
            let recognizer = existing ?? AvatarPointerRecognizer(window: window)
            recognizer.users += 1
            return recognizer
        }

        private convenience init(window: UIWindow) {
            self.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
            window.addGestureRecognizer(self)
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered))
            hover.delegate = self
            window.addGestureRecognizer(hover)
            hoverRecognizer = hover
        }

        func release() {
            users -= 1
            guard users == 0 else { return }
            if let hoverRecognizer { view?.removeGestureRecognizer(hoverRecognizer) }
            view?.removeGestureRecognizer(self)
        }

        @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed: hover = recognizer.location(in: view)
            default: hover = nil
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            tracked = tracked ?? touches.first
            location(of: tracked)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            location(of: tracked)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            lift(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            lift(touches)
        }

        private func location(of touch: UITouch?) {
            self.touch = touch?.location(in: view)
        }

        private func lift(_ touches: Set<UITouch>) {
            guard let tracked, touches.contains(tracked) else { return }
            self.tracked = nil
            touch = nil
            state = .failed
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
#endif
