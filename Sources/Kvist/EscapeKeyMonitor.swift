import AppKit
import SwiftUI

struct EscapeKeyMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self, weak view] event in
                guard event.window === view?.window,
                      event.keyCode == 53,
                      NSEvent.pressedMouseButtons == 0 else {
                    return event
                }
                let shortcutModifiers = event.modifierFlags.intersection([
                    .command,
                    .control,
                    .option,
                    .shift
                ])
                guard shortcutModifiers.isEmpty else { return event }
                self?.action()
                return nil
            }
        }

        func uninstall() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
