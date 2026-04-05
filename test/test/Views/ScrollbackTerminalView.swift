import UIKit
import SwiftTerm

final class ScrollbackTerminalView: SwiftTerm.TerminalView {
    private var isReviewingScrollback = false

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

        super.scrolled(source: terminal, yDisp: yDisp)
        restoreViewportIfNeeded(previousOffset: previousOffset, previousContentSize: previousContentSize)
    }

    override func sizeChanged(source: Terminal) {
        let previousOffset = contentOffset
        let previousContentSize = contentSize

        super.sizeChanged(source: source)
        restoreViewportIfNeeded(previousOffset: previousOffset, previousContentSize: previousContentSize)
    }

    private func configureScrollbackBehavior() {
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true
        panGestureRecognizer.addTarget(self, action: #selector(handlePanStateChange(_:)))
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

    private func updateScrollbackReviewState() {
        let maxOffsetY = max(0, contentSize.height - bounds.height)
        let distanceFromBottom = max(0, maxOffsetY - contentOffset.y)
        isReviewingScrollback = distanceFromBottom > bottomFollowThreshold
    }

    private func restoreViewportIfNeeded(previousOffset: CGPoint, previousContentSize: CGSize) {
        guard isReviewingScrollback else { return }

        let previousMaxOffsetY = max(0, previousContentSize.height - bounds.height)
        let newMaxOffsetY = max(0, contentSize.height - bounds.height)
        let distanceFromBottom = max(0, previousMaxOffsetY - previousOffset.y)
        let targetOffsetY = max(0, min(newMaxOffsetY - distanceFromBottom, newMaxOffsetY))

        if abs(contentOffset.y - targetOffsetY) > 0.5 {
            setContentOffset(CGPoint(x: contentOffset.x, y: targetOffsetY), animated: false)
        }
    }

    private var bottomFollowThreshold: CGFloat {
        max(28, bounds.height * 0.04)
    }
}
