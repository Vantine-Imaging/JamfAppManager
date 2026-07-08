import SwiftUI

/// First-run / reconnect screen: pick a saved Jamf Pro server or add one.
/// Selecting a saved server fills the form; connecting saves the secret to
/// the Keychain.
struct ConnectView: View {
    @Environment(SessionStore.self) private var session

    @State private var name = ""
    @State private var urlString = ""
    @State private var clientID = ""
    @State private var secret = ""
    @State private var selectedServerID: UUID?

    private var isConnecting: Bool { session.phase == .connecting }

    private var selectedServer: ServerRecord? {
        session.servers.first { $0.id == selectedServerID }
    }

    /// True when the form matches a saved server whose secret is in the Keychain.
    private var hasStoredSecretForForm: Bool {
        guard let selectedServer,
              selectedServer.urlString == normalizedURL,
              selectedServer.clientID == clientID
        else { return false }
        return session.storedSecret(for: selectedServer) != nil
    }

    private var normalizedURL: String {
        urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.square.badge.ellipsis")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Jamf App Manager")
                    .font(.largeTitle.weight(.semibold))
                Text("Connect to Jamf Pro with an API client.\nCreate one under Settings → System → API Roles and Clients.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Form {
                if !session.servers.isEmpty {
                    Section("Saved Servers") {
                        ForEach(session.servers) { server in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.displayName)
                                    Text(server.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedServerID == server.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { select(server) }
                            .contextMenu {
                                Button("Remove Server", role: .destructive) {
                                    if selectedServerID == server.id { clearForm() }
                                    session.removeServer(server)
                                }
                            }
                        }
                    }
                }

                Section(selectedServer == nil ? "Add a Server" : "Server Details") {
                    TextField("Name (optional)", text: $name, prompt: Text("Production"))
                    TextField("Server URL", text: $urlString, prompt: Text("https://yourorg.jamfcloud.com"))
                        .textContentType(.URL)
                    TextField("Client ID", text: $clientID)
                    SecureField(
                        "Client Secret", text: $secret,
                        prompt: hasStoredSecretForForm ? Text("Saved in Keychain") : Text("Client Secret")
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 460, maxHeight: 400)
            .disabled(isConnecting)

            if case .failed(let message) = session.phase {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            Button {
                Task { await connect() }
            } label: {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 120)
                } else {
                    Text("Connect")
                        .frame(minWidth: 120)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isConnecting || normalizedURL.isEmpty || clientID.isEmpty)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear { prefill() }
    }

    private func prefill() {
        if let first = session.servers.first, urlString.isEmpty {
            select(first)
        } else if urlString.isEmpty, let enrolled = EnrollmentDetector.enrolledServerURL() {
            urlString = enrolled
        }
    }

    private func select(_ server: ServerRecord) {
        selectedServerID = server.id
        name = server.name
        urlString = server.urlString
        clientID = server.clientID
        secret = ""
    }

    private func clearForm() {
        selectedServerID = nil
        name = ""
        urlString = EnrollmentDetector.enrolledServerURL() ?? ""
        clientID = ""
        secret = ""
    }

    private func connect() async {
        let record = session.upsertServer(name: name, urlString: normalizedURL, clientID: clientID)
        selectedServerID = record.id
        await session.connect(to: record, secret: secret.isEmpty ? nil : secret)
    }
}
