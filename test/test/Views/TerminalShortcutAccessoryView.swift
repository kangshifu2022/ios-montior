import UIKit

final class TerminalShortcutAccessoryView: UIInputView {
    enum ShortcutStyle {
        case normal
        case accent
    }

    private final class ShortcutButton: UIButton {
        private static let defaultBackgroundColor = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1.0)
        private static let accentBackgroundColor = UIColor(red: 0.03, green: 0.50, blue: 0.20, alpha: 1.0)
        private static let selectedBackgroundColor = UIColor(red: 0.03, green: 0.50, blue: 0.20, alpha: 1.0)
        private static let pressedBackgroundColor = UIColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1.0)
        private static let accentPressedBackgroundColor = UIColor(red: 0.02, green: 0.42, blue: 0.17, alpha: 1.0)
        private static let selectedPressedBackgroundColor = UIColor(red: 0.02, green: 0.42, blue: 0.17, alpha: 1.0)
        private static let activatedBackgroundColor = UIColor(red: 0.08, green: 0.58, blue: 0.25, alpha: 1.0)
        private static let defaultBorderColor = UIColor.white.withAlphaComponent(0.08)
        private static let selectedBorderColor = UIColor.white.withAlphaComponent(0.18)
        private static let activatedBorderColor = UIColor.white.withAlphaComponent(0.22)
        private static let defaultForegroundColor = UIColor.white.withAlphaComponent(0.92)
        private static let selectedForegroundColor = UIColor.white

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
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.backgroundColor = Self.activatedBackgroundColor
                    self.layer.borderColor = Self.activatedBorderColor.resolvedColor(with: self.traitCollection).cgColor
                },
                completion: { _ in
                    self.updateAppearance(animated: true)
                }
            )
        }

        private func updateAppearance(animated: Bool) {
            let updates = {
                let backgroundColor: UIColor
                if self.isHighlighted {
                    if self.isSelected {
                        backgroundColor = Self.selectedPressedBackgroundColor
                    } else {
                        backgroundColor = self.shortcutStyle == .accent ? Self.accentPressedBackgroundColor : Self.pressedBackgroundColor
                    }
                } else {
                    if self.isSelected {
                        backgroundColor = Self.selectedBackgroundColor
                    } else {
                        backgroundColor = self.shortcutStyle == .accent ? Self.accentBackgroundColor : Self.defaultBackgroundColor
                    }
                }

                let borderColor = (self.isHighlighted || self.isSelected || self.shortcutStyle == .accent)
                    ? Self.selectedBorderColor
                    : Self.defaultBorderColor
                self.backgroundColor = backgroundColor
                self.layer.borderColor = borderColor.resolvedColor(with: self.traitCollection).cgColor
                var configuration = self.configuration
                configuration?.baseForegroundColor = (self.isSelected || self.shortcutStyle == .accent)
                    ? Self.selectedForegroundColor
                    : Self.defaultForegroundColor
                self.configuration = configuration
                self.setTitleColor(
                    (self.isSelected || self.shortcutStyle == .accent)
                        ? Self.selectedForegroundColor
                        : Self.defaultForegroundColor,
                    for: .normal
                )
                self.tintColor = (self.isSelected || self.shortcutStyle == .accent)
                    ? Self.selectedForegroundColor
                    : Self.defaultForegroundColor
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
        let preferredWidth: CGFloat?
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
            preferredWidth: CGFloat? = nil,
            isSelected: (() -> Bool)? = nil,
            observedNotifications: [ObservedNotification] = [],
            action: @escaping () -> Void
        ) {
            self.style = style
            self.preferredWidth = preferredWidth
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
            preferredWidth: CGFloat? = nil,
            isSelected: (() -> Bool)? = nil,
            observedNotifications: [ObservedNotification] = [],
            action: @escaping () -> Void
        ) {
            self.style = style
            self.preferredWidth = preferredWidth
            self.title = nil
            self.systemImageName = systemImageName
            self.accessibilityLabel = accessibilityLabel
            self.isSelected = isSelected
            self.observedNotifications = observedNotifications
            self.action = action
        }
    }

    private let rows: [[ShortcutItem]]
    private let preferredHeight: CGFloat
    private var observationTokens: [NSObjectProtocol] = []

    init(rows: [[ShortcutItem]]) {
        let normalizedRows = rows.filter { !$0.isEmpty }
        self.rows = normalizedRows
        self.preferredHeight = Self.preferredHeight(forRowCount: normalizedRows.count)
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: preferredHeight), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupUI()
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

    private func setupUI() {
        backgroundColor = .clear

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
            rowStack.distribution = .fillProportionally

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
                button.widthAnchor.constraint(equalToConstant: Self.preferredButtonWidth(for: item)).isActive = true
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

    private static func preferredButtonWidth(for item: ShortcutItem) -> CGFloat {
        if let preferredWidth = item.preferredWidth {
            return preferredWidth
        }

        if item.systemImageName != nil {
            return 34
        }

        let titleLength = (item.title ?? "").count
        switch titleLength {
        case 0...1:
            return 34
        case 2...3:
            return 40
        case 4...5:
            return 48
        default:
            return 56
        }
    }
}
