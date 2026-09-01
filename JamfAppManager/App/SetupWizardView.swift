// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// First-run bootstrap: admin credentials go in once (never stored), and the
/// wizard creates the API role + client in Jamf Pro, pulls fresh client
/// credentials, saves them, and connects.
struct SetupWizardView: View {
    var prefillURL: String

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model = SetupWizardModel()
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    private let accent = Color.purple

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: 660, height: 560)
        .onAppear {
            if serverURL.isEmpty {
                serverURL = prefillURL.isEmpty
                    ? (EnrollmentDetector.enrolledServerURL() ?? "")
                    : prefillURL
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.22))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Setup Wizard")
                    .font(.title2.weight(.bold))
                Text("Creates the API role and client in Jamf Pro for you")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if model.phase == .form {
                Label("Admin credentials are used once and never stored.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch model.phase {
            case .form:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await model.run(serverURLString: normalizedURL, username: username, password: password) }
                } label: {
                    Text("Create API Client").frame(minWidth: 130)
                }
                .buttonStyle(.glassProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedURL.isEmpty || username.isEmpty || password.isEmpty)
            case .running:
                ProgressView().controlSize(.small)
            case .done:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await saveAndConnect() }
                } label: {
                    Text("Connect").frame(minWidth: 130)
                }
                .buttonStyle(.glassProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { model.phase = .form }
                    .buttonStyle(.glassProminent)
                    .tint(accent)
            }
        }
        .padding(16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .form:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card {
                        Text("Sign in with a Jamf Pro administrator account. The wizard creates a “\(SetupWizard.roleName)” API role with exactly the privileges this app needs, an API client bound to it, and hands the credentials straight to your Keychain.")
                            .foregroundStyle(.secondary)
                    }
                    card {
                        VStack(spacing: 10) {
                            wizardField("Server URL", text: $serverURL, prompt: "https://yourorg.jamfcloud.com")
                            Divider()
                            wizardField("Admin Username", text: $username, prompt: "admin")
                            Divider()
                            HStack {
                                Text("Admin Password")
                                    .frame(width: 150, alignment: .leading)
                                SecureField("", text: $password, prompt: Text("••••••••"))
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("What gets created", systemImage: "checklist")
                                .font(.headline)
                            Text("An API role named “\(SetupWizard.roleName)” with \(SetupWizard.privileges.count) privileges (read for browsing, update for saving), and an API client with a 30-minute token lifetime. Re-running the wizard updates the role and rotates the client secret.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        case .running, .done, .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card {
                        VStack(spacing: 0) {
                            ForEach(SetupWizardModel.Step.allCases, id: \.self) { step in
                                stepRow(step)
                                if step != SetupWizardModel.Step.allCases.last {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                    }
                    if model.phase == .done {
                        card {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Ready to connect", systemImage: "checkmark.seal.fill")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                LabeledContent("Client ID") {
                                    Text(model.clientID)
                                        .font(.callout.monospaced())
                                        .textSelection(.enabled)
                                }
                                Text("The client secret is held in memory and moves to your Keychain when you connect. If this client existed before, its previous secret just stopped working.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.phase == .failed {
                        card {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Setup failed", systemImage: "xmark.octagon.fill")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                Text(model.failureMessage)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                Text("The admin account needs permission to manage API roles and clients — typically a full Jamf Pro Administrator.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func stepRow(_ step: SetupWizardModel.Step) -> some View {
        let state = model.stepStates[step] ?? .pending
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: step.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(accent)
                }
            Text(step.label)
            Spacer()
            switch state {
            case .pending:
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
            case .running:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func wizardField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 150, alignment: .leading)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
        }
    }

    private var normalizedURL: String {
        serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func saveAndConnect() async {
        let record = session.upsertServer(name: "", urlString: normalizedURL, clientID: model.clientID)
        await session.connect(to: record, secret: model.clientSecret)
        if session.phase == .connected {
            dismiss()
        }
    }
}
