import AppKit
import ServiceManagement

@main
@MainActor
final class UsageBarApp: NSObject, NSApplicationDelegate {
    private var monitor: UsageMonitor?
    private var statusBar: StatusBarController?

    static func main() {
        // These maintenance modes are used only by uninstall.sh; they do not touch CLI credentials.
        if CommandLine.arguments.contains("--unregister-launch-at-login") {
            if #available(macOS 13.0, *) { try? SMAppService.mainApp.unregister() }
            return
        }
        if CommandLine.arguments.contains("--remove-usagebar-keychain") {
            try? KeychainStore.deleteAllUsageBarCredentials()
            return
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
    }
}
