import Foundation

enum BarkService {
    struct BarkError: LocalizedError, Sendable {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static func pushBaseURLString(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme,
              let host = components.host else {
            return nil
        }

        let segments = components.path.split(separator: "/").map(String.init)
        guard let key = segments.first, !key.isEmpty else {
            return nil
        }

        var normalized = "\(scheme)://\(host)"
        if let port = components.port {
            normalized += ":\(port)"
        }
        normalized += "/\(key)"
        return normalized
    }

    static func sendConfigurationTest(rawURL: String) async throws -> String {
        guard let pushURLString = pushBaseURLString(from: rawURL),
              let pushURL = URL(string: pushURLString) else {
            throw BarkError(message: "Bark 地址无效，请粘贴 Bark App 里的测试地址")
        }

        var request = URLRequest(url: pushURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let message = "bark通知成功配置"
        let queryItems = [
            URLQueryItem(name: "title", value: message),
            URLQueryItem(name: "body", value: message),
            URLQueryItem(name: "group", value: "ios-monitor"),
            URLQueryItem(name: "isArchive", value: "1")
        ]

        var components = URLComponents()
        components.queryItems = queryItems
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw BarkError(message: "Bark 连通性测试失败，请检查地址或 bark-server 是否可访问")
            }
            return "Bark 连通性测试成功，已发送“bark通知成功配置”"
        } catch {
            if let barkError = error as? BarkError {
                throw barkError
            }
            throw BarkError(message: "Bark 连通性测试失败：\(error.localizedDescription)")
        }
    }
}
