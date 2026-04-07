import UIKit
import SwiftTerm

extension Notification.Name {
    static let terminalAccessoryAltModifierChanged = Notification.Name("terminalAccessoryAltModifierChanged")
    static let terminalAccessoryShiftModifierChanged = Notification.Name("terminalAccessoryShiftModifierChanged")
}

final class ScrollbackTerminalView: SwiftTerm.TerminalView {
    private enum Zoom {
        static let minimumPointSize: CGFloat = 8
        static let maximumPointSize: CGFloat = 22
        static let step: CGFloat = 0.5
    }

    private final class HiddenKeyboardInputView: UIInputView {
        override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
            super.init(frame: frame, inputViewStyle: inputViewStyle)
            allowsSelfSizing = true
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
            isOpaque = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            .zero
        }

        override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
            CGSize(width: targetSize.width, height: 0)
        }

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            CGSize(width: size.width, height: 0)
        }
    }

    private var isReviewingScrollback = false
    private var lastKnownBoundsHeight: CGFloat?
    private var lastKnownAdjustedInsets: UIEdgeInsets?
    private var isAwaitingKeyboardFocus = false
    private var pinchStartFontPointSize: CGFloat?
    private lazy var terminalPinchGestureRecognizer: UIPinchGestureRecognizer = {
        let gestureRecognizer = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinchStateChange(_:))
        )
        gestureRecognizer.cancelsTouchesInView = false
        return gestureRecognizer
    }()
    private lazy var hiddenKeyboardInputView = HiddenKeyboardInputView(frame: .zero, inputViewStyle: .keyboard)

    var accessoryAltModifier = false {
        didSet {
            guard oldValue != accessoryAltModifier else { return }
            NotificationCenter.default.post(name: .terminalAccessoryAltModifierChanged, object: self)
        }
    }

    var accessoryShiftModifier = false {
        didSet {
            guard oldValue != accessoryShiftModifier else { return }
            NotificationCenter.default.post(name: .terminalAccessoryShiftModifierChanged, object: self)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureScrollbackBehavior()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScrollbackBehavior()
    }

    override func scrolled(source terminal: Terminal, yDisp: Int) {
        let previousOffset = contentOffset
        let previousContentSize = contentSize
        let previousBoundsHeight = bounds.height
        let previousInsets = adjustedContentInset

        super.scrolled(source: terminal, yDisp: yDisp)
        restoreViewportIfNeeded(
            previousOffset: previousOffset,
            previousContentSize: previousContentSize,
            previousBoundsHeight: previousBoundsHeight,
            previousInsets: previousInsets,
            keepDistanceFromBottom: isReviewingScrollback
        )
    }

    override func sizeChanged(source: Terminal) {
        let previousOffset = contentOffset
        let previousContentSize = contentSize
        let previousBoundsHeight = bounds.height
        let previousInsets = adjustedContentInset

        super.sizeChanged(source: source)
        restoreViewportIfNeeded(
            previousOffset: previousOffset,
            previousContentSize: previousContentSize,
            previousBoundsHeight: previousBoundsHeight,
            previousInsets: previousInsets,
            keepDistanceFromBottom: isReviewingScrollback
        )
    }

    override func layoutSubviews() {
        let previousOffset = contentOffset
        let previousContentSize = contentSize
        let previousBoundsHeight = lastKnownBoundsHeight ?? bounds.height
        let previousInsets = lastKnownAdjustedInsets ?? adjustedContentInset
        let wasReviewingScrollback = isReviewingScrollback

        super.layoutSubviews()

        if updateKeyboardInsetsIfNeeded() {
            restoreViewportIfNeeded(
                previousOffset: previousOffset,
                previousContentSize: previousContentSize,
                previousBoundsHeight: previousBoundsHeight,
                previousInsets: previousInsets,
                keepDistanceFromBottom: wasReviewingScrollback
            )
        }

        lastKnownBoundsHeight = bounds.height
        lastKnownAdjustedInsets = adjustedContentInset
        fulfillPendingKeyboardFocusIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        fulfillPendingKeyboardFocusIfNeeded()
    }

    private func configureScrollbackBehavior() {
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true
        panGestureRecognizer.addTarget(self, action: #selector(handlePanStateChange(_:)))
        pinchGestureRecognizer?.isEnabled = false
        addGestureRecognizer(terminalPinchGestureRecognizer)
    }

    func toggleSoftwareKeyboard() {
        let shouldHideSoftwareKeyboard = inputView !== hiddenKeyboardInputView
        inputView = shouldHideSoftwareKeyboard ? hiddenKeyboardInputView : nil

        guard isFirstResponder else {
            _ = becomeFirstResponder()
            return
        }

        reloadInputViews()
        setNeedsLayout()
        layoutIfNeeded()
    }

    func requestKeyboardFocus() {
        isAwaitingKeyboardFocus = true
        fulfillPendingKeyboardFocusIfNeeded()
    }

    @objc
    private func handlePanStateChange(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed, .ended, .cancelled:
            updateScrollbackReviewState()
        default:
            break
        }
    }

    @objc
    private func handlePinchStateChange(_ gestureRecognizer: UIPinchGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            pinchStartFontPointSize = font.pointSize
        case .changed:
            guard let pinchStartFontPointSize else { return }
            let scaledPointSize = pinchStartFontPointSize * gestureRecognizer.scale
            applyZoom(pointSize: scaledPointSize)
        case .ended, .cancelled, .failed:
            pinchStartFontPointSize = nil
        default:
            break
        }
    }

    private func applyZoom(pointSize: CGFloat) {
        let clampedPointSize = min(max(pointSize, Zoom.minimumPointSize), Zoom.maximumPointSize)
        let snappedPointSize = (clampedPointSize / Zoom.step).rounded() * Zoom.step
        guard abs(snappedPointSize - font.pointSize) >= 0.01 else { return }
        font = font.withSize(snappedPointSize)
    }

    private func updateScrollbackReviewState() {
        let maxOffsetY = maxScrollableOffsetY(
            contentSize: contentSize,
            boundsHeight: bounds.height,
            insets: adjustedContentInset
        )
        let distanceFromBottom = max(0, maxOffsetY - contentOffset.y)
        isReviewingScrollback = distanceFromBottom > bottomFollowThreshold
    }

    private func restoreViewportIfNeeded(
        previousOffset: CGPoint,
        previousContentSize: CGSize,
        previousBoundsHeight: CGFloat,
        previousInsets: UIEdgeInsets,
        keepDistanceFromBottom: Bool
    ) {
        let previousMaxOffsetY = maxScrollableOffsetY(
            contentSize: previousContentSize,
            boundsHeight: previousBoundsHeight,
            insets: previousInsets
        )
        let newMaxOffsetY = maxScrollableOffsetY(
            contentSize: contentSize,
            boundsHeight: bounds.height,
            insets: adjustedContentInset
        )
        let distanceFromBottom = max(0, previousMaxOffsetY - previousOffset.y)

        let targetOffsetY: CGFloat
        if keepDistanceFromBottom {
            targetOffsetY = clampOffsetY(newMaxOffsetY - distanceFromBottom, maxOffsetY: newMaxOffsetY)
        } else if distanceFromBottom <= bottomFollowThreshold {
            targetOffsetY = newMaxOffsetY
        } else {
            return
        }

        if abs(contentOffset.y - targetOffsetY) > 0.5 {
            setContentOffset(CGPoint(x: contentOffset.x, y: targetOffsetY), animated: false)
        }
    }

    private func updateKeyboardInsetsIfNeeded() -> Bool {
        let overlap = keyboardOverlapHeight()
        guard abs(contentInset.bottom - overlap) > 0.5
                || abs(verticalScrollIndicatorInsets.bottom - overlap) > 0.5 else {
            return false
        }

        contentInset.bottom = overlap
        verticalScrollIndicatorInsets.bottom = overlap
        return true
    }

    private func keyboardOverlapHeight() -> CGFloat {
        guard window != nil else { return 0 }
        let keyboardFrame = keyboardLayoutGuide.layoutFrame
        guard !keyboardFrame.isEmpty else { return 0 }
        return max(0, bounds.maxY - keyboardFrame.minY)
    }

    private func maxScrollableOffsetY(contentSize: CGSize, boundsHeight: CGFloat, insets: UIEdgeInsets) -> CGFloat {
        max(-insets.top, contentSize.height - boundsHeight + insets.bottom)
    }

    private func clampOffsetY(_ value: CGFloat, maxOffsetY: CGFloat) -> CGFloat {
        max(-adjustedContentInset.top, min(value, maxOffsetY))
    }

    private var bottomFollowThreshold: CGFloat {
        max(28, bounds.height * 0.04)
    }

    private func fulfillPendingKeyboardFocusIfNeeded() {
        guard isAwaitingKeyboardFocus, window != nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAwaitingKeyboardFocus, self.window != nil else { return }
            self.isAwaitingKeyboardFocus = !self.becomeFirstResponder()
        }
    }
}
