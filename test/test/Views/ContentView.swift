import SwiftUI

struct ContentView: View {
    @StateObject private var store = ServerStore()
    @StateObject private var terminalWorkspace = TerminalWorkspace()

    var body: some View {
        configuredTabView
    }

    @ViewBuilder
    private var configuredTabView: some View {
        if #available(iOS 26.0, *) {
            rootTabView
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            rootTabView
        }
    }

    private var rootTabView: some View {
        TabView {
            DevicesView(store: store)
                .tabItem {
                    Label("概览", systemImage: "server.rack")
                }

            Text("容器")
                .tabItem {
                    Label("容器", systemImage: "square.3.layers.3d")
                }

            AlertsView(store: store)
                .tabItem {
                    Label("告警", systemImage: "bell")
                }

            SettingsView(store: store)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .environmentObject(terminalWorkspace)
    }
}

#Preview {
    ContentView()
}
