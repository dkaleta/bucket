#if os(macOS)
import AppKit
import SwiftUI

struct CanvasInput: NSViewRepresentable {
    var onZoom: (CGFloat, CGPoint) -> Void
    var onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.onZoom = onZoom
        view.onPan = onPan
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.onZoom = onZoom
        view.onPan = onPan
    }

    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.stopMonitoring() }

    final class InputView: NSView {
        var onZoom: ((CGFloat, CGPoint) -> Void)?
        var onPan: ((CGSize) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                if event.type == .magnify {
                    self.onZoom?(max(0.05, 1 + event.magnification), point)
                } else if event.modifierFlags.contains(.command) {
                    let delta = min(max(event.scrollingDeltaY, -12), 12)
                    self.onZoom?(exp(delta * 0.008), point)
                } else {
                    self.onPan?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                }
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stopMonitoring() }
    }
}
#endif
