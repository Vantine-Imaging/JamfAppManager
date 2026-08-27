// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Saved Jamf Pro servers plus the connection state for the active one.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case needsSetup
        case connecting
        case connected
        case failed(String)
    }

    private(set) var phase: Phase = .needsSetup
    private(set) var client: JamfClient?
    private(set) var activeServerID: UUID?

    private(set) var servers: [ServerRecord] {
        didSet { persistServers() }
    }

    private static let serversKey = "jamf.servers"
    private static let legacyServerKey = "jamf.serverURL"
    private static let legacyClientIDKey = "jamf.clientID"

    var activeServer: ServerRecord? {
        servers.first { $0.id == activeServerID }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.serversKey),
           let saved = try? JSONDecoder().decode([ServerRecord].self, from: data) {
            servers = saved
        } else if let legacyURL = UserDefaults.standard.string(forKey: Self.legacyServerKey),
                  !legacyURL.isEmpty {
            // Migrate the single-server setup from earlier builds.
            let legacyClientID = UserDefaults.standard.string(forKey: Self.legacyClientIDKey) ?? ""
            servers = [ServerRecord(name: "", urlString: legacyURL, clientID: legacyClientID)]
            UserDefaults.standard.removeObject(forKey: Self.legacyServerKey)
            UserDefaults.standard.removeObject(forKey: Self.legacyClientIDKey)
            persistServers()
        } else {
            servers = []
        }
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: Self.serversKey)
        }
    }

    func storedSecret(for server: ServerRecord) -> String? {
        KeychainStore.loadSecret(server: server.urlString, clientID: server.clientID)
    }

    /// Adds or updates a server record (matched by URL + client ID) and
    /// returns the persisted record.
    func upsertServer(name: String, urlString: String, clientID: String) -> ServerRecord {
        let trimmedURL = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let index = servers.firstIndex(where: {
            $0.urlString == trimmedURL && $0.clientID == clientID
        }) {
            servers[index].name = name
            return servers[index]
        }
        let record = ServerRecord(name: name, urlString: trimmedURL, clientID: clientID)
        servers.append(record)
        return record
    }

    func removeServer(_ server: ServerRecord) {
        KeychainStore.deleteSecret(server: server.urlString, clientID: server.clientID)
        servers.removeAll { $0.id == server.id }
        if activeServerID == server.id {
            disconnect()
        }
    }

    /// Connects to a saved server. Pass a secret when the user just entered
    /// one (it is saved to the Keychain on success); otherwise the stored
    /// secret is used.
    func connect(to server: ServerRecord, secret: String? = nil) async {
        guard let url = URL(string: server.urlString), url.scheme == "https" else {
            phase = .failed("Enter the full server URL, e.g. https://yourorg.jamfcloud.com")
            return
        }
        guard !server.clientID.isEmpty else {
            phase = .failed("Enter the API client ID.")
            return
        }
        let resolvedSecret = secret ?? storedSecret(for: server)
        guard let resolvedSecret, !resolvedSecret.isEmpty else {
            phase = .failed("Enter the API client secret for \(server.displayName).")
            return
        }

        phase = .connecting
        let candidate = JamfClient(serverURL: url, clientID: server.clientID, clientSecret: resolvedSecret)
        do {
            try await candidate.verifyCredentials()
            if secret != nil {
                try? KeychainStore.saveSecret(resolvedSecret, server: server.urlString, clientID: server.clientID)
            }
            client = candidate
            activeServerID = server.id
            phase = .connected
        } catch {
            client = nil
            activeServerID = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// Switches to another saved server, falling back to the connect screen
    /// when its secret isn't in the Keychain.
    func switchTo(_ server: ServerRecord) async {
        client = nil
        await connect(to: server)
    }

    func disconnect() {
        client = nil
        activeServerID = nil
        phase = .needsSetup
    }
}