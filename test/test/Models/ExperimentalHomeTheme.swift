import Foundation

enum ExperimentalHomeTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    static let storageKey = "experimentalHomeTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .dark:
            return "深色"
        case .light:
            return "浅色"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            return "自动跟随系统外观"
        case .dark:
            return "更偏监控面板的暗色氛围"
        case .light:
            return "更清爽的浅色卡片风格"
        }
    }
}
