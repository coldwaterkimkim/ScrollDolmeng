import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    var onEnabledChanged: ((Bool) -> Void)?
    var onSpeedPresetChanged: ((Double) -> Void)?
    var onSpeedValueChanged: ((Double) -> Void)?
    var onFlipHorizontalChanged: ((Bool) -> Void)?
    var onFlipVerticalChanged: ((Bool) -> Void)?
    var onShowMenuBarIconChanged: ((Bool) -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onReconnectInputHook: (() -> Void)?
    var onDidClose: (() -> Void)?

    private var isApplyingState = false

    // Status
    private let statusDot = StatusDotView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusDetailLabel = NSTextField(labelWithString: "")
    private let enableSwitch = NSSwitch()

    // Scroll Feel
    private let speedSegmented = NSSegmentedControl(
        labels: ["Slow", "Normal", "Fast"],
        trackingMode: .selectOne, target: nil, action: nil
    )
    private let speedSlider = NSSlider(
        value: 1.0, minValue: 0.60, maxValue: 1.50, target: nil, action: nil
    )
    private let speedValueLabel = NSTextField(labelWithString: "")

    // Direction
    private let flipHorizontalSwitch = NSSwitch()
    private let flipVerticalSwitch = NSSwitch()

    // General
    private let menuBarIconSwitch = NSSwitch()

    // Permissions
    private let accessibilityButton = NSButton(title: "Accessibility\u{2026}", target: nil, action: nil)
    private let inputMonitoringButton = NSButton(title: "Input Monitoring\u{2026}", target: nil, action: nil)
    private let reconnectButton = NSButton(title: "Reconnect Hook", target: nil, action: nil)
    private var permissionsViews: [NSView] = []

    private var mainStack: NSStackView!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "울트라돌멩의원핑거스크롤"
        window.isReleasedWhenClosed = true
        window.contentMinSize = NSSize(width: 460, height: 430)
        super.init(window: window)
        window.delegate = self
        buildUI()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func apply(settings: ScrollSettings, hasTap: Bool, hasTrackpadDevices: Bool) {
        isApplyingState = true
        defer { isApplyingState = false }

        let color: NSColor
        if !hasTap || !hasTrackpadDevices {
            color = .systemOrange
        } else {
            color = settings.isEnabled ? .systemGreen : .tertiaryLabelColor
        }
        statusDot.color = color

        statusLabel.stringValue = SettingsPresentation.statusTitle(
            hasTap: hasTap,
            hasTrackpadDevices: hasTrackpadDevices,
            isEnabled: settings.isEnabled
        )

        if !hasTap {
            statusDetailLabel.stringValue = "Grant Accessibility and Input Monitoring permissions"
        } else if !hasTrackpadDevices {
            statusDetailLabel.stringValue = "No trackpad detected"
        } else if !settings.isEnabled {
            statusDetailLabel.stringValue = "One-finger scrolling is paused"
        } else {
            statusDetailLabel.stringValue = "Hold \(TrackpadScrollController.fixedModifierKey.title) to scroll"
        }

        enableSwitch.state = settings.isEnabled ? .on : .off

        applySpeedControls(value: settings.scrollMultiplier)

        flipHorizontalSwitch.state = settings.flipHorizontal ? .on : .off
        flipVerticalSwitch.state = settings.flipVertical ? .on : .off

        menuBarIconSwitch.state = settings.showMenuBarIcon ? .on : .off

        let needsPermissions = !hasTap || !hasTrackpadDevices
        permissionsViews.forEach { $0.isHidden = !needsPermissions }
    }

    func windowWillClose(_ notification: Notification) {
        onDidClose?()
    }

    private func speedDisplayText(for value: Double) -> String {
        let name = SettingsPresentation.selectedSpeedPresetName(for: value)
        return name == "Custom" ? String(format: "%.2f", value) : name
    }

    private func applySpeedControls(value: Double) {
        speedSlider.doubleValue = value
        speedValueLabel.stringValue = speedDisplayText(for: value)
        speedSegmented.selectedSegment = speedSegment(for: value)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        contentView.addSubview(scroll)

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        mainStack = stack

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
        ])

        speedSlider.numberOfTickMarks = 3
        speedSlider.allowsTickMarkValuesOnly = false

        speedSlider.isContinuous = true
        speedSegmented.segmentStyle = .rounded

        speedValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        speedValueLabel.textColor = .secondaryLabelColor
        speedValueLabel.alignment = .right

        [accessibilityButton, inputMonitoringButton, reconnectButton].forEach {
            $0.bezelStyle = .rounded
            $0.controlSize = .regular
        }

        addFull(makeStatusRow())
        addSpacing(20)

        addFull(makeSeparator())
        addSpacing(14)
        addFull(makeSectionLabel("Scroll Feel"))
        addSpacing(10)
        addFull(makeSliderGroup("Speed", value: speedValueLabel, seg: speedSegmented, slider: speedSlider))
        addSpacing(20)

        addFull(makeSeparator())
        addSpacing(14)
        addFull(makeSectionLabel("Direction"))
        addSpacing(10)
        addFull(makeRow("Flip Horizontal", accessory: flipHorizontalSwitch))
        addSpacing(10)
        addFull(makeRow("Flip Vertical", accessory: flipVerticalSwitch))
        addSpacing(20)

        addFull(makeSeparator())
        addSpacing(14)
        addFull(makeSectionLabel("General"))
        addSpacing(10)
        addFull(makeRow("Show Menu Bar Icon", accessory: menuBarIconSwitch))
        addSpacing(20)

        let permissionsSeparator = makeSeparator()
        addFull(permissionsSeparator)
        addSpacing(14)
        let permissionsLabel = makeSectionLabel("Permissions")
        addFull(permissionsLabel)
        addSpacing(10)
        let permissionsButtons = makeButtonRow()
        addFull(permissionsButtons)

        permissionsViews = [permissionsSeparator, permissionsLabel, permissionsButtons]
    }

    private func addFull(_ view: NSView) {
        mainStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    private func addSpacing(_ points: CGFloat) {
        guard let last = mainStack.arrangedSubviews.last else { return }
        mainStack.setCustomSpacing(points, after: last)
    }

    private func makeStatusRow() -> NSView {
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusDetailLabel.font = .systemFont(ofSize: 11)
        statusDetailLabel.textColor = .secondaryLabelColor

        let dotTitle = NSStackView(views: [statusDot, statusLabel])
        dotTitle.orientation = .horizontal
        dotTitle.alignment = .centerY
        dotTitle.spacing = 6

        let left = NSStackView(views: [dotTitle, statusDetailLabel])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2

        enableSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [left, NSView(), enableSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeSectionLabel(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeRow(_ title: String, accessory: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        accessory.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, NSView(), accessory])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeSliderGroup(
        _ title: String,
        value: NSTextField,
        seg: NSSegmentedControl,
        slider: NSSlider
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)

        let titleRow = NSStackView(views: [titleLabel, NSView(), value])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8

        let group = NSStackView(views: [titleRow, seg, slider])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 6

        titleRow.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleRow.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            titleRow.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            slider.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: group.trailingAnchor),
        ])
        return group
    }

    private func makeButtonRow() -> NSView {
        let row = NSStackView(views: [accessibilityButton, inputMonitoringButton, reconnectButton])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func wireActions() {
        enableSwitch.target = self
        enableSwitch.action = #selector(enabledChanged(_:))

        speedSegmented.target = self
        speedSegmented.action = #selector(speedPresetChanged(_:))
        speedSlider.target = self
        speedSlider.action = #selector(speedValueChanged(_:))

        flipHorizontalSwitch.target = self
        flipHorizontalSwitch.action = #selector(flipHorizontalChanged(_:))
        flipVerticalSwitch.target = self
        flipVerticalSwitch.action = #selector(flipVerticalChanged(_:))

        menuBarIconSwitch.target = self
        menuBarIconSwitch.action = #selector(menuBarIconChanged(_:))

        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilityPressed)
        inputMonitoringButton.target = self
        inputMonitoringButton.action = #selector(openInputMonitoringPressed)
        reconnectButton.target = self
        reconnectButton.action = #selector(reconnectInputHookPressed)
    }

    private func speedSegment(for value: Double) -> Int {
        if abs(value - 0.82) < 0.01 { return 0 }
        if abs(value - 1.00) < 0.01 { return 1 }
        if abs(value - 1.18) < 0.01 { return 2 }
        return -1
    }

    @objc private func enabledChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onEnabledChanged?(sender.state == .on)
    }

    @objc private func speedPresetChanged(_ sender: NSSegmentedControl) {
        guard !isApplyingState else { return }
        switch sender.selectedSegment {
        case 0:
            applySpeedControls(value: 0.82)
            onSpeedPresetChanged?(0.82)
        case 1:
            applySpeedControls(value: 1.0)
            onSpeedPresetChanged?(1.0)
        case 2:
            applySpeedControls(value: 1.18)
            onSpeedPresetChanged?(1.18)
        default:
            break
        }
    }

    @objc private func speedValueChanged(_ sender: NSSlider) {
        guard !isApplyingState else { return }
        applySpeedControls(value: sender.doubleValue)
        onSpeedValueChanged?(sender.doubleValue)
    }

    @objc private func flipHorizontalChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onFlipHorizontalChanged?(sender.state == .on)
    }

    @objc private func flipVerticalChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onFlipVerticalChanged?(sender.state == .on)
    }

    @objc private func menuBarIconChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowMenuBarIconChanged?(sender.state == .on)
    }

    @objc private func openAccessibilityPressed() { onOpenAccessibility?() }
    @objc private func openInputMonitoringPressed() { onOpenInputMonitoring?() }
    @objc private func reconnectInputHookPressed() { onReconnectInputHook?() }
}

private final class StatusDotView: NSView {
    var color: NSColor = .tertiaryLabelColor {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 8),
            heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
