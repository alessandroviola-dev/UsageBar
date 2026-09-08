import AppKit

@MainActor
final class ProvidersWindowController: NSWindowController {
    private let monitor: UsageMonitor
    private let stack = NSStackView()

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "UsageBar Providers"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        guard let content = window?.contentView else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        ])
        stack.addArrangedSubview(label("PROVIDERS", bold: true))
        rebuildRows()
    }

    override func showWindow(_ sender: Any?) { rebuildRows(); super.showWindow(sender) }

    private func rebuildRows() {
        while stack.arrangedSubviews.count > 1 {
            let view = stack.arrangedSubviews[1]
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for provider in monitor.providers {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            let name = label(provider.displayName, bold: false)
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(name)
            let detail = label(detailText(for: provider), bold: false)
            detail.textColor = .secondaryLabelColor
            detail.alignment = .right
            detail.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(detail)
            if provider.id == "codex" { row.addArrangedSubview(button("Use", action: #selector(useCodex))) }
            if provider is any APIKeyProvider {
                row.addArrangedSubview(button("Add Key", action: #selector(addKey(_:)), id: provider.id))
                if isConnected(provider.id) { row.addArrangedSubview(button("Disconnect", action: #selector(disconnect(_:)), id: provider.id)) }
            }
            stack.addArrangedSubview(row)
        }
        stack.addArrangedSubview(button("Rescan Providers", action: #selector(rescan)))
    }

    private func detailText(for provider: any UsageProvider) -> String {
        if isConnected(provider.id) { return UserDefaults.standard.string(forKey: "accountLabel.\(provider.id).default") ?? "Connected" }
        if provider is any APIKeyProvider { return LocalProviderDiscovery().state(for: provider.id).description }
        return LocalProviderDiscovery().state(for: provider.id).description
    }

    private func isConnected(_ providerID: String) -> Bool {
        guard providerID == "openrouter" else { return false }
        return (try? KeychainStore.load(account: "openrouter.default")) != nil
    }

    private func button(_ title: String, action: Selector, id: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.tag = id == "openrouter" ? 1 : 0
        return button
    }

    private func label(_ text: String, bold: Bool) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        return field
    }

    @objc private func useCodex() { monitor.select(providerID: "codex"); rebuildRows() }
    @objc private func rescan() { rebuildRows() }

    @objc private func addKey(_ sender: NSButton) {
        let id = sender.tag == 1 ? "openrouter" : ""
        guard let provider = monitor.provider(id: id) as? any APIKeyProvider else { return }
        let name = NSTextField(string: "Personal")
        let key = NSSecureTextField(string: "")
        let accessory = NSStackView(views: [label("Account Name", bold: false), name, label("API Key", bold: false), key])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 6
        let alert = NSAlert()
        alert.messageText = "Add \(provider.displayName) Key"
        alert.informativeText = "The key is validated using a non-billable endpoint and stored only in your Keychain."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let accountName = name.stringValue
        let apiKey = key.stringValue
        key.stringValue = ""
        Task { [weak self] in
            do {
                try await provider.connect(accountName: accountName, apiKey: apiKey)
                self?.monitor.select(providerID: id)
                self?.rebuildRows()
            } catch { self?.showError(error.localizedDescription) }
        }
    }

    @objc private func disconnect(_ sender: NSButton) {
        let id = sender.tag == 1 ? "openrouter" : ""
        guard let provider = monitor.provider(id: id) else { return }
        Task { [weak self] in
            do {
                try await provider.disconnect()
                if self?.monitor.activeProviderID == id { self?.monitor.select(providerID: "codex") }
                self?.rebuildRows()
            } catch { self?.showError(error.localizedDescription) }
        }
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Could not connect"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
