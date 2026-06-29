import Foundation
import Network

/// Live LAN auto-detect for self-hosted LLM servers (Plan AF #6) — **best-effort,
/// experimental**. Browses Bonjour for HTTP hosts, then probes each host's preset
/// candidate URLs (`LocalServerDiscovery.candidates`) via `ModelFetcher.testConnection`,
/// returning the reachable OpenAI-compatible servers.
///
/// Device-pending by nature: many local servers (Ollama, llama.cpp) don't advertise
/// Bonjour, and Local Network access requires the user's permission + the
/// `NSLocalNetworkUsageDescription` / `NSBonjourServices` Info.plist keys. The manual
/// preset (#5) remains the primary path; the pure candidate logic is in
/// `LocalServerDiscovery` and is unit-tested.
@MainActor
final class LocalServerScanner {

    struct DiscoveredServer: Identifiable, Equatable {
        var id: String { baseURL }
        let host: String
        let baseURL: String
        let preset: LocalServerPreset
        let modelCount: Int
        let latencyMs: Int
    }

    private var browser: NWBrowser?

    /// Browse Bonjour `_http._tcp` for up to `discoverySeconds`, then probe each
    /// discovered host's preset candidates. Returns reachable servers, fastest first.
    func scan(discoverySeconds: TimeInterval = 3) async -> [DiscoveredServer] {
        let hosts = await browseHosts(for: discoverySeconds)
        guard !hosts.isEmpty else { return [] }

        var found: [DiscoveredServer] = []
        await withTaskGroup(of: DiscoveredServer?.self) { group in
            for host in hosts {
                for candidate in LocalServerDiscovery.candidates(host: host) {
                    group.addTask {
                        let result = await ModelFetcher.testConnection(
                            provider: .custom, apiKey: "", baseURL: candidate.baseURL)
                        guard case let .ok(latencyMs, modelCount) = result else { return nil }
                        return DiscoveredServer(host: host, baseURL: candidate.baseURL,
                                                preset: candidate.preset,
                                                modelCount: modelCount, latencyMs: latencyMs)
                    }
                }
            }
            for await server in group where server != nil {
                found.append(server!)
            }
        }
        // De-dupe by base URL, fastest first.
        var seen = Set<String>()
        return found
            .sorted { $0.latencyMs < $1.latencyMs }
            .filter { seen.insert($0.baseURL).inserted }
    }

    /// Collect candidate hostnames from Bonjour `_http._tcp` service results. Maps each
    /// discovered service instance to its `<name>.local` host (best-effort — exact
    /// endpoint resolution is device-validated).
    private func browseHosts(for seconds: TimeInterval) async -> [String] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            var hosts = Set<String>()
            var resumed = false
            let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: .tcp)
            self.browser = browser

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint {
                        let host = name.hasSuffix(".local") ? name : "\(name).local"
                        hosts.insert(host)
                    }
                }
            }

            let finish: () -> Void = { [weak self] in
                guard !resumed else { return }
                resumed = true
                self?.browser?.cancel()
                self?.browser = nil
                continuation.resume(returning: Array(hosts))
            }

            browser.stateUpdateHandler = { state in
                if case .failed = state { finish() }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: finish)
        }
    }
}
