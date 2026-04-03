import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: ServerStore
    @AppStorage(HomeScreenStyle.storageKey) private var homeScreenStyleRawValue = HomeScreenStyle.classic.rawValue

    private var selectedStyle: HomeScreenStyle {
        HomeScreenStyle(rawValue: homeScreenStyleRawValue) ?? .classic
    }

    var body: some View {
        Group {
            switch selectedStyle {
            case .classic:
                DevicesClassicView(store: store)
            case .experimental:
                DevicesExperimentalView(store: store)
            }
        }
    }
}
