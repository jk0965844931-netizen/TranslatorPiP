import Foundation
import NaturalLanguage

final class TranslationService {
    private let session = URLSession.shared

    func translate(_ text: String, from sourceLang: String, to targetLang: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        let trimmed = String(text.prefix(500))

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "langpair", value: "\(sourceLang)|\(targetLang)")
        ]

        guard let url = components.url else { throw TranslationError.invalidURL }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TranslationError.serverError
        }

        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)

        guard decoded.responseStatus == 200 else {
            throw TranslationError.apiError(decoded.responseDetails ?? "Unknown error")
        }

        return decoded.responseData.translatedText
    }

    enum TranslationError: LocalizedError {
        case invalidURL
        case serverError
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL ไม่ถูกต้อง"
            case .serverError: return "Server error"
            case .apiError(let msg): return "Translation API error: \(msg)"
            }
        }
    }

    private struct MyMemoryResponse: Decodable {
        let responseData: ResponseData
        let responseStatus: Int
        let responseDetails: String?

        struct ResponseData: Decodable {
            let translatedText: String
        }
    }
}
