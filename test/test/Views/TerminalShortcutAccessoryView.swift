import UIKit

final class TerminalShortcutAccessoryView: UIInputView {
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
                let button = UIButton(type: .system)
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
                button.backgroundColor = .tertiarySystemFill
                button.layer.cornerRadius = 8
                button.clipsToBounds = true
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
                button.addAction(UIAction { _ in
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
