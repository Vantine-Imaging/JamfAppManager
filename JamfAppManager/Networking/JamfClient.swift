import Foundation

enum JamfError: LocalizedError {
    case invalidServerURL
    case authenticationFailed(String)
    case httpError(statusCode: Int, body: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "The Jamf Pro server URL is not valid."
        case .authenticationFailed(let detail):
            "Authentication failed: \(detail)"
        case .httpError(let statusCode, let body):
            "Jamf Pro returned HTTP \(statusCode). \(body.prefix(300))"
        case .decodingFailed(let detail):
            "Could not read the server response: \(detail)"
        }
    }
}

/// Async client for a single Jamf Pro server, authenticating with an
/// API Roles & Clients OAuth client (client-credentials grant).
actor JamfClient {
    let serverURL: URL
    private let clientID: String
    private let clientSecret: String
    private let session: URLSession

    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    init(serverURL: URL, clientID: String, clientSecret: String) {
        self.serverURL = serverURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Auth

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private func validToken() async throws -> String {
        // API client tokens are short-lived (~60 s), so reuse until nearly
        // expired and rely on the 401 retry in getJSON as the backstop.
        if let accessToken, tokenExpiry.timeIntervalSinceNow > 5 {
            return accessToken
        }

        var request = URLRequest(url: serverURL.appending(path: "api/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "grant_type": "client_credentials",
            "client_id": clientID,
            "client_secret": clientSecret,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JamfError.authenticationFailed("No HTTP response from server.")
        }
        guard http.statusCode == 200 else {
            let body = String(decoding: data, as: UTF8.self)
            throw JamfError.authenticationFailed("HTTP \(http.statusCode). \(body.prefix(300))")
        }

        let token: TokenResponse
        do {
            token = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw JamfError.authenticationFailed("Unreadable token response.")
        }
        accessToken = token.accessToken
        tokenExpiry = Date(timeIntervalSinceNow: token.expiresIn)
        return token.accessToken
    }

    private func formEncoded(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    /// Fetches a token without hitting any data endpoint — used by the
    /// connection screen to validate credentials.
    func verifyCredentials() async throws {
        _ = try await validToken()
    }

    // MARK: - Requests

    private func send(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        retryOnAuthFailure: Bool = true
    ) async throws -> Data {
        let token = try await validToken()
        var url = serverURL.appending(path: path)
        if !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JamfError.httpError(statusCode: -1, body: "No HTTP response.")
        }
        if http.statusCode == 401, retryOnAuthFailure {
            accessToken = nil
            return try await send(
                method: method, path: path, queryItems: queryItems, body: body,
                contentType: contentType, retryOnAuthFailure: false
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw JamfError.httpError(statusCode: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private func getJSON(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        try await send(method: "GET", path: path, queryItems: queryItems)
    }

    /// Updates a Classic API record with a partial XML document — only the
    /// elements present in the XML are changed on the server.
    func putClassicXML(path: String, xml: String) async throws {
        _ = try await send(
            method: "PUT",
            path: path,
            body: Data(xml.utf8),
            contentType: "application/xml"
        )
    }

    /// Updates a Jamf Pro API resource with a JSON document.
    func putProJSON(path: String, body: Data) async throws {
        _ = try await send(
            method: "PUT",
            path: path,
            body: body,
            contentType: "application/json"
        )
    }

    /// Simple id/name lists used by editor pickers.
    func fetchNamedIDs(path: String, key: String) async throws -> [NamedID] {
        let data = try await getJSON(path: "JSSResource/\(path)")
        do {
            let envelope = try JSONDecoder().decode([String: LossyArray<NamedID>].self, from: data)
            return (envelope[key]?.elements ?? []).sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
        } catch {
            throw JamfError.decodingFailed(String(describing: error))
        }
    }

    func fetchVPPAccounts() async throws -> [NamedID] {
        try await fetchNamedIDs(path: "vppaccounts", key: "vpp_accounts")
    }

    func fetchCategories() async throws -> [NamedID] {
        try await fetchNamedIDs(path: "categories", key: "categories")
    }

    /// Smart computer groups only — App Installer deployments can't scope to
    /// static groups.
    func fetchSmartComputerGroups() async throws -> [NamedID] {
        struct GroupEntry: Decodable {
            var id: Int
            var name: String?
            var isSmart: Bool?

            enum CodingKeys: String, CodingKey {
                case id, name
                case isSmart = "is_smart"
            }
        }
        let data = try await getJSON(path: "JSSResource/computergroups")
        do {
            let envelope = try JSONDecoder().decode([String: LossyArray<GroupEntry>].self, from: data)
            return (envelope["computer_groups"]?.elements ?? [])
                .filter { $0.isSmart == true }
                .map { NamedID(id: $0.id, name: $0.name) }
                .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        } catch {
            throw JamfError.decodingFailed(String(describing: error))
        }
    }

    // MARK: - App catalogs (read)

    func fetchAppList(catalog: AppCatalog) async throws -> [AppSummary] {
        let data = try await getJSON(path: "JSSResource/\(catalog.classicPath)")
        do {
            let envelope = try JSONDecoder().decode([String: LossyArray<AppSummary>].self, from: data)
            let apps = envelope[catalog.collectionKey]?.elements ?? []
            return apps.sorted {
                $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedAscending
            }
        } catch {
            throw JamfError.decodingFailed(String(describing: error))
        }
    }

    func fetchMobileDeviceAppDetail(id: Int) async throws -> MobileDeviceAppDetail {
        let data = try await getJSON(path: "JSSResource/mobiledeviceapplications/id/\(id)")
        do {
            let envelope = try JSONDecoder().decode([String: MobileDeviceAppDetail].self, from: data)
            guard let detail = envelope[AppCatalog.mobileDevice.recordKey] else {
                throw JamfError.decodingFailed("Missing \(AppCatalog.mobileDevice.recordKey) key.")
            }
            return detail
        } catch let error as JamfError {
            throw error
        } catch {
            throw JamfError.decodingFailed(String(describing: error))
        }
    }

    /// Fetches the entities scope editing can target: smart/static groups for
    /// the catalog's device family, plus buildings and departments.
    func fetchScopeOptions(catalog: AppCatalog) async throws -> ScopeOptions {
        let groupsPath = catalog == .mobileDevice ? "mobiledevicegroups" : "computergroups"
        let groupsKey = catalog == .mobileDevice ? "mobile_device_groups" : "computer_groups"

        async let groupsData = getJSON(path: "JSSResource/\(groupsPath)")
        async let buildingsData = getJSON(path: "JSSResource/buildings")
        async let departmentsData = getJSON(path: "JSSResource/departments")

        func decode(_ data: Data, key: String) throws -> [NamedID] {
            do {
                let envelope = try JSONDecoder().decode([String: LossyArray<NamedID>].self, from: data)
                return (envelope[key]?.elements ?? []).sorted {
                    ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
                }
            } catch {
                throw JamfError.decodingFailed(String(describing: error))
            }
        }

        return ScopeOptions(
            groups: try decode(try await groupsData, key: groupsKey),
            buildings: try decode(try await buildingsData, key: "buildings"),
            departments: try decode(try await departmentsData, key: "departments")
        )
    }

    // MARK: - Jamf App Catalog (App Installers, Pro API)

    func fetchAppInstallerDeployments() async throws -> [AppInstallerDeployment] {
        var all: [AppInstallerDeployment] = []
        var page = 0
        repeat {
            let data = try await getJSON(
                path: "api/v1/app-installers/deployments",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: "100"),
                ]
            )
            let envelope: ProAPIPage<AppInstallerDeployment>
            do {
                envelope = try JSONDecoder().decode(ProAPIPage<AppInstallerDeployment>.self, from: data)
            } catch {
                throw JamfError.decodingFailed(String(describing: error))
            }
            all.append(contentsOf: envelope.results)
            page += 1
            if envelope.results.isEmpty || all.count >= envelope.totalCount { break }
        } while true
        return all.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func fetchAppInstallerDeploymentDetail(id: String) async throws -> AppInstallerDeploymentDetail {
        let data = try await getJSON(path: "api/v1/app-installers/deployments/\(id)")
        do {
            return try JSONDecoder().decode(AppInstallerDeploymentDetail.self, from: data)
        } catch {
            throw JamfError.decodingFailed(String(describing: error))
        }
    }

    func fetchMacAppDetail(id: Int) async throws -> MacAppDetail {
        let data = try await getJSON(path: "JSSResource/macapplications/id/\(id)")
        do {
            let envelope = try JSONDecoder().decode([String: MacAppDetail].self, from: data)
            guard let detail = envelope[AppCatalog.mac.recordKey] else {
                throw JamfError.decodingFailed("Missing \(AppCatalog.mac.recordKey) key.")
            }
            return detail
        } catch let error as JamfError {
            throw error
        } catch {
            throw JamfError.decodingFailed(String(describing: error))
        }
    }
}
