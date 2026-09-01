// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Bootstraps Jamf Pro for this app: with admin credentials supplied once
/// (and never stored), it creates — or updates on re-run — a "Jamf App
/// Manager" API Role carrying exactly the privileges the app needs, an API
/// client bound to that role, and returns fresh client credentials.
enum SetupWizard {
    static let roleName = "Jamf App Manager"
    static let integrationName = "Jamf App Manager"
    /// 30 minutes instead of Jamf's short default, so the app re-authenticates
    /// far less often.
    static let tokenLifetimeSeconds = 1800

    static let privileges = [
        "Read Mac Applications",
        "Update Mac Applications",
        "Read Mobile Device Applications",
        "Update Mobile Device Applications",
        "Read Smart Computer Groups",
        "Read Static Computer Groups",
        "Read Smart Mobile Device Groups",
        "Read Static Mobile Device Groups",
        "Read Buildings",
        "Read Departments",
        "Read Categories",
        "Read Volume Purchasing Locations",
    ]

    struct WizardError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    // MARK: - Requests

    private static func request(
        _ method: String, _ url: URL, bearer: String? = nil, basic: (String, String)? = nil,
        json: Encodable? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let (user, pass) = basic {
            let credentials = Data("\(user):\(pass)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WizardError(message: "No HTTP response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WizardError(message: friendlyMessage(status: http.statusCode, body: data))
        }
        return data
    }

    /// Jamf Pro error envelope: {httpStatus, errors: [{code, description, field}]}.
    private static func friendlyMessage(status: Int, body: Data) -> String {
        struct Envelope: Decodable {
            struct Item: Decodable {
                var code: String?
                var description: String?
                var field: String?
            }
            var errors: [Item]?
        }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: body))?.errors?
            .compactMap { item -> String? in
                guard let description = item.description else { return item.code }
                return item.field.map { "\(description) (\($0))" } ?? description
            }
            .joined(separator: "; ")
        switch status {
        case 401: return "Jamf Pro rejected the admin credentials (HTTP 401)."
        case 403: return "That account can't manage API roles and clients (HTTP 403) — it needs administrator privileges."
        default: return "HTTP \(status): \(detail ?? String(decoding: body.prefix(200), as: UTF8.self))"
        }
    }

    // MARK: - Steps

    /// POST /api/v1/auth/token with Basic auth. The credentials live only in
    /// this call; the returned token is used for the remaining steps.
    static func adminToken(server: URL, username: String, password: String) async throws -> String {
        struct TokenResponse: Decodable { var token: String }
        let data = try await request(
            "POST", server.appending(path: "api/v1/auth/token"), basic: (username, password)
        )
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }

    /// Creates the API role, or updates its privileges if a role with the
    /// same name already exists (so re-running the wizard heals the role).
    static func ensureRole(server: URL, token: String) async throws {
        struct Role: Decodable { var id: String?; var displayName: String? }
        struct RolePage: Decodable { var totalCount: Int; var results: [Role] }
        struct RoleBody: Encodable { var displayName: String; var privileges: [String] }

        let listURL = server.appending(path: "api/v1/api-roles")
            .appending(queryItems: [URLQueryItem(name: "page-size", value: "200")])
        let page = try JSONDecoder().decode(RolePage.self, from: try await request("GET", listURL, bearer: token))
        let body = RoleBody(displayName: roleName, privileges: privileges)

        if let existing = page.results.first(where: { $0.displayName == roleName }), let id = existing.id {
            _ = try await request("PUT", server.appending(path: "api/v1/api-roles/\(id)"), bearer: token, json: body)
        } else {
            _ = try await request("POST", server.appending(path: "api/v1/api-roles"), bearer: token, json: body)
        }
    }

    /// Creates the API client bound to the role, or reuses an existing one
    /// with the same display name. Returns its id.
    static func ensureIntegration(server: URL, token: String) async throws -> Int {
        struct Integration: Decodable { var id: Int?; var displayName: String? }
        struct IntegrationPage: Decodable { var totalCount: Int; var results: [Integration] }
        struct IntegrationBody: Encodable {
            var authorizationScopes: [String]
            var displayName: String
            var enabled: Bool
            var accessTokenLifetimeSeconds: Int
        }

        let listURL = server.appending(path: "api/v1/api-integrations")
            .appending(queryItems: [URLQueryItem(name: "page-size", value: "200")])
        let page = try JSONDecoder().decode(IntegrationPage.self, from: try await request("GET", listURL, bearer: token))
        let body = IntegrationBody(
            authorizationScopes: [roleName],
            displayName: integrationName,
            enabled: true,
            accessTokenLifetimeSeconds: tokenLifetimeSeconds
        )

        if let existing = page.results.first(where: { $0.displayName == integrationName }), let id = existing.id {
            _ = try await request("PUT", server.appending(path: "api/v1/api-integrations/\(id)"), bearer: token, json: body)
            return id
        }
        struct Created: Decodable { var id: Int }
        let data = try await request("POST", server.appending(path: "api/v1/api-integrations"), bearer: token, json: body)
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    /// Generates (or rotates) the client secret. Rotation invalidates any
    /// previous secret for this client — the UI warns about that.
    static func generateCredentials(server: URL, token: String, integrationID: Int) async throws -> (clientID: String, clientSecret: String) {
        struct Credentials: Decodable { var clientId: String; var clientSecret: String }
        let data = try await request(
            "POST",
            server.appending(path: "api/v1/api-integrations/\(integrationID)/client-credentials"),
            bearer: token
        )
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        return (credentials.clientId, credentials.clientSecret)
    }
}

/// Drives the wizard UI through its steps.
@MainActor
@Observable
final class SetupWizardModel {
    enum Step: Int, CaseIterable {
        case authenticate
        case role
        case client
        case credentials

        var label: String {
            switch self {
            case .authenticate: "Sign in with the admin account"
            case .role: "Create the “Jamf App Manager” API role"
            case .client: "Create the API client"
            case .credentials: "Generate the client secret"
            }
        }

        var symbol: String {
            switch self {
            case .authenticate: "person.badge.key"
            case .role: "checklist"
            case .client: "app.connected.to.app.below.fill"
            case .credentials: "key.fill"
            }
        }
    }

    enum StepState: Equatable {
        case pending
        case running
        case done
        case failed(String)
    }

    enum Phase {
        case form
        case running
        case done
        case failed
    }

    var phase: Phase = .form
    private(set) var stepStates: [Step: StepState] = [:]
    private(set) var clientID = ""
    private(set) var clientSecret = ""
    private(set) var failureMessage = ""

    func run(serverURLString: String, username: String, password: String) async {
        guard let server = URL(string: serverURLString), server.scheme == "https" else {
            failureMessage = "Enter the full server URL, e.g. https://yourorg.jamfcloud.com"
            phase = .failed
            return
        }
        phase = .running
        for step in Step.allCases { stepStates[step] = .pending }

        do {
            stepStates[.authenticate] = .running
            let token = try await SetupWizard.adminToken(server: server, username: username, password: password)
            stepStates[.authenticate] = .done

            stepStates[.role] = .running
            try await SetupWizard.ensureRole(server: server, token: token)
            stepStates[.role] = .done

            stepStates[.client] = .running
            let integrationID = try await SetupWizard.ensureIntegration(server: server, token: token)
            stepStates[.client] = .done

            stepStates[.credentials] = .running
            let credentials = try await SetupWizard.generateCredentials(server: server, token: token, integrationID: integrationID)
            stepStates[.credentials] = .done

            clientID = credentials.clientID
            clientSecret = credentials.clientSecret
            phase = .done
        } catch {
            for step in Step.allCases where stepStates[step] == .running {
                stepStates[step] = .failed(error.localizedDescription)
            }
            failureMessage = error.localizedDescription
            phase = .failed
        }
    }
}
