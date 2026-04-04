import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        DevicesExperimentalView(store: store)
    }
}
