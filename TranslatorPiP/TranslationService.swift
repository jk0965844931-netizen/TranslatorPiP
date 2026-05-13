import Translation

@available(iOS 17.4, *)
final class TranslationService {
    private var session: TranslationSession?
    private var configuration: TranslationSession.Configuration?

    func configure(from sourceLanguage: Locale.Language, to targetLanguage: Locale.Language) {
        configuration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    func translate(_ text: String) async throws -> String {
        guard let configuration else {
            throw TranslationError.notConfigured
        }
        if session == nil {
            session = TranslationSession(configuration: configuration)
        }
        guard let session else { throw TranslationError.sessionUnavailable }
        let response = try await session.translate(text)
        return response.targetText
    }

    func reset() {
        session = nil
    }

    enum TranslationError: LocalizedError {
        case notConfigured
        case sessionUnavailable

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "TranslationService ยังไม่ได้ตั้งค่า"
            case .sessionUnavailable: return "ไม่สามารถสร้าง Translation Session ได้"
            }
        }
    }
}

final class TranslationServiceLegacy {
    func translate(_ text: String, from: String, to: String) async throws -> String {
        let urlString = "https://api.mymemory.translated.net/get?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&langpair=\(from)|\(to)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        return json.responseData.translatedText
    }

    private struct MyMemoryResponse: Decodable {
        let responseData: ResponseData
        struct ResponseData: Decodable {
            let translatedText: String
        }
    }
}
