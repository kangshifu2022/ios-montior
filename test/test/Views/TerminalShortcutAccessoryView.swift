import UIKit

final class TerminalShortcutAccessoryView: UIInputView {
    private static let preferredHeight: CGFloat = 58

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

    init(rows: [[ShortcutItem]]) {
        self.rows = rows
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.preferredHeight), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Self.preferredHeight)
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        CGSize(width: targetSize.width, height: Self.preferredHeight)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        invalidateIntrinsicContentSize()
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 2
        contentStack.alignment = .leading
        contentStack.layoutMargins = UIEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)

        for rowItems in rows where !rowItems.isEmpty {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 2
            rowStack.alignment = .center

            for item in rowItems {
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.plain()
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
                configuration.baseForegroundColor = .label
                if let title = item.title {
                    configuration.title = title
                } else if let systemImageName = item.systemImageName {
                    configuration.image = UIImage(systemName: systemImageName)
                    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                }
                button.configuration = configuration
                button.accessibilityLabel = item.accessibilityLabel
                button.titleLabel?.font = .systemFont(ofSize: 9, weight: .medium)
                button.setTitleColor(.label, for: .normal)
                button.backgroundColor = .tertiarySystemFill
                button.layer.cornerRadius = 7
                button.addAction(UIAction { _ in
                    item.action()
                }, for: .touchUpInside)
                rowStack.addArrangedSubview(button)
            }

            contentStack.addArrangedSubview(rowStack)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }
}
