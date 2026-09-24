import SwiftUI
import UIKit

struct SSHServersView: View {
    @StateObject private var store = SSHConfigStore.shared
    @State private var searchText = ""
    @State private var editingServer: SSHServerEntry?
    @State private var showingAddServerSheet = false
    @State private var showingAddActionSheet = false
    @State private var showingGenerateKeySheet = false
    @State private var showingImportKeySheet = false
    @State private var viewingKey: SSHKeyEntry?
    @State private var deleteServerConfirm: SSHServerEntry?
    @State private var deleteKeyConfirm: SSHKeyEntry?
    @State private var deleteKnownHostConfirm: SSHKnownHostEntry?
    @State private var showingClearKnownHostsConfirm = false
    @State private var errorMessage: String?
    @State private var showAdvanced = false

    private var isEmpty: Bool {
        store.servers.isEmpty && store.keys.isEmpty
    }

    private var filteredServers: [SSHServerEntry] {
        if searchText.isEmpty { return store.servers }
        return store.servers.filter {
            $0.alias.localizedCaseInsensitiveContains(searchText) ||
            $0.hostname.localizedCaseInsensitiveContains(searchText) ||
            ($0.note ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if isEmpty {
                emptyStateView
            } else {
                contentList
            }
        }
        .navigationTitle("SSH Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddActionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .confirmationDialog(
            "Add",
            isPresented: $showingAddActionSheet,
            titleVisibility: .hidden
        ) {
            Button("Add Server") {
                showingAddServerSheet = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddServerSheet) {
            SSHAddServerSheet()
        }
        .sheet(item: $editingServer) { server in
            SSHServerDetailSheet(server: server)
        }
        .sheet(isPresented: $showingGenerateKeySheet) {
            SSHKeyGenerateSheet { name, type in
                Task {
                    do {
                        try await store.generateKey(name: name, type: type)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showingImportKeySheet) {
            SSHKeyImportSheet { name, content in
                do {
                    try store.importPrivateKey(name: name, content: content)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $viewingKey) { key in
            SSHKeyDetailSheet(key: key, publicKey: store.publicKey(name: key.name))
        }
        .alert(
            AppLocalized("Delete this server?"),
            isPresented: Binding(
                get: { deleteServerConfirm != nil },
                set: { if !$0 { deleteServerConfirm = nil } }
            ),
            presenting: deleteServerConfirm
        ) { server in
            Button(AppLocalized("Delete"), role: .destructive) {
                do {
                    try store.removeServer(alias: server.alias)
                    store.deletePassword(alias: server.alias)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button(AppLocalized("Cancel"), role: .cancel) {}
        } message: { server in
            Text(AppLocalized("Server \"\(server.alias)\" will be removed from ~/.ssh/config."))
        }
        .alert(
            AppLocalized("Delete this key?"),
            isPresented: Binding(
                get: { deleteKeyConfirm != nil },
                set: { if !$0 { deleteKeyConfirm = nil } }
            ),
            presenting: deleteKeyConfirm
        ) { key in
            Button(AppLocalized("Delete"), role: .destructive) {
                do {
                    try store.deleteKey(name: key.name)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button(AppLocalized("Cancel"), role: .cancel) {}
        } message: { key in
            Text(AppLocalized("Key \"\(key.name)\" and its public key will be deleted."))
        }
        .alert(
            AppLocalized("Delete this known host?"),
            isPresented: Binding(
                get: { deleteKnownHostConfirm != nil },
                set: { if !$0 { deleteKnownHostConfirm = nil } }
            ),
            presenting: deleteKnownHostConfirm
        ) { host in
            Button(AppLocalized("Delete"), role: .destructive) {
                do {
                    try store.removeKnownHost(id: host.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button(AppLocalized("Cancel"), role: .cancel) {}
        } message: { host in
            Text(AppLocalized("Host \"\(host.host)\" will be removed from known_hosts."))
        }
        .alert(
            AppLocalized("Clear all known hosts?"),
            isPresented: $showingClearKnownHostsConfirm
        ) {
            Button(AppLocalized("Clear All"), role: .destructive) {
                do {
                    try store.clearKnownHosts()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button(AppLocalized("Cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalized("All entries will be removed from ~/.ssh/known_hosts."))
        }
        .alert(
            AppLocalized("Error"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(AppLocalized("OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            store.reload()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Connect to Your Servers")
                    .font(.title2.bold())
                Text("Enter an address and password to set up a connection. Keys are handled automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showingAddServerSheet = true
                } label: {
                    Text("Add Server")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    // MARK: - Content List (MCP Pattern)

    private var contentList: some View {
        List {
            Section {
                ForEach(filteredServers) { server in
                    Button {
                        editingServer = server
                    } label: {
                        serverRow(server)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteServerConfirm = server
                        } label: {
                            Label(AppLocalized("Delete"), systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    let serversToDelete = offsets.map { filteredServers[$0] }
                    if let first = serversToDelete.first {
                        deleteServerConfirm = first
                    }
                }
            }

            Section {
                DisclosureGroup(
                    isExpanded: $showAdvanced,
                    content: {
                        advancedContent
                    },
                    label: {
                        Label("Advanced: Keys & Trust Records", systemImage: "gearshape.2")
                            .font(.body)
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Filter servers")
    }

    @ViewBuilder
    private var advancedContent: some View {
        if !store.keys.isEmpty {
            Text("Keys")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(store.keys) { key in
                keyRow(key)
            }
        }

        if !store.knownHosts.isEmpty {
            Text("Known Hosts")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            ForEach(store.knownHosts) { host in
                knownHostRow(host)
            }
            Button(role: .destructive) {
                showingClearKnownHostsConfirm = true
            } label: {
                Label("Clear All Known Hosts", systemImage: "trash")
            }
        }

        Text("Dependencies")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        depRow("SSH Client", ok: store.deps.ssh)
        depRow("SSH Keygen", ok: store.deps.sshKeygen)
        depRow("SSH Pass", ok: store.deps.sshpass)

        HStack(spacing: 8) {
            Button {
                showingGenerateKeySheet = true
            } label: {
                Label("Generate Key", systemImage: "key")
            }
            .buttonStyle(.bordered)

            Button {
                showingImportKeySheet = true
            } label: {
                Label("Import Key", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
        .padding(.top, 8)
    }

    // MARK: - Row Builders

    private func serverRow(_ server: SSHServerEntry) -> some View {
        HStack(spacing: 12) {
            let state = store.testStates[server.alias]
            Circle()
                .fill(state == nil ? Color.gray : (state! ? Color.green : Color.red))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.alias)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text("\(server.user)@\(server.hostname)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if server.port != 22 {
                        Text(":\(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func keyRow(_ key: SSHKeyEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(key.keyType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                        .foregroundStyle(.blue)
                    let refCount = store.servers.filter { $0.identityFileName == key.name }.count
                    if refCount > 0 {
                        Text("\(refCount) referenced")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewingKey = key
        }
    }

    @ViewBuilder
    private func knownHostRow(_ host: SSHKnownHostEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.host)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            Text(host.fingerprint)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteKnownHostConfirm = host
            } label: {
                Label(AppLocalized("Delete"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func depRow(_ name: String, ok: Bool) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }
}

// MARK: - Add Server Sheet (One-Touch Flow)

private struct SSHAddServerSheet: View {
    @StateObject private var store = SSHConfigStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hostname = ""
    @State private var port = "22"
    @State private var user = "root"
    @State private var authMode = "password"
    @State private var identityFileName: String?
    @State private var password = ""
    @State private var alias = ""
    @State private var note = ""
    @State private var showCustomOptions = false
    @State private var isSettingUp = false
    @State private var setupResult: SSHTestResult?

    private var currentKeys: [SSHKeyEntry] { store.keys }
    private var currentServers: [SSHServerEntry] { store.servers }

    private var isValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !user.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil &&
        (authMode == "key" ? identityFileName != nil || currentKeys.isEmpty : true)
    }

    private var effectiveAlias: String {
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return SSHConfigStore.generateAlias(from: hostname, existing: currentServers)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Hostname", text: $hostname)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Port", text: $port)
                        .font(.system(.body, design: .monospaced))
                        .keyboardType(.numberPad)

                    TextField("User", text: $user)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMode) {
                        Text("Password").tag("password")
                        Text("SSH Key").tag("key")
                    }

                    if authMode == "password" {
                        SecureField("Password", text: $password)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        if currentKeys.isEmpty {
                            Text("No keys available — will generate one automatically")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Key", selection: $identityFileName) {
                                Text("None").tag(String?.none)
                                ForEach(currentKeys) { key in
                                    Text(key.name).tag(String?.some(key.name))
                                }
                            }
                        }
                    }
                }

                DisclosureGroup("Custom Options", isExpanded: $showCustomOptions) {
                    TextField("Alias (auto-generated if empty)", text: $alias)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)

                    if authMode == "password" {
                        Text("Note: agent cannot use password-only connections. A key will be set up automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let result = setupResult {
                    Section {
                        if result.ok {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Connected — agent can use `ssh \(effectiveAlias)`", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline.bold())
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Connection failed", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.subheadline.bold())
                                Text(result.message)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSettingUp {
                        ProgressView()
                    } else if setupResult?.ok == true {
                        Button("Done") { dismiss() }
                    } else {
                        Button(setupResult != nil ? "Retry" : "Set Up") {
                            performSetup()
                        }
                        .disabled(!isValid || isSettingUp)
                    }
                }
            }
        }
    }

    private func performSetup() {
        isSettingUp = true
        setupResult = nil
        let entry = SSHServerEntry(
            alias: effectiveAlias,
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            user: user.trimmingCharacters(in: .whitespaces),
            identityFileName: identityFileName,
            authMode: authMode,
            note: note.isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let pwd = authMode == "password" ? password : nil
        let keysSnapshot = currentKeys
        Task {
            let result = await store.performOneTouchSetup(
                server: entry, password: pwd, keys: keysSnapshot)
            setupResult = result
            isSettingUp = false
        }
    }
}

// MARK: - Server Detail Sheet

private struct SSHServerDetailSheet: View {
    let server: SSHServerEntry

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SSHConfigStore.shared
    @State private var alias: String
    @State private var hostname: String
    @State private var port: String
    @State private var user: String
    @State private var authMode: String
    @State private var identityFileName: String?
    @State private var password: String
    @State private var note: String
    @State private var isTesting = false
    @State private var testResult: SSHTestResult?
    @State private var showingDeleteConfirm = false
    @State private var showingGenerateKeySheet = false

    init(server: SSHServerEntry) {
        self.server = server
        _alias = State(initialValue: server.alias)
        _hostname = State(initialValue: server.hostname)
        _port = State(initialValue: String(server.port))
        _user = State(initialValue: server.user)
        _authMode = State(initialValue: server.authMode)
        _identityFileName = State(initialValue: server.identityFileName)
        _password = State(initialValue: SSHConfigStore.shared.password(alias: server.alias) ?? "")
        _note = State(initialValue: server.note ?? "")
    }

    private var isHostKeyError: Bool {
        guard let result = testResult, !result.ok else { return false }
        return SSHConfigStore.isHostKeyError(result.message)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isHostKeyError {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Server fingerprint has changed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline.bold())
                            Text("The stored fingerprint no longer matches the server. This can happen when the server is reinstalled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Clear Old Fingerprint & Retry") {
                                clearAndRetry()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section("Connection") {
                    TextField("Alias", text: $alias)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()

                    TextField("Hostname", text: $hostname)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()

                    TextField("Port", text: $port)
                        .font(.system(.body, design: .monospaced))
                        .keyboardType(.numberPad)

                    TextField("User", text: $user)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMode) {
                        Text("Password").tag("password")
                        Text("SSH Key").tag("key")
                    }

                    if authMode == "key" {
                        if store.keys.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No SSH keys available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Generate Key") {
                                    showingGenerateKeySheet = true
                                }
                            }
                        } else {
                            Picker("Key", selection: $identityFileName) {
                                Text("None").tag(String?.none)
                                ForEach(store.keys) { key in
                                    Text(key.name).tag(String?.some(key.name))
                                }
                            }
                        }
                    } else {
                        SecureField("Password", text: $password)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTesting ? "Testing…" : "Test Connection")
                                .bold()
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.ok ? .green : .red)
                                Text(result.ok ? "Connected" : "Failed")
                                    .font(.subheadline.bold())
                                Text("(\(result.elapsedMs)ms)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !result.ok {
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Test")
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Server", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Server Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(alias.trimmingCharacters(in: .whitespaces).isEmpty ||
                              hostname.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert(
                AppLocalized("Delete this server?"),
                isPresented: $showingDeleteConfirm
            ) {
                Button(AppLocalized("Delete"), role: .destructive) {
                    do {
                        try store.removeServer(alias: server.alias)
                        store.deletePassword(alias: server.alias)
                        dismiss()
                    } catch {
                        // Handled by parent
                    }
                }
                Button(AppLocalized("Cancel"), role: .cancel) {}
            } message: {
                Text(AppLocalized("Server \"\(server.alias)\" will be removed from ~/.ssh/config."))
            }
            .sheet(isPresented: $showingGenerateKeySheet) {
                SSHKeyGenerateSheet { name, type in
                    Task {
                        do {
                            try await store.generateKey(name: name, type: type)
                            identityFileName = name
                        } catch {
                            // Error handled by parent
                        }
                    }
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let entry = SSHServerEntry(
            alias: alias.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            user: user.trimmingCharacters(in: .whitespaces),
            identityFileName: identityFileName,
            authMode: authMode,
            note: nil
        )
        let pwd = authMode == "password" ? password : nil
        Task {
            let result = await store.testConnection(entry, password: pwd)
            testResult = SSHTestResult(
                ok: result.ok,
                message: result.ok ? result.message : SSHConfigStore.humanize(result.message),
                elapsedMs: result.elapsedMs)
            isTesting = false
        }
    }

    private func clearAndRetry() {
        let host = hostname.trimmingCharacters(in: .whitespaces)
        let p = Int(port) ?? 22
        _ = store.clearStaleFingerprint(for: host, port: p)
        testConnection()
    }

    private func saveChanges() {
        let entry = SSHServerEntry(
            alias: alias.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            user: user.trimmingCharacters(in: .whitespaces),
            identityFileName: identityFileName,
            authMode: authMode,
            note: note.isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            if alias != server.alias {
                try store.removeServer(alias: server.alias)
                store.deletePassword(alias: server.alias)
            }
            try store.upsertServer(entry)
            if authMode == "password" && !password.isEmpty {
                store.setPassword(password, alias: entry.alias)
            }
            dismiss()
        } catch {
            // Error handled by parent
        }
    }
}

// MARK: - Key Generate Sheet

private struct SSHKeyGenerateSheet: View {
    let onGenerate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = "id_ed25519"
    @State private var type = "ed25519"

    var body: some View {
        NavigationStack {
            Form {
                Section("Key Name") {
                    TextField("Name", text: $name)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                }

                Section("Key Type") {
                    Picker("Type", selection: $type) {
                        Text("Ed25519").tag("ed25519")
                        Text("RSA").tag("rsa")
                    }
                }
            }
            .navigationTitle("Generate Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        onGenerate(name, type)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Key Import Sheet

private struct SSHKeyImportSheet: View {
    let onImport: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Key Name") {
                    TextField("Name", text: $name)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                }

                Section("Private Key Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(name, content)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || content.isEmpty)
                }
            }
        }
    }
}

// MARK: - Key Detail Sheet

private struct SSHKeyDetailSheet: View {
    let key: SSHKeyEntry
    let publicKey: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showingExportConfirm = false
    @State private var exportedPrivateKey: Data?
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Public Key") {
                    if let publicKey = publicKey {
                        Text(publicKey)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = publicKey
                        } label: {
                            Label("Copy Public Key", systemImage: "doc.on.clipboard")
                        }
                    } else {
                        Text("No public key available")
                            .foregroundStyle(.secondary)
                    }
                }

                if key.hasPrivate {
                    Section {
                        Button {
                            showingExportConfirm = true
                        } label: {
                            Label("Export Private Key", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Key", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(key.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                AppLocalized("Export private key?"),
                isPresented: $showingExportConfirm
            ) {
                Button(AppLocalized("Export"), role: .destructive) {
                    exportedPrivateKey = SSHConfigStore.shared.exportPrivateKey(name: key.name)
                    if let data = exportedPrivateKey, let str = String(data: data, encoding: .utf8) {
                        UIPasteboard.general.string = str
                    }
                }
                Button(AppLocalized("Cancel"), role: .cancel) {}
            } message: {
                Text(AppLocalized("The private key will be copied to the clipboard. Handle with care."))
            }
            .alert(
                AppLocalized("Delete this key?"),
                isPresented: $showingDeleteConfirm
            ) {
                Button(AppLocalized("Delete"), role: .destructive) {
                    do {
                        try SSHConfigStore.shared.deleteKey(name: key.name)
                        dismiss()
                    } catch {
                        // Error handled by parent
                    }
                }
                Button(AppLocalized("Cancel"), role: .cancel) {}
            } message: {
                Text(AppLocalized("Key \"\(key.name)\" and its public key will be deleted."))
            }
        }
    }
}
