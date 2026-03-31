import SwiftUI

struct ContentView: View {
    @StateObject private var store = ServerStore()

    var body: some View {
        TabView {
            DevicesView(store: store)
                .tabItem {
                    Label("设备", systemImage: "server.rack")
                }
            
            Text("容器")
                .tabItem {
                    Label("容器", systemImage: "square.3.layers.3d")
                }
            
            Text("告警")
                .tabItem {
                    Label("告警", systemImage: "bell")
                }
            
            SettingsView(store: store)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
