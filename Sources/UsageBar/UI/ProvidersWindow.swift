import AppKit

@MainActor
final class ProvidersWindowController: NSWindowController {
    private let monitor: UsageMonitor
    private let stack = NSStackView()

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
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
        let title = label("CONNECTED", bold: true)
        stack.addArrangedSubview(title)
        rebuildRows()
    }

    override func showWindow(_ sender: Any?) {
        rebuildRows()
        super.showWindow(sender)
    }

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
            row.distribution = .fill
            row.spacing = 10
            let name = label(provider.displayName, bold: false)
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(name)
            let detail = label(provider.id == monitor.activeProviderID ? "Selected" : statusText(for: provider.id), bold: false)
            detail.textColor = .secondaryLabelColor
            detail.alignment = .right
            detail.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(detail)
            if provider.id == "codex" {
                let button = NSButton(title: "Use", target: self, action: #selector(useCodex))
                button.bezelStyle = .rounded
                row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }
    }

    private func statusText(for id: String) -> String { id == "codex" ? "Local CLI" : "Not available" }
    private func label(_ text: String, bold: Bool) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        return field
    }
    @objc private func useCodex() { monitor.select(providerID: "codex"); rebuildRows() }
}
