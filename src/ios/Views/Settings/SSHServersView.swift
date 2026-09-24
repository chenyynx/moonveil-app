import SwiftUI
import UIKit

struct SSHServersView: View {
    @StateObject private var store = SSHConfigStore.shared
    @State private var searchText = ""
    @State private var showingAddServerSheet = false
    @State private var editingServer: SSHServerEntry?
    @State private var showingAddActionSheet = false
    @State private var showingGenerateKeySheet = false
    @State private var showingImportKeySheet = false
    @State private var viewingKey: SSHKeyEntry?
    @State private var deleteServerConfirm: SSHServerEntry?
    @State private var deleteKeyConfirm: SSHKeyEntry?
    @State private var deleteKnownHostConfirm: SSHKnownHostEntry?
    @State private var showingClearKnownHostsConfirm = false
    @State private var testResult: SSHTestResult?
    @State private var testingServer: SSHServerEntry?
    @State private var errorMessage: String?

    private var filteredServers: [SSHServerEntry] {
        if searchText.isEmpty {
            return store.servers
        }
        let query = searchText
        return store.servers.filter { (entry: SSHServerEntry) -> Bool in
            entry.alias.localizedCaseInsensitiveContains(query) ||
            entry.hostname.localizedCaseInsensitiveContains(query) ||
            (entry.note ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var sshSections: some View {
            if store.servers.isEmpty && store.keys.isEmpty && store.knownHosts.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No SSH Configuration")
                            .font(.headline)
                        Text("Add servers, generate SSH keys, or import existing keys to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            Section("Servers") {
                if filteredServers.isEmpty && !searchText.isEmpty {
                    Text("No servers match your search")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredServers) { server in
                        serverRow(server)
                    }
                    .onDelete { offsets in
                        let serversToDelete = offsets.map { filteredServers[$0] }
                        if let first = serversToDelete.first {
                            deleteServerConfirm = first
                        }
                    }
                }
            }

            Section("Keys") {
                if store.keys.isEmpty {
                    Text("No SSH keys")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.keys) { key in
                        keyRow(key)
                    }
                    .onDelete { offsets in
                        let keysToDelete = offsets.map { store.keys[$0] }
                        if let first = keysToDelete.first {
                            deleteKeyConfirm = first
                        }
                    }
                }
            }

            Section("Known Hosts") {
                if store.knownHosts.isEmpty {
                    Text("No known hosts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.knownHosts) { host in
                        knownHostRow(host)
                    }
                    .onDelete { offsets in
                        let hostsToDelete = offsets.map { store.knownHosts[$0] }
                        if let first = hostsToDelete.first {
                            deleteKnownHostConfirm = first
                        }
                    }

                    Button(role: .destructive) {
                        showingClearKnownHostsConfirm = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }

            Section("Diagnostics") {
                dependencyRow("SSH Client", available: store.deps.ssh)
                dependencyRow("SSH Keygen", available: store.deps.sshKeygen)
                dependencyRow("SSH Pass", available: store.deps.sshpass)

                if !store.deps.ssh || !store.deps.sshKeygen || !store.deps.sshpass {
                    Button {
                        UIPasteboard.general.string = "apk add openssh-client sshpass"
                    } label: {
                        Label("Copy Install Command", systemImage: "doc.on.clipboard")
                    }
                }
            }
    }

    var body: some View {
        applyDialogs(
        List {
            sshSections
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Filter servers")
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
        )
    }

    /// Type-check isolation: the 1 confirmationDialog + 5 sheets + 6 alerts
    /// chain made the compiler give up ("unable to type-check in reasonable
    /// time") while attached to body. Moved into its own generic function so
    /// each modifier resolves independently of the opaque body type.
    private func applyDialogs<V: View>(_ base: V) -> some View {
        base
        .confirmationDialog(
            "Add",
            isPresented: $showingAddActionSheet,
            titleVisibility: .hidden
        ) {
            Button("Add Server") {
                showingAddServerSheet = true
            }
            Button("Generate Key") {
                showingGenerateKeySheet = true
            }
            Button("Import Private Key") {
                showingImportKeySheet = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddServerSheet) {
            SSHServerFormSheet(mode: .add, keys: store.keys) { server, password in
                do {
                    try store.upsertServer(server)
                    if let password = password {
                        store.setPassword(password, alias: server.alias)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $editingServer) { server in
            SSHServerFormSheet(mode: .edit, server: server, keys: store.keys) { updated, password in
                do {
                    try store.removeServer(alias: server.alias)
                    try store.upsertServer(updated)
                    if let password = password {
                        store.setPassword(password, alias: updated.alias)
                    } else if updated.alias != server.alias {
                        store.deletePassword(alias: server.alias)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showingGenerateKeySheet) {
            SSHKeyGenerateSheet { name, type in
                do {
                    try store.generateKey(name: name, type: type)
                } catch {
                    errorMessage = error.localizedDescription
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
        .alert(
            AppLocalized("Test Result"),
            isPresented: Binding(
                get: { testResult != nil },
                set: { if !$0 { testResult = nil } }
            ),
            presenting: testResult
        ) { result in
            Button(AppLocalized("OK"), role: .cancel) {}
        } message: { result in
            Text(result.message)
        }
        .onAppear {
            store.reload()
        }
    }

    @ViewBuilder
    private func serverRow(_ server: SSHServerEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.alias)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text("\(server.user)@\(server.hostname):\(server.port)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let note = server.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if testingServer?.id == server.id {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    testConnection(server)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingServer = server
        }
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
            Text(host.keyType)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(host.fingerprint)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func dependencyRow(_ name: String, available: Bool) -> some View {
        HStack {
            Text(name)
                .font(.body)
            Spacer()
            if available {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func testConnection(_ server: SSHServerEntry) {
        testingServer = server
        let password = store.password(alias: server.alias)
        Task {
            let result = await store.testConnection(server, password: password)
            testingServer = nil
            testResult = result
        }
    }
}

// MARK: - Server Form Sheet

private struct SSHServerFormSheet: View {
    enum Mode { case add, edit }

    let mode: Mode
    var server: SSHServerEntry? = nil
    let keys: [SSHKeyEntry]
    let onSave: (SSHServerEntry, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var authMode = "key"
    @State private var identityFileName: String?
    @State private var password = ""
    @State private var note = ""
    @State private var showingGenerateKeySheet = false
    @State private var pushPassword = ""
    @State private var showingPushSheet = false
    @State private var pushResult: SSHTestResult?

    private var isValid: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty &&
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !user.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
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
                        Text("SSH Key").tag("key")
                        Text("Password").tag("password")
                    }

                    if authMode == "key" {
                        if keys.isEmpty {
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
                                ForEach(keys) { key in
                                    Text(key.name).tag(String?.some(key.name))
                                }
                            }

                            Button("Generate Key & Push") {
                                showingPushSheet = true
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

                if mode == .edit {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                        } label: {
                            Label("Delete Server", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(mode == .add ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .add ? "Add" : "Save") {
                        let entry = SSHServerEntry(
                            alias: alias.trimmingCharacters(in: .whitespaces),
                            hostname: hostname.trimmingCharacters(in: .whitespaces),
                            port: Int(port) ?? 22,
                            user: user.trimmingCharacters(in: .whitespaces),
                            identityFileName: identityFileName,
                            authMode: authMode,
                            note: note.isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        let pwd = authMode == "password" ? password : nil
                        onSave(entry, pwd)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingGenerateKeySheet) {
                SSHKeyGenerateSheet { name, type in
                    do {
                        try SSHConfigStore.shared.generateKey(name: name, type: type)
                        identityFileName = name
                    } catch {
                        // Error handled by parent
                    }
                }
            }
            .sheet(isPresented: $showingPushSheet) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("Server Password", text: $pushPassword)
                                .font(.system(.body, design: .monospaced))
                        } header: {
                            Text("Enter the server password to push your public key")
                        }

                        if let result = pushResult {
                            Section {
                                HStack {
                                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result.ok ? .green : .red)
                                    Text(result.message)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .navigationTitle("Push Public Key")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingPushSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Push") {
                                Task {
                                    guard let keyName = identityFileName ?? keys.first?.name else { return }
                                    let tempServer = SSHServerEntry(
                                        alias: alias.isEmpty ? "temp" : alias,
                                        hostname: hostname,
                                        port: Int(port) ?? 22,
                                        user: user,
                                        identityFileName: keyName,
                                        authMode: "key",
                                        note: nil
                                    )
                                    let result = await SSHConfigStore.shared.pushPublicKey(server: tempServer, password: pushPassword)
                                    pushResult = result
                                    if result.ok {
                                        identityFileName = keyName
                                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                                        showingPushSheet = false
                                    }
                                }
                            }
                            .disabled(pushPassword.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                if let server = server {
                    alias = server.alias
                    hostname = server.hostname
                    port = String(server.port)
                    user = server.user
                    authMode = server.authMode
                    identityFileName = server.identityFileName
                    note = server.note ?? ""
                }
            }
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
