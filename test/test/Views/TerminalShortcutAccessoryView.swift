import UIKit

final class TerminalShortcutAccessoryView: UIInputView {
    private final class ShortcutButton: UIButton {
        private static let defaultBackgroundColor = UIColor.tertiarySystemFill
        private static let pressedBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.28)
        private static let activatedBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.20)
        private static let defaultBorderColor = UIColor.separator.withAlphaComponent(0.18)
        private static let activatedBorderColor = UIColor.systemBlue.withAlphaComponent(0.45)

        override var isHighlighted: Bool {
            didSet {
                updateAppearance(animated: true)
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            adjustsImageWhenHighlighted = false
            clipsToBounds = true
            layer.cornerRadius = 8
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            updateAppearance(animated: false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateAppearance(animated: false)
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
                self.backgroundColor = self.isHighlighted ? Self.pressedBackgroundColor : Self.defaultBackgroundColor
                let borderColor = self.isHighlighted ? Self.activatedBorderColor : Self.defaultBorderColor
                self.layer.borderColor = borderColor.resolvedColor(with: self.traitCollection).cgColor
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

    private static let rowHeight: CGFloat = 36
    private static let verticalSpacing: CGFloat = 4
    private static let horizontalSpacing: CGFloat = 4
    private static let contentInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

    struct ShortcutItem {
        let title: String?
        let systemImageName: String?
        let accessibilityLabel: String
        let action: () -> Void

        init(title: String, action: @escaping () -> Void) {
            self.title = title
            self.systemImageName = nil
            self.accessibilityLabel = title
            self.action = action
        }

        init(systemImageName: String, accessibilityLabel: String, action: @escaping () -> Void) {
            self.title = nil
            self.systemImageName = systemImageName
            self.accessibilityLabel = accessibilityLabel
            self.action = action
        }
    }

    private let rows: [[ShortcutItem]]
    private let preferredHeight: CGFloat

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
            rowStack.distribution = .fillEqually

            for item in rowItems {
                let button = ShortcutButton(frame: .zero)
                button.translatesAutoresizingMaskIntoConstraints = false
                var configuration = UIButton.Configuration.plain()
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
                configuration.baseForegroundColor = .label
                if let title = item.title {
                    configuration.title = title
                } else if let systemImageName = item.systemImageName {
                    configuration.image = UIImage(systemName: systemImageName)
                    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
                }
                button.configuration = configuration
                button.accessibilityLabel = item.accessibilityLabel
                button.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold)
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                button.titleLabel?.minimumScaleFactor = 0.7
                button.titleLabel?.lineBreakMode = .byClipping
                button.setTitleColor(.label, for: .normal)
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
                button.addAction(UIAction { [weak button] _ in
                    button?.flashActivation()
                    item.action()
                }, for: .touchUpInside)
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
}
