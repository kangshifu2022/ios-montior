import UIKit

final class TerminalShortcutAccessoryView: UIInputView {
    enum ShortcutStyle: Equatable {
        case normal
        case accent
    }

    private struct KeyboardPalette {
        let accessoryBackground: UIColor
        let accessoryTopBorder: UIColor
        let defaultBackground: UIColor
        let defaultPressedBackground: UIColor
        let accentBackground: UIColor
        let accentPressedBackground: UIColor
        let selectedBackground: UIColor
        let selectedPressedBackground: UIColor
        let activatedBackground: UIColor
        let defaultBorderColor: UIColor
        let emphasizedBorderColor: UIColor
        let defaultForegroundColor: UIColor
        let accentForegroundColor: UIColor
        let selectedForegroundColor: UIColor
    }

    private final class ShortcutButton: UIButton {
        var shortcutStyle: ShortcutStyle = .normal {
            didSet {
                updateAppearance(animated: false)
            }
        }

        override var isHighlighted: Bool {
            didSet {
                updateAppearance(animated: true)
            }
        }

        override var isSelected: Bool {
            didSet {
                updateAppearance(animated: true)
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.cornerRadius = 8
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
                (self: Self, _: UITraitCollection) in
                self.updateAppearance(animated: false)
            }
            updateAppearance(animated: false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func flashActivation() {
            let palette = TerminalShortcutAccessoryView.keyboardPalette(for: traitCollection)
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.backgroundColor = palette.activatedBackground
                    self.layer.borderColor = palette.emphasizedBorderColor.cgColor
                },
                completion: { _ in
                    self.updateAppearance(animated: true)
                }
            )
        }

        private func updateAppearance(animated: Bool) {
            let updates = {
                let palette = TerminalShortcutAccessoryView.keyboardPalette(for: self.traitCollection)
                let backgroundColor: UIColor
                if self.isHighlighted {
                    if self.isSelected {
                        backgroundColor = palette.selectedPressedBackground
                    } else {
                        backgroundColor = self.shortcutStyle == .accent
                            ? palette.accentPressedBackground
                            : palette.defaultPressedBackground
                    }
                } else {
                    if self.isSelected {
                        backgroundColor = palette.selectedBackground
                    } else {
                        backgroundColor = self.shortcutStyle == .accent
                            ? palette.accentBackground
                            : palette.defaultBackground
                    }
                }

                let borderColor = (self.isHighlighted || self.isSelected || self.shortcutStyle == .accent)
                    ? palette.emphasizedBorderColor
                    : palette.defaultBorderColor
                let foregroundColor: UIColor
                if self.isSelected {
                    foregroundColor = palette.selectedForegroundColor
                } else if self.shortcutStyle == .accent {
                    foregroundColor = palette.accentForegroundColor
                } else {
                    foregroundColor = palette.defaultForegroundColor
                }
                self.backgroundColor = backgroundColor
                self.layer.borderColor = borderColor.cgColor
                var configuration = self.configuration
                configuration?.baseForegroundColor = foregroundColor
                self.configuration = configuration
                self.setTitleColor(foregroundColor, for: .normal)
                self.tintColor = foregroundColor
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }

            guard animated else {
                updates()
                return
            }

            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: updates
            )
        }
    }

    private static let rowHeight: CGFloat = 38
    private static let verticalSpacing: CGFloat = 6
    private static let horizontalSpacing: CGFloat = 4
    private static let contentInsets = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
    private static let buttonFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private static let buttonSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)

    struct ObservedNotification {
        let name: Notification.Name
        let objectProvider: () -> AnyObject?

        init(name: Notification.Name, objectProvider: @escaping () -> AnyObject? = { nil }) {
            self.name = name
            self.objectProvider = objectProvider
        }
    }

    struct ShortcutItem {
        let style: ShortcutStyle
        let columnSpan: Int
        let title: String?
        let systemImageName: String?
        let accessibilityLabel: String
        let isSelected: (() -> Bool)?
        let observedNotifications: [ObservedNotification]
        let action: () -> Void

        init(
            title: String,
            accessibilityLabel: String? = nil,
            style: ShortcutStyle = .normal,
            columnSpan: Int = 1,
            isSelected: (() -> Bool)? = nil,
            observedNotifications: [ObservedNotification] = [],
            action: @escaping () -> Void
        ) {
            self.style = style
            self.columnSpan = max(columnSpan, 1)
            self.title = title
            self.systemImageName = nil
            self.accessibilityLabel = accessibilityLabel ?? title
            self.isSelected = isSelected
            self.observedNotifications = observedNotifications
            self.action = action
        }

        init(
            systemImageName: String,
            accessibilityLabel: String,
            style: ShortcutStyle = .normal,
            columnSpan: Int = 1,
            isSelected: (() -> Bool)? = nil,
            observedNotifications: [ObservedNotification] = [],
            action: @escaping () -> Void
        ) {
            self.style = style
            self.columnSpan = max(columnSpan, 1)
            self.title = nil
            self.systemImageName = systemImageName
            self.accessibilityLabel = accessibilityLabel
            self.isSelected = isSelected
            self.observedNotifications = observedNotifications
            self.action = action
        }
    }

    private struct ButtonWidthConstraint {
        let columnSpan: Int
        let constraint: NSLayoutConstraint
    }

    private let rows: [[ShortcutItem]]
    private let gridColumnCount: Int
    private let preferredHeight: CGFloat
    private let topBorderView = UIView()
    private var buttonWidthConstraints: [ButtonWidthConstraint] = []
    private var observationTokens: [NSObjectProtocol] = []

    init(rows: [[ShortcutItem]]) {
        let normalizedRows = rows.filter { !$0.isEmpty }
        self.rows = normalizedRows
        self.gridColumnCount = Self.gridColumnCount(for: normalizedRows)
        self.preferredHeight = Self.preferredHeight(forRowCount: normalizedRows.count)
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: preferredHeight), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (self: Self, _: UITraitCollection) in
            self.updateContainerAppearance()
        }
        setupUI()
        updateContainerAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for token in observationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: preferredHeight)
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        CGSize(width: targetSize.width, height: preferredHeight)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateButtonWidths()
    }

    private func setupUI() {
        topBorderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorderView)

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = Self.verticalSpacing
        contentStack.alignment = .fill
        contentStack.distribution = .fillEqually
        contentStack.layoutMargins = Self.contentInsets
        contentStack.isLayoutMarginsRelativeArrangement = true
        addSubview(contentStack)

        for rowItems in rows where !rowItems.isEmpty {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = Self.horizontalSpacing
            rowStack.alignment = .fill
            rowStack.distribution = .fill

            for item in rowItems {
                let button = ShortcutButton(frame: .zero)
                button.translatesAutoresizingMaskIntoConstraints = false
                var configuration = UIButton.Configuration.plain()
                configuration.buttonSize = .mini
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 2, bottom: 5, trailing: 2)
                configuration.baseForegroundColor = .label
                if let title = item.title {
                    configuration.title = title
                    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                        var outgoing = incoming
                        outgoing.font = Self.buttonFont
                        return outgoing
                    }
                } else if let systemImageName = item.systemImageName {
                    configuration.image = UIImage(systemName: systemImageName)
                    configuration.preferredSymbolConfigurationForImage = Self.buttonSymbolConfiguration
                }
                button.configuration = configuration
                button.shortcutStyle = item.style
                button.accessibilityLabel = item.accessibilityLabel
                button.titleLabel?.font = Self.buttonFont
                button.titleLabel?.adjustsFontForContentSizeCategory = false
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                button.titleLabel?.minimumScaleFactor = 0.6
                button.titleLabel?.lineBreakMode = .byClipping
                button.isSelected = item.isSelected?() ?? false
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
                let widthConstraint = button.widthAnchor.constraint(
                    equalToConstant: Self.fallbackButtonWidth(forColumnSpan: item.columnSpan)
                )
                widthConstraint.isActive = true
                buttonWidthConstraints.append(
                    ButtonWidthConstraint(columnSpan: item.columnSpan, constraint: widthConstraint)
                )
                button.addAction(UIAction { [weak button] _ in
                    button?.flashActivation()
                    item.action()
                    button?.isSelected = item.isSelected?() ?? false
                }, for: .touchUpInside)

                for observedNotification in item.observedNotifications {
                    let token = NotificationCenter.default.addObserver(
                        forName: observedNotification.name,
                        object: observedNotification.objectProvider(),
                        queue: .main
                    ) { [weak button] _ in
                        button?.isSelected = item.isSelected?() ?? false
                    }
                    observationTokens.append(token)
                }

                rowStack.addArrangedSubview(button)
            }

            contentStack.addArrangedSubview(rowStack)
        }

        NSLayoutConstraint.activate([
            topBorderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorderView.topAnchor.constraint(equalTo: topAnchor),
            topBorderView.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private static func preferredHeight(forRowCount rowCount: Int) -> CGFloat {
        let clampedRowCount = max(rowCount, 1)
        let totalVerticalInsets = contentInsets.top + contentInsets.bottom
        let totalRowSpacing = CGFloat(max(clampedRowCount - 1, 0)) * verticalSpacing
        return totalVerticalInsets + totalRowSpacing + (CGFloat(clampedRowCount) * rowHeight)
    }

    private func updateButtonWidths() {
        let availableWidth = bounds.width - Self.contentInsets.left - Self.contentInsets.right
        guard availableWidth > 0 else { return }

        let totalSpacing = CGFloat(max(gridColumnCount - 1, 0)) * Self.horizontalSpacing
        let singleColumnWidth = max((availableWidth - totalSpacing) / CGFloat(gridColumnCount), 0)

        for buttonWidthConstraint in buttonWidthConstraints {
            let span = max(buttonWidthConstraint.columnSpan, 1)
            buttonWidthConstraint.constraint.constant =
                (singleColumnWidth * CGFloat(span)) + (CGFloat(span - 1) * Self.horizontalSpacing)
        }
    }

    private func updateContainerAppearance() {
        let palette = Self.keyboardPalette(for: traitCollection)
        backgroundColor = palette.accessoryBackground
        topBorderView.backgroundColor = palette.accessoryTopBorder
    }

    private static func gridColumnCount(for rows: [[ShortcutItem]]) -> Int {
        max(
            rows.map { rowItems in
                rowItems.reduce(0) { partialResult, item in
                    partialResult + max(item.columnSpan, 1)
                }
            }.max() ?? 1,
            1
        )
    }

    private static func fallbackButtonWidth(forColumnSpan columnSpan: Int) -> CGFloat {
        let singleColumnWidth: CGFloat = 38
        return (singleColumnWidth * CGFloat(max(columnSpan, 1)))
            + (CGFloat(max(columnSpan - 1, 0)) * horizontalSpacing)
    }

    private static func keyboardPalette(for traitCollection: UITraitCollection) -> KeyboardPalette {
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return KeyboardPalette(
                accessoryBackground: UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0),
                accessoryTopBorder: UIColor.white.withAlphaComponent(0.10),
                defaultBackground: UIColor(red: 0.39, green: 0.40, blue: 0.43, alpha: 1.0),
                defaultPressedBackground: UIColor(red: 0.31, green: 0.32, blue: 0.35, alpha: 1.0),
                accentBackground: UIColor(red: 0.30, green: 0.31, blue: 0.34, alpha: 1.0),
                accentPressedBackground: UIColor(red: 0.24, green: 0.25, blue: 0.28, alpha: 1.0),
                selectedBackground: UIColor(red: 0.48, green: 0.49, blue: 0.53, alpha: 1.0),
                selectedPressedBackground: UIColor(red: 0.41, green: 0.42, blue: 0.46, alpha: 1.0),
                activatedBackground: UIColor(red: 0.44, green: 0.45, blue: 0.49, alpha: 1.0),
                defaultBorderColor: UIColor.white.withAlphaComponent(0.06),
                emphasizedBorderColor: UIColor.white.withAlphaComponent(0.14),
                defaultForegroundColor: UIColor.white.withAlphaComponent(0.96),
                accentForegroundColor: UIColor.white.withAlphaComponent(0.96),
                selectedForegroundColor: UIColor.white
            )
        default:
            return KeyboardPalette(
                accessoryBackground: UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1.0),
                accessoryTopBorder: UIColor.black.withAlphaComponent(0.08),
                defaultBackground: UIColor.white,
                defaultPressedBackground: UIColor(red: 0.75, green: 0.78, blue: 0.82, alpha: 1.0),
                accentBackground: UIColor(red: 0.68, green: 0.72, blue: 0.77, alpha: 1.0),
                accentPressedBackground: UIColor(red: 0.61, green: 0.65, blue: 0.70, alpha: 1.0),
                selectedBackground: UIColor(red: 0.54, green: 0.58, blue: 0.63, alpha: 1.0),
                selectedPressedBackground: UIColor(red: 0.48, green: 0.52, blue: 0.57, alpha: 1.0),
                activatedBackground: UIColor(red: 0.64, green: 0.68, blue: 0.73, alpha: 1.0),
                defaultBorderColor: UIColor.black.withAlphaComponent(0.06),
                emphasizedBorderColor: UIColor.black.withAlphaComponent(0.12),
                defaultForegroundColor: UIColor.black.withAlphaComponent(0.92),
                accentForegroundColor: UIColor.black.withAlphaComponent(0.92),
                selectedForegroundColor: UIColor.white
            )
        }
    }
}
