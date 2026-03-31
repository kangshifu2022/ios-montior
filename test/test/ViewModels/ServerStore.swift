import Foundation
import SwiftUI
import Combine

class ServerStore: ObservableObject {
    @Published var servers: [ServerConfig] = []
    
    private let key = "saved_servers"
    
    init() {
        load()
    }
    
    func add(_ server: ServerConfig) {
        servers.append(server)
        save()
    }
    
    func update(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            save()
        }
    }
    
    func delete(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        save()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = decoded
        }
    }
}
