import UIKit
import SwiftTerm

final class TerminalShortcutAccessoryView: UIInputView {
    enum Modifier: Hashable {
        case alt
        case control
        case shift

        var title: String {
            switch self {
            case .alt:
                return "Alt"
            case .control:
                return "Ctrl"
            case .shift:
                return "Shift"
            }
        }
    }

    private static let preferredHeight: CGFloat = 134

    struct ShortcutItem {
        enum Role {
            case action((Set<Modifier>) -> Void)
            case modifier(Modifier)
        }

        let title: String?
        let systemImageName: String?
        let accessibilityLabel: String
        let role: Role

        init(title: String, action: @escaping (Set<Modifier>) -> Void) {
            self.title = title
            self.systemImageName = nil
            self.accessibilityLabel = title
            self.role = .action(action)
        }

        init(systemImageName: String, accessibilityLabel: String, action: @escaping (Set<Modifier>) -> Void) {
            self.title = nil
            self.systemImageName = systemImageName
            self.accessibilityLabel = accessibilityLabel
            self.role = .action(action)
        }

        init(modifier: Modifier) {
            self.title = modifier.title
            self.systemImageName = nil
            self.accessibilityLabel = modifier.title
            self.role = .modifier(modifier)
        }
    }

    private let rows: [[ShortcutItem]]
    private weak var terminalView: SwiftTerm.TerminalView?
    private var modifierButtons: [Modifier: UIButton] = [:]
    private var activeModifiers: Set<Modifier> = []
    private var notificationObservers: [NSObjectProtocol] = []

    init(terminalView: SwiftTerm.TerminalView, rows: [[ShortcutItem]]) {
        self.terminalView = terminalView
        self.rows = rows
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.preferredHeight), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        registerModifierObservers()
        setupUI()
    }

    deinit {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
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

    private func registerModifierObservers() {
        guard let terminalView else { return }

        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: .terminalViewControlModifierReset,
                object: terminalView,
                queue: .main
            ) { [weak self] _ in
                self?.activeModifiers.remove(.control)
                self?.updateModifierButtonStates()
            },
            notificationCenter.addObserver(
                forName: .terminalViewMetaModifierReset,
                object: terminalView,
                queue: .main
            ) { [weak self] _ in
                self?.activeModifiers.remove(.alt)
                self?.updateModifierButtonStates()
            }
        ]
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.alignment = .leading
        contentStack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)

        for rowItems in rows where !rowItems.isEmpty {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 22
            rowStack.alignment = .center

            for item in rowItems {
                let button = makeButton(for: item)
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

    private func makeButton(for item: ShortcutItem) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        configuration.baseForegroundColor = UIColor(white: 0.97, alpha: 0.96)

        if let title = item.title {
            configuration.title = title
        } else if let systemImageName = item.systemImageName {
            configuration.image = UIImage(systemName: systemImageName)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        }

        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .regular)
        button.layer.cornerRadius = 8
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.clear.cgColor
        button.backgroundColor = .clear
        button.accessibilityLabel = item.accessibilityLabel
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: item.title == nil ? 28 : 36).isActive = true

        switch item.role {
        case .modifier(let modifier):
            modifierButtons[modifier] = button
            button.addAction(UIAction { [weak self] _ in
                self?.toggleModifier(modifier)
            }, for: .touchUpInside)
            updateModifierStyle(for: button, isActive: activeModifiers.contains(modifier))

        case .action(let action):
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                action(self.activeModifiers)
                self.clearModifiers()
            }, for: .touchUpInside)
        }

        return button
    }

    private func toggleModifier(_ modifier: Modifier) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }

        switch modifier {
        case .control:
            terminalView?.controlModifier = activeModifiers.contains(.control)
        case .alt:
            terminalView?.metaModifier = activeModifiers.contains(.alt)
        case .shift:
            break
        }

        updateModifierButtonStates()
    }

    private func clearModifiers() {
        activeModifiers.removeAll()
        terminalView?.controlModifier = false
        terminalView?.metaModifier = false
        updateModifierButtonStates()
    }

    private func updateModifierButtonStates() {
        for (modifier, button) in modifierButtons {
            updateModifierStyle(for: button, isActive: activeModifiers.contains(modifier))
        }
    }

    private func updateModifierStyle(for button: UIButton, isActive: Bool) {
        button.backgroundColor = isActive ? UIColor(white: 0.23, alpha: 1) : .clear
        button.layer.borderColor = isActive
            ? UIColor(white: 0.38, alpha: 1).cgColor
            : UIColor.clear.cgColor
    }
}
