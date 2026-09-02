import Foundation

struct APIConfiguration: Equatable, Sendable {
    static let infoPlistKey = "API_BASE_URL"

    let baseURL: URL

    init(baseURL: URL) throws {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host?.isEmpty == false else {
            throw APIClientError.invalidBaseURL
        }
        self.baseURL = baseURL
    }

    static func fromInfoDictionary(
        _ dictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> APIConfiguration {
        guard let value = dictionary[infoPlistKey] as? String,
              let url = URL(string: value) else {
            throw APIClientError.missingConfiguration(infoPlistKey)
        }
        return try APIConfiguration(baseURL: url)
    }
}
