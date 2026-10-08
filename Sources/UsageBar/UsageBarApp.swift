import AppKit
import ServiceManagement

enum LaunchAtLoginRemoval {
    struct UnsupportedOS: Error {}

    static func exitCode(unregister: () throws -> Void) -> Int32 {
        do {
            try unregister()
            return EXIT_SUCCESS
        } catch {
            return EXIT_FAILURE
        }
    }
}

@main
@MainActor
final class UsageBarApp: NSObject, NSApplicationDelegate {
    private var monitor: UsageMonitor?
    private var statusBar: StatusBarController?
    private var wakeObserver: NSObjectProtocol?

    static func main() {
        if CommandLine.arguments.contains("--unregister-launch-at-login") {
            let code = LaunchAtLoginRemoval.exitCode {
                if #available(macOS 13.0, *) {
                    try SMAppService.mainApp.unregister()
                } else {
                    throw LaunchAtLoginRemoval.UnsupportedOS()
                }
            }
            if code != EXIT_SUCCESS {
                // Never log potentially sensitive framework error descriptions.
                fputs("UsageBar: unable to unregister Launch at Login.\n", stderr)
            }
            exit(code)
        }
        let app = NSApplication.shared
        let delegate = UsageBarApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = UsageMonitor()
        self.monitor = monitor
        statusBar = StatusBarController(monitor: monitor)
        monitor.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak monitor] _ in
            Task { @MainActor in monitor?.refresh(manual: true) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
