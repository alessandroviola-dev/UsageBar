import AppKit
import ServiceManagement

@MainActor
final class StatusBarController: NSObject {
    private let monitor: UsageMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var providersWindow: ProvidersWindowController?

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        super.init()
        guard let button = statusItem.button else { return }
        button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = "Usage ?"
        monitor.onChange = { [weak self] in self?.update() }
        update()
    }

    func update() {
        statusItem.button?.title = UsageFormatting.statusTitle(snapshot: monitor.snapshot)
        let menu = NSMenu()
        let providerName = monitor.activeProvider.displayName
        let heading = NSMenuItem(title: providerName, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        if let snapshot = monitor.snapshot {
            for window in [snapshot.primary, snapshot.secondary].compactMap({ $0 }) {
                let reset = UsageFormatting.resetText(window.resetAt) ?? ""
                let item = NSMenuItem(title: "\(window.label)\t\(window.remainingPercent)%\t\(reset)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        } else {
            let item = NSMenuItem(title: monitor.lastError ? "Last update failed" : "No usage data", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        let switchItem = NSMenuItem(title: "Switch Provider", action: nil, keyEquivalent: "")
        let switchMenu = NSMenu()
        for provider in monitor.providers {
            let item = NSMenuItem(title: provider.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.id
            if provider.id == monitor.activeProviderID { item.state = .on }
            switchMenu.addItem(item)
        }
        switchItem.submenu = switchMenu
        menu.addItem(switchItem)

        let providers = NSMenuItem(title: "Providers…", action: #selector(showProviders), keyEquivalent: ",")
        providers.target = self
        menu.addItem(providers)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        if #available(macOS 13.0, *) { login.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit UsageBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func refresh() { monitor.refresh(manual: true) }
    @objc private func selectProvider(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { monitor.select(providerID: id) }
    }
    @objc private func showProviders() {
        if providersWindow == nil { providersWindow = ProvidersWindowController(monitor: monitor) }
        providersWindow?.showWindow(nil)
        providersWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { /* The checkbox is rebuilt from the actual service status. */ }
        }
        update()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
