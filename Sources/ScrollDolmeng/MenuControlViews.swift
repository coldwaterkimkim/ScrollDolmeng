import AppKit

final class MenuSectionHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    init(title: String, subtitle: String, width: CGFloat = 320) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 56))

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        setText(title: title, subtitle: subtitle)
    }

    func setText(title: String, subtitle: String) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class MenuSliderView: NSView {
    let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")

    init(
        title: String,
        description: String,
        minValue: Double,
        maxValue: Double,
        width: CGFloat = 320
    ) {
        slider = NSSlider(value: minValue, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 92))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.textColor = .secondaryLabelColor

        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2

        slider.isContinuous = true

        let headerRow = NSStackView(views: [titleLabel, valueLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fillProportionally
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        slider.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(headerRow)
        addSubview(slider)
        addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            headerRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            slider.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4),

            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            descriptionLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            descriptionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        setValue(minValue, display: String(format: "%.2f", minValue), description: description)
    }

    func setValue(_ value: Double, display: String) {
        slider.doubleValue = value
        valueLabel.stringValue = display
    }

    func setValue(_ value: Double, display: String, description: String) {
        setValue(value, display: display)
        descriptionLabel.stringValue = description
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
