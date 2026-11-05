#if os(iOS)
    import UIKit

    /// Watches touches and hovers anywhere in a window without taking part in gesture handling, so
    /// avatars can look at a finger that is scrolling something else. One per window, shared by every
    /// following avatar and removed after the last one lets go.
    final class AvatarPointerRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
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

        private func track(_ touches: Set<UITouch>) {
            touch = touches.first.map { $0.location(in: view) }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { track(touches) }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { track(touches) }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            touch = nil
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            touch = nil
            state = .failed
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
#endif
