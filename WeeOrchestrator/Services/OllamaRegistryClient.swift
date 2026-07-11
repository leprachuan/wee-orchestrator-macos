import Foundation

/// A single downloadable tag variant of a model discovered on the public Ollama registry
/// (ollama.com/library). Only variants meeting the 64K context-window requirement are
/// ever surfaced to callers — see `OllamaRegistryClient.minimumContextWindow`.
struct OllamaRegistryModel: Identifiable, Hashable {
    let baseName: String
    let tag: String
    let contextWindow: Int
    let sizeGB: Double?
    let modalities: String?

    var fullTag: String { tag.isEmpty || tag == "latest" ? baseName : "\(baseName):\(tag)" }
    var id: String { fullTag }

    var displayName: String {
        tag.isEmpty || tag == "latest" ? baseName : "\(baseName) (\(tag))"
    }

    var sizeLabel: String {
        guard let sizeGB else { return "Unknown size" }
        return "~\(String(format: "%.1f", sizeGB)) GB"
    }
}

/// Best-effort client for the public Ollama model registry. Ollama does not publish a
/// stable JSON search API, so this scrapes the same server-rendered HTML the
/// ollama.com website itself renders (search results page + per-model tag listing).
/// Every parse function degrades gracefully to an empty result on unexpected markup
/// rather than throwing, so callers can always fall back to the static catalog.
enum OllamaRegistryClient {
    static let minimumContextWindow = 64_000

    private static let userAgent = "WeeOrchestratorMac/1.0 (+https://github.com/leprachuan/wee-orchestrator-macos)"

    enum RegistryError: Error {
        case badResponse
    }

    /// Searches ollama.com for base model families matching `query` (e.g. "qwen3.6" -> "qwen3.6").
    static func searchBaseModels(query: String, limit: Int = 6) async throws -> [String] {
        var components = URLComponents(string: "https://ollama.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }
        let html = try await fetchHTML(url)
        return parseBaseModelNames(from: html, limit: limit)
    }

    /// Fetches every 64K+ context tag variant published for `baseName` on its Ollama library page.
    static func fetchTagVariants(baseName: String) async throws -> [OllamaRegistryModel] {
        guard let url = URL(string: "https://ollama.com/library/\(baseName)") else { return [] }
        let html = try await fetchHTML(url)
        return parseTagVariants(from: html, baseName: baseName)
    }

    /// Convenience: search + expand each matching base model's tags in one call, already
    /// filtered to the 64K context requirement and sorted (largest context, then smallest size).
    static func search(query: String, maxBaseModels: Int = 6) async throws -> [OllamaRegistryModel] {
        let baseNames = try await searchBaseModels(query: query, limit: maxBaseModels)
        var results: [OllamaRegistryModel] = []
        for baseName in baseNames {
            if let variants = try? await fetchTagVariants(baseName: baseName) {
                results.append(contentsOf: variants)
            }
        }
        return results.sorted {
            if $0.contextWindow != $1.contextWindow { return $0.contextWindow > $1.contextWindow }
            return ($0.sizeGB ?? .greatestFiniteMagnitude) < ($1.sizeGB ?? .greatestFiniteMagnitude)
        }
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RegistryError.badResponse }
        guard let html = String(data: data, encoding: .utf8) else { throw RegistryError.badResponse }
        return html
    }

    static func parseBaseModelNames(from html: String, limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"href="/library/([a-zA-Z0-9._-]+)""#) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var names: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: html) else { continue }
            let name = String(html[nameRange])
            if seen.insert(name).inserted { names.append(name) }
            if names.count >= limit { break }
        }
        return names
    }

    static func parseTagVariants(from html: String, baseName: String) -> [OllamaRegistryModel] {
        let escapedBase = NSRegularExpression.escapedPattern(for: baseName)
        let pattern = #"href="/library/"# + escapedBase
            + #":([a-zA-Z0-9._-]+)".*?([0-9]+(?:\.[0-9]+)?)(GB|MB) · ([0-9]+)K context window(?: · ([^·<]+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seenTags = Set<String>()
        var results: [OllamaRegistryModel] = []
        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let sizeRange = Range(match.range(at: 2), in: html),
                  let unitRange = Range(match.range(at: 3), in: html),
                  let contextRange = Range(match.range(at: 4), in: html) else { continue }
            let tag = String(html[tagRange])
            guard seenTags.insert(tag).inserted else { continue }
            let sizeValue = Double(html[sizeRange]) ?? 0
            let sizeGB = String(html[unitRange]) == "MB" ? sizeValue / 1024 : sizeValue
            let contextWindow = (Int(html[contextRange]) ?? 0) * 1_000
            var modalities: String?
            if match.range(at: 5).location != NSNotFound, let modalityRange = Range(match.range(at: 5), in: html) {
                modalities = String(html[modalityRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            results.append(OllamaRegistryModel(baseName: baseName, tag: tag, contextWindow: contextWindow, sizeGB: sizeGB, modalities: modalities))
        }
        return results.filter { $0.contextWindow >= minimumContextWindow }
    }
}
