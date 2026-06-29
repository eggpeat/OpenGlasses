import Foundation

/// PURE candidate generation for LAN local-server auto-detect (Plan AF #6). Given a
/// host found on the network, produce the OpenAI-compatible base URLs worth probing
/// — one per known server preset, on its usual port. The live Bonjour browse + HTTP
/// probing lives in `LocalServerScanner`; this stays a pure, headless-testable value
/// helper (the reachability classification reuses `ModelFetcher.classify`).
enum LocalServerDiscovery {

    /// A base URL to probe on a discovered host, tagged with the preset it came from.
    struct Candidate: Equatable {
        let preset: LocalServerPreset
        let baseURL: String
    }

    /// One probe URL per preset, with the preset's `localhost` swapped for `host`
    /// (keeping the scheme, port, and `/v1` path). Skips any preset whose URL can't
    /// be rewritten. De-duplicates identical base URLs (different presets, same port).
    static func candidates(host: String) -> [Candidate] {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [Candidate] = []
        for preset in LocalServerPreset.allCases {
            guard let url = rewriteHost(preset.baseURL, to: trimmed), seen.insert(url).inserted else { continue }
            out.append(Candidate(preset: preset, baseURL: url))
        }
        return out
    }

    /// Replace the host in an OpenAI-compatible base URL, preserving scheme, port and
    /// path. Returns nil if the URL can't be parsed.
    static func rewriteHost(_ baseURL: String, to host: String) -> String? {
        guard var comps = URLComponents(string: baseURL), comps.scheme != nil else { return nil }
        comps.host = host
        return comps.string
    }
}
