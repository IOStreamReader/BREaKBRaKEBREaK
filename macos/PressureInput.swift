import AppKit
import WebKit

final class ForceWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        view?.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
        return view
    }
}

/// Listens to the separate AppKit pressure stream, never mouse-event pressure.
final class PressureInput {
    private var monitor: Any?
    private var timer: Timer?
    private var value: Double = 0
    private var peak: Double = 0
    private var dirty = false
    private var gesture = 0
    private var needsFreshPress = true
    private(set) var verified = false
    private var active = false
    private var mouseWasDown = false
    var window: NSWindow?
    var onSample: (([String: Any]) -> Void)?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.pressure, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            switch event.type {
            case .leftMouseDown:
                self.gesture += 1
                self.needsFreshPress = false
                NSPressureConfiguration(pressureBehavior: .primaryGeneric).set()
            case .leftMouseUp:
                self.release()
            case .pressure:
                self.receive(event)
                return nil // Prevent lookup / deep-click behaviors in WebKit.
            default: break
            }
            return event
        }
        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // A release can arrive outside the window; never retain a stuck brake.
            let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
            if !mouseDown && (self.value > 0 || self.mouseWasDown) { self.release() }
            self.mouseWasDown = mouseDown
            self.flush()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func setSession(_ enabled: Bool) {
        active = enabled
        needsFreshPress = true
        peak = 0
        release()
    }

    func deactivate() {
        needsFreshPress = true
        peak = 0
        release()
    }

    func beginProbe() {
        verified = false
        active = false
        needsFreshPress = true
        peak = 0
        release()
    }

    private func receive(_ event: NSEvent) {
        if event.stage == 0 { release(); return }
        // .primaryGeneric supplies a single continuous stage. Never combine stages.
        guard event.stage == 1, event.pressureBehavior != .unknown else { return }
        let raw = Double(event.pressure)
        guard raw.isFinite else { return }
        if raw > 0 { verified = true }
        value = min(1, max(0, raw))
        if active && needsFreshPress { value = 0 }
        peak = max(peak, value)
        dirty = true
    }

    private func release() {
        value = 0
        // Keep peaks until the JS sample consumes them, including a short press.
        dirty = true
    }

    private func flush() {
        guard dirty else { return }
        onSample?(["value": value, "peak": peak, "verified": verified, "gesture": gesture,
                   "mouseDown": NSEvent.pressedMouseButtons & 1 != 0])
        peak = 0
        dirty = false
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
    }
}
