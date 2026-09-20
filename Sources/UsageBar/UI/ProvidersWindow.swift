import AppKit

@MainActor
final class ProvidersWindowController: NSWindowController {
    private let monitor: UsageMonitor
    private let stack = NSStackView()

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "UsageBar Providers"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        rebuildRows()
        super.showWindow(sender)
        rescan()
    }

    private func build() {
        guard let content = window?.contentView else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20)
        ])
        rebuildRows()
    }

    private func rebuildRows() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        stack.addArrangedSubview(label("PROVIDERS", bold: true))
        for provider in monitor.providers {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            let name = label(provider.displayName, bold: false)
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let detail = label(monitor.connectionStatus(for: provider.id).label, bold: false)
            detail.textColor = .secondaryLabelColor
            detail.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(name)
            row.addArrangedSubview(detail)
            stack.addArrangedSubview(row)
        }
        stack.addArrangedSubview(button("Rescan Providers", action: #selector(rescan)))
    }

    @objc private func rescan() {
        Task { [weak self] in
            guard let self else { return }
            await monitor.refreshConnectionStatusesAndWait()
            rebuildRows()
        }
    }

    private func label(_ text: String, bold: Bool) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}
