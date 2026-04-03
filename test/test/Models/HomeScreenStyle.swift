import Foundation

enum HomeScreenStyle: String, CaseIterable, Identifiable {
    case classic
    case experimental

    static let storageKey = "home_screen_style"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            return "经典版"
        case .experimental:
            return "实验版"
        }
    }

    var subtitle: String {
        switch self {
        case .classic:
            return "保持当前首屏布局"
        case .experimental:
            return "用于尝试新的首页结构"
        }
    }
}
