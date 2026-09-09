import Foundation

struct APIConfiguration: Equatable, Sendable {
    static let infoPlistKey = "API_BASE_URL"
    static let productionBaseURL = URL(string: "https://toshizo.link/tsutsuura-api/api")!

    /// An unfinished verification belongs to the server that issued it. Keep
    /// old-server challenges isolated when an installed app changes API roots.
    var verificationStorageSuiteName: String {
        let identity = baseURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        )!
        return "jp.tsutsuura.verification." + identity
    }

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
