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
        let activatedForegroundColor: UIColor
    }

    private final class ShortcutButton: UIButton {
        private static let activationFeedbackHoldDuration: TimeInterval = 0.5
        private static let standardAnimationDuration: TimeInterval = 0.12
        private static let activationFadeOutDuration: TimeInterval = 0.32
        private static let activationScale = CGAffineTransform(scaleX: 1.04, y: 1.04)
        private static let highlightedScale = CGAffineTransform(scaleX: 1.06, y: 1.06)

        private var isActivationFeedbackVisible = false
        private var activationResetWorkItem: DispatchWorkItem?

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

        deinit {
            activationResetWorkItem?.cancel()
        }

        func flashActivation() {
            activationResetWorkItem?.cancel()
            isActivationFeedbackVisible = true
            updateAppearance(animated: true)

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isActivationFeedbackVisible = false
                self.updateAppearance(
                    animated: true,
                    duration: Self.activationFadeOutDuration,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
                )
            }
            activationResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.activationFeedbackHoldDuration,
                execute: workItem
            )
        }

        private func updateAppearance(
            animated: Bool,
            duration: TimeInterval,
            options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        ) {
            let updates = {
                let palette = TerminalShortcutAccessoryView.keyboardPalette(for: self.traitCollection)
                let showsActivationFeedback = self.isHighlighted || self.isActivationFeedbackVisible
                let backgroundColor: UIColor
                if showsActivationFeedback {
                    backgroundColor = palette.activatedBackground
                } else {
                    if self.isSelected {
                        backgroundColor = palette.selectedBackground
                    } else {
                        backgroundColor = self.shortcutStyle == .accent
                            ? palette.accentBackground
                            : palette.defaultBackground
                    }
                }

                let borderColor = (showsActivationFeedback || self.isSelected || self.shortcutStyle == .accent)
                    ? palette.emphasizedBorderColor
                    : palette.defaultBorderColor
                let foregroundColor: UIColor
                if showsActivationFeedback {
                    foregroundColor = palette.activatedForegroundColor
                } else if self.isSelected {
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
                if self.isHighlighted {
                    self.transform = Self.highlightedScale
                } else if self.isActivationFeedbackVisible {
                    self.transform = Self.activationScale
                } else {
                    self.transform = .identity
                }
            }

            guard animated else {
                updates()
                return
            }

            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: options,
                animations: updates
            )
        }

        private func updateAppearance(animated: Bool) {
            updateAppearance(
                animated: animated,
                duration: Self.standardAnimationDuration
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

    private let rows: [[ShortcutItem]]
    private let gridColumnCount: Int
    private let preferredHeight: CGFloat
    private let topBorderView = UIView()
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

    private func setupUI() {
        topBorderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorderView)

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = Self.verticalSpacing
        contentStack.alignment = .fill
        contentStack.distribution = .fill
        contentStack.layoutMargins = Self.contentInsets
        contentStack.isLayoutMarginsRelativeArrangement = true
        addSubview(contentStack)

        for rowItems in rows where !rowItems.isEmpty {
            contentStack.addArrangedSubview(makeRowView(for: rowItems))
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

    private func makeRowView(for rowItems: [ShortcutItem]) -> UIView {
        let rowView = UIView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true

        let columnGuides = makeColumnGuides(in: rowView)
        var currentColumn = 0

        for item in rowItems {
            guard currentColumn < columnGuides.count else { break }

            let button = makeButton(for: item)
            let span = min(max(item.columnSpan, 1), columnGuides.count - currentColumn)
            let trailingColumn = currentColumn + span - 1
            rowView.addSubview(button)

            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: columnGuides[currentColumn].leadingAnchor),
                button.trailingAnchor.constraint(equalTo: columnGuides[trailingColumn].trailingAnchor),
                button.topAnchor.constraint(equalTo: rowView.topAnchor),
                button.bottomAnchor.constraint(equalTo: rowView.bottomAnchor)
            ])

            currentColumn += span
        }

        return rowView
    }

    private func makeColumnGuides(in rowView: UIView) -> [UILayoutGuide] {
        let guides = (0..<gridColumnCount).map { _ in UILayoutGuide() }
        guard let firstGuide = guides.first else { return guides }

        for guide in guides {
            rowView.addLayoutGuide(guide)
            NSLayoutConstraint.activate([
                guide.topAnchor.constraint(equalTo: rowView.topAnchor),
                guide.bottomAnchor.constraint(equalTo: rowView.bottomAnchor)
            ])
        }

        firstGuide.leadingAnchor.constraint(equalTo: rowView.leadingAnchor).isActive = true

        for index in 1..<guides.count {
            NSLayoutConstraint.activate([
                guides[index].leadingAnchor.constraint(equalTo: guides[index - 1].trailingAnchor, constant: Self.horizontalSpacing),
                guides[index].widthAnchor.constraint(equalTo: firstGuide.widthAnchor)
            ])
        }

        if let lastGuide = guides.last {
            lastGuide.trailingAnchor.constraint(equalTo: rowView.trailingAnchor).isActive = true
        }
        return guides
    }

    private func makeButton(for item: ShortcutItem) -> ShortcutButton {
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

        return button
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
                activatedBackground: UIColor(red: 0.29, green: 0.54, blue: 0.96, alpha: 1.0),
                defaultBorderColor: UIColor.white.withAlphaComponent(0.06),
                emphasizedBorderColor: UIColor.white.withAlphaComponent(0.14),
                defaultForegroundColor: UIColor.white.withAlphaComponent(0.96),
                accentForegroundColor: UIColor.white.withAlphaComponent(0.96),
                selectedForegroundColor: UIColor.white,
                activatedForegroundColor: UIColor.white
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
                activatedBackground: UIColor(red: 0.24, green: 0.51, blue: 0.96, alpha: 1.0),
                defaultBorderColor: UIColor.black.withAlphaComponent(0.06),
                emphasizedBorderColor: UIColor.black.withAlphaComponent(0.12),
                defaultForegroundColor: UIColor.black.withAlphaComponent(0.92),
                accentForegroundColor: UIColor.black.withAlphaComponent(0.92),
                selectedForegroundColor: UIColor.white,
                activatedForegroundColor: UIColor.white
            )
        }
    }
}
