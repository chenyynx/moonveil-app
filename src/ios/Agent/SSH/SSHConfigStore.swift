//
//  SSHConfigStore.swift
//  MinisApp
//
//  Data layer for SSH server management.
//  Single source of truth: iSH rootfs /root/.ssh/ directory.
//

import Foundation
import SwiftUI

// MARK: - Data Models

struct SSHServerEntry: Identifiable, Codable, Equatable, Sendable {
    var id: String { alias }
    var alias: String
    var hostname: String
    var port: Int
    var user: String
    var identityFileName: String?
    var authMode: String
    var note: String?
}

struct SSHKeyEntry: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var keyType: String
    var hasPrivate: Bool
    var hasPublicKey: Bool
    var comment: String?
}

struct SSHKnownHostEntry: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var host: String
    var keyType: String
    var fingerprint: String
}

struct SSHTestResult: Sendable {
    var ok: Bool
    var message: String
    var elapsedMs: Int
}

struct SSHDependencyStatus: Sendable {
    var ssh: Bool
    var sshKeygen: Bool
    var sshpass: Bool
}

// MARK: - Error Type

enum SSHStoreError: LocalizedError {
    case missingDependency(String)
    case keyInUse(aliases: [String])
    case keyNotFound
    case keyNameInvalid
    case keyAlreadyExists
    case keyContentInvalid
    case configParseFailed(String)
    case operationFailed(String)

    // §9 localization iron rule: these surface in user-facing alerts via
    // `localizedDescription`, so route them through AppLocalized (key = the
    // English source with %@ placeholders from LocalizationValue interpolation).
    var errorDescription: String? {
        switch self {
        case .missingDependency(let dep):
            return AppLocalized("Missing dependency: \(dep)")
        case .keyInUse(let aliases):
            return AppLocalized("Key is referenced by: \(aliases.joined(separator: ", "))")
        case .keyNotFound:
            return AppLocalized("Key not found")
        case .keyNameInvalid:
            return AppLocalized("Invalid key name")
        case .keyAlreadyExists:
            return AppLocalized("Key with this name already exists")
        case .keyContentInvalid:
            return AppLocalized("Content does not appear to be a private key")
        case .configParseFailed(let msg):
            return AppLocalized("Config parse error: \(msg)")
        case .operationFailed(let msg):
            return AppLocalized("Operation failed: \(msg)")
        }
    }
}

// MARK: - Internal Config Parsing Types

private struct ServerConfigBlock: Sendable {
    var note: String?
    var alias: String
    var knownDirectives: [(String, String)]
    var unknownLines: [String]

    func value(for key: String) -> String? {
        knownDirectives.first { $0.0.lowercased() == key.lowercased() }?.1
    }
}

// MARK: - SSHConfigStore

@MainActor
final class SSHConfigStore: ObservableObject {
    static let shared = SSHConfigStore()

    @Published private(set) var servers: [SSHServerEntry] = []
    @Published private(set) var keys: [SSHKeyEntry] = []
    @Published private(set) var knownHosts: [SSHKnownHostEntry] = []
    @Published private(set) var deps = SSHDependencyStatus(ssh: false, sshKeygen: false, sshpass: false)

    private let keychainService = "moonveil.ssh"

    // MARK: - Paths

    private var sshDirHostURL: URL {
        RootfsManager.shared.dataPath.appendingPathComponent("root/.ssh")
    }

    private var configHostURL: URL {
        sshDirHostURL.appendingPathComponent("config")
    }

    private var knownHostsHostURL: URL {
        sshDirHostURL.appendingPathComponent("known_hosts")
    }

    private let sshDirLinuxPath = "/root/.ssh"
    private let configLinuxPath = "/root/.ssh/config"
    private let knownHostsLinuxPath = "/root/.ssh/known_hosts"

    // MARK: - Reload

    func reload() {
        servers = Self.parseServers(from: configHostURL)
        keys = Self.scanKeys(in: sshDirHostURL)
        knownHosts = Self.parseKnownHosts(from: knownHostsHostURL)
        deps = Self.checkDependencies()
    }

    // MARK: - Server Management

    func upsertServer(_ entry: SSHServerEntry) throws {
        do {
            // [review] Input sanitize — a newline (or stray whitespace) in any
            // field would break the config block structure: alias lands on the
            // `Host` line, hostname/user on their directive lines, note in a
            // `# note:` comment. Single-line everything before serializing.
            var clean = entry
            func oneLine(_ s: String) -> String {
                s.replacingOccurrences(of: "\r", with: "")
                 .replacingOccurrences(of: "\n", with: " ")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            clean.alias = oneLine(entry.alias)
            clean.hostname = oneLine(entry.hostname)
            clean.user = oneLine(entry.user)
            clean.identityFileName = entry.identityFileName.map(oneLine)
            clean.note = entry.note.map(oneLine)
            guard !clean.alias.isEmpty, !clean.hostname.isEmpty else {
                throw SSHStoreError.keyNameInvalid
            }
            ensureSSHDirExists()
            var blocks = Self.parseConfigBlocks(from: configHostURL)
            blocks = Self.upsertBlock(for: clean, in: blocks)
            try writeConfigFile(blocks)
            reload()
        } catch let e as SSHStoreError {
            throw e
        } catch {
            throw SSHStoreError.operationFailed(error.localizedDescription)
        }
    }

    func removeServer(alias: String) throws {
        do {
            var blocks = Self.parseConfigBlocks(from: configHostURL)
            blocks.removeAll { $0.alias == alias }
            try writeConfigFile(blocks)
            reload()
        } catch let e as SSHStoreError {
            throw e
        } catch {
            throw SSHStoreError.operationFailed(error.localizedDescription)
        }
    }

    // MARK: - Key Management

    func generateKey(name: String, type: String) throws {
        guard deps.sshKeygen else {
            throw SSHStoreError.missingDependency("ssh-keygen")
        }
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else {
            throw SSHStoreError.keyNameInvalid
        }
        let linuxKeyPath = "\(sshDirLinuxPath)/\(name)"

        ensureSSHDirExists()

        if FileManager.default.fileExists(atPath: sshDirHostURL.appendingPathComponent(name).path) {
            throw SSHStoreError.keyAlreadyExists
        }

        let rmCmd = "rm -f \(linuxKeyPath) \(linuxKeyPath).pub"
        let genCmd = "ssh-keygen -t \(type) -f \(linuxKeyPath) -N \"\" -C \(name)"
        let script = "\(rmCmd); \(genCmd)"

        let result = runShellSync(script)
        guard result.exitCode == 0 else {
            throw SSHStoreError.operationFailed("ssh-keygen: \(result.errorOutput)")
        }

        RootfsManager.shared.ensureFakefsMetadata(
            for: linuxKeyPath, isDirectory: false,
            mode: 0o100600)
        RootfsManager.shared.ensureFakefsMetadata(
            for: "\(linuxKeyPath).pub", isDirectory: false,
            mode: 0o100644)

        reload()
    }

    func importPrivateKey(name: String, content: String) throws {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else {
            throw SSHStoreError.keyNameInvalid
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-----BEGIN") || trimmed.hasPrefix("-----OPENSSH") else {
            throw SSHStoreError.keyContentInvalid
        }

        ensureSSHDirExists()

        let hostURL = sshDirHostURL.appendingPathComponent(name)
        try content.write(to: hostURL, atomically: true, encoding: .utf8)

        RootfsManager.shared.ensureFakefsMetadata(
            for: "\(sshDirLinuxPath)/\(name)", isDirectory: false,
            mode: 0o100600)

        reload()
    }

    func publicKey(name: String) -> String? {
        let url = sshDirHostURL.appendingPathComponent("\(name).pub")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func exportPrivateKey(name: String) -> Data? {
        let url = sshDirHostURL.appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }

    func deleteKey(name: String) throws {
        let referencing = servers.filter { $0.identityFileName == name }.map(\.alias)
        if !referencing.isEmpty {
            throw SSHStoreError.keyInUse(aliases: referencing)
        }

        let linuxPriv = "\(sshDirLinuxPath)/\(name)"
        let linuxPub = "\(linuxPriv).pub"
        let hostPriv = sshDirHostURL.appendingPathComponent(name)
        let hostPub = sshDirHostURL.appendingPathComponent("\(name).pub")

        if hostPriv.exists {
            try? FileManager.default.removeItem(at: hostPriv)
            RootfsManager.shared.removeFakefsPath(linuxPriv)
        }
        if hostPub.exists {
            try? FileManager.default.removeItem(at: hostPub)
            RootfsManager.shared.removeFakefsPath(linuxPub)
        }

        reload()
    }

    // MARK: - Known Hosts

    func removeKnownHost(id: String) throws {
        do {
            var entries = Self.parseKnownHosts(from: knownHostsHostURL)
            entries.removeAll { $0.id == id }
            try writeKnownHosts(entries)
            reload()
        } catch {
            throw SSHStoreError.operationFailed(error.localizedDescription)
        }
    }

    func clearKnownHosts() throws {
        let url = knownHostsHostURL
        if url.exists {
            try? FileManager.default.removeItem(at: url)
            RootfsManager.shared.removeFakefsPath(knownHostsLinuxPath)
        }
        reload()
    }

    // MARK: - Password (Keychain)

    func setPassword(_ password: String, alias: String) {
        Self.keychainStore(password, alias: alias, service: keychainService)
    }

    func password(alias: String) -> String? {
        Self.keychainLoad(alias: alias, service: keychainService)
    }

    func deletePassword(alias: String) {
        Self.keychainDelete(alias: alias, service: keychainService)
    }

    // MARK: - Operations

    func pushPublicKey(server: SSHServerEntry, password: String) async -> SSHTestResult {
        guard deps.sshpass else {
            return SSHTestResult(
                ok: false,
                message: AppLocalized("Missing sshpass. Run: apk add sshpass"),
                elapsedMs: 0)
        }
        guard let pubKey = publicKey(name: server.identityFileName ?? "id_ed25519") else {
            return SSHTestResult(
                ok: false, message: AppLocalized("No public key found"), elapsedMs: 0)
        }
        let pubKeyTrimmed = pubKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = server.port
        let cmd = [
            "sshpass -e ssh",
            "-o StrictHostKeyChecking=no",
            "-o Port=\(port)",
            "\(server.user)@\(server.hostname)",
            "\"mkdir -p ~/.ssh && chmod 700 ~/.ssh &&",
            "echo '\(pubKeyTrimmed)' >> ~/.ssh/authorized_keys &&",
            "chmod 600 ~/.ssh/authorized_keys\""
        ].joined(separator: " ")

        let start = Date()
        let result = await executeSSHCommand(cmd, env: ["SSHPASS": password])
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        if result.exitCode == 0 {
            return SSHTestResult(ok: true, message: AppLocalized("Public key pushed successfully"), elapsedMs: elapsed)
        }
        return SSHTestResult(ok: false, message: result.combinedOutput, elapsedMs: elapsed)
    }

    func testConnection(_ entry: SSHServerEntry, password: String?) async -> SSHTestResult {
        let cmd: String
        let env: [String: String]

        if entry.authMode == "password", let pw = password {
            let hostStr = entry.port == 22
                ? "\(entry.user)@\(entry.hostname)"
                : "\(entry.user)@\(entry.hostname) -p \(entry.port)"
            cmd = "sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \(hostStr) echo ok"
            env = ["SSHPASS": pw]
        } else {
            cmd = "ssh -o BatchMode=yes -o ConnectTimeout=5 \(entry.alias) echo ok"
            env = [:]
        }

        let start = Date()
        let result = await executeSSHCommand(cmd, env: env)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        if result.exitCode == 0 {
            return SSHTestResult(ok: true, message: "ok", elapsedMs: elapsed)
        }
        return SSHTestResult(ok: false, message: result.combinedOutput, elapsedMs: elapsed)
    }

    // MARK: - Prompt Injection

    nonisolated static func systemPromptSnippet() -> String? {
        let configURL = RootfsManager.shared.dataPath
            .appendingPathComponent("root/.ssh/config")
        let servers = parseServers(from: configURL)
        guard !servers.isEmpty else { return nil }

        var lines: [String] = []
        lines.append(
            "SSH servers (manage in Settings → SSH Servers; "
            + "configs live in /root/.ssh/config, connect via `ssh <alias>`):")
        for s in servers {
            var line = "- \(s.alias) — \(s.user)@\(s.hostname)"
            if s.port != 22 { line += ":\(s.port)" }
            if let note = s.note, !note.isEmpty {
                line += " · \(note)"
            }
            if s.authMode == "password" {
                line += " — auth: password — agent cannot connect (interactive only), user connects manually"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Config Parsing (Private)

    private static func parseServers(from url: URL) -> [SSHServerEntry] {
        parseConfigBlocks(from: url).compactMap { block -> SSHServerEntry? in
            let hostname = block.value(for: "hostname") ?? ""
            guard !hostname.isEmpty else { return nil }
            return SSHServerEntry(
                alias: block.alias,
                hostname: hostname,
                port: Int(block.value(for: "port") ?? "") ?? 22,
                user: block.value(for: "user") ?? "",
                identityFileName: block.value(for: "identityfile").map {
                    ($0 as NSString).lastPathComponent
                },
                authMode: block.value(for: "identityfile") != nil ? "key" : "password",
                note: block.note
            )
        }
    }

    private static func parseConfigBlocks(from url: URL) -> [ServerConfigBlock] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let allLines = content.components(separatedBy: "\n")
        var blocks: [ServerConfigBlock] = []
        var globalLines: [String] = []
        var i = 0

        while i < allLines.count {
            let line = allLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                globalLines.append(line)
                i += 1
                continue
            }

            let parts = trimmed.split(maxTokens: 1) { $0.isWhitespace }
            if parts.count == 2, parts[0].lowercased() == "host" {
                let alias = String(parts[1]).trimmingCharacters(in: .whitespaces)
                var directives: [(String, String)] = []
                var unknown: [String] = []
                i += 1

                while i < allLines.count {
                    let dLine = allLines[i]
                    let dTrimmed = dLine.trimmingCharacters(in: .whitespaces)
                    if dTrimmed.isEmpty {
                        i += 1
                        continue
                    }
                    let dParts = dTrimmed.split(maxTokens: 1) { $0.isWhitespace }
                    if dParts.count == 2, dParts[0].lowercased() == "host" {
                        break
                    }
                    if dParts.count == 2 {
                        let key = String(dParts[0])
                        let val = String(dParts[1]).trimmingCharacters(in: .whitespaces)
                        let kl = key.lowercased()
                        if kl == "hostname" || kl == "port" || kl == "user"
                            || kl == "identityfile"
                        {
                            directives.append((key, val))
                        } else {
                            unknown.append(dLine)
                        }
                    } else {
                        unknown.append(dLine)
                    }
                    i += 1
                }

                let note = findNoteForHost(alias, in: globalLines, previousBlocks: blocks)
                blocks.append(ServerConfigBlock(
                    note: note, alias: alias,
                    knownDirectives: directives, unknownLines: unknown))
            } else {
                globalLines.append(line)
                i += 1
            }
        }
        return blocks
    }

    private static func findNoteForHost(
        _ alias: String, in globalLines: [String],
        previousBlocks: [ServerConfigBlock]
    ) -> String? {
        var searchLines = globalLines
        if let lastBlock = previousBlocks.last {
            let blockStart = "Host \(lastBlock.alias)"
            if let idx = searchLines.lastIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == blockStart
            }) {
                searchLines = Array(searchLines[..<idx])
            }
        }
        for j in stride(from: searchLines.count - 1, through: 0, by: -1) {
            let l = searchLines[j].trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("# note:") {
                return String(l.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            if !l.isEmpty, !l.hasPrefix("#") {
                break
            }
        }
        return nil
    }

    // MARK: - Config Serialization (Private)

    private static func serializeConfig(_ blocks: [ServerConfigBlock]) -> String {
        var lines: [String] = []
        for block in blocks {
            if let note = block.note, !note.isEmpty {
                lines.append("# note: \(note)")
            }
            lines.append("Host \(block.alias)")
            for (key, value) in block.knownDirectives {
                lines.append("    \(key) \(value)")
            }
            for unknown in block.unknownLines {
                lines.append(unknown)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func upsertBlock(
        for entry: SSHServerEntry, in blocks: [ServerConfigBlock]
    ) -> [ServerConfigBlock] {
        let existingUnknown = blocks.first { $0.alias == entry.alias }?.unknownLines ?? []
        var result = blocks.filter { $0.alias != entry.alias }
        var directives: [(String, String)] = []
        directives.append(("HostName", entry.hostname))
        directives.append(("Port", String(entry.port)))
        directives.append(("User", entry.user))
        if let idFile = entry.identityFileName {
            directives.append(("IdentityFile", "~/.ssh/\(idFile)"))
        }
        result.append(ServerConfigBlock(
            note: entry.note, alias: entry.alias,
            knownDirectives: directives, unknownLines: existingUnknown))
        return result
    }

    // MARK: - Keychain (Private)

    private static func keychainStore(
        _ secret: String, alias: String, service: String
    ) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: alias,
        ]
        SecItemDelete(query as CFDictionary)
        guard !secret.isEmpty else { return }
        query[kSecValueData as String] = Data(secret.utf8)
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[SSHConfigStore] keychain write failed for '\(alias)': \(status)")
        }
    }

    private static func keychainLoad(alias: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: alias,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(alias: String, service: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: alias,
        ] as CFDictionary)
    }

    // MARK: - Shell Execution (Private)

    private struct ShellResult {
        var exitCode: Int
        var combinedOutput: String
        var errorOutput: String
    }

    private func executeSSHCommand(
        _ command: String, env: [String: String] = [:]
    ) async -> ShellResult {
        let scriptContent =
            "cd /root\n({ exec 0</dev/null; } 2>/dev/null || true; \(command)\n)\n"
        let stdinData = scriptContent.data(using: .utf8)

        return await withCheckedContinuation { continuation in
            ISHShellExecutor.executeExecutable(
                "/bin/sh",
                arguments: nil,
                environment: env.isEmpty ? nil : env,
                stdinData: stdinData,
                fsContext: 0,
                lineCallback: nil,
                completion: { result in
                    var output = result.output
                    let errOutput = result.errorOutput
                    if !errOutput.isEmpty {
                        output += output.isEmpty ? "" : "\n"
                        output += errOutput
                    }
                    if result.exitCode != 0 && !output.contains("exit code") {
                        output += "\n(exit code: \(result.exitCode))"
                    }
                    if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        output = "(command completed with no output)"
                    }
                    continuation.resume(returning: ShellResult(
                        exitCode: result.exitCode,
                        combinedOutput: output,
                        errorOutput: errOutput))
                }
            )
        }
    }

    private func runShellSync(_ command: String) -> ShellResult {
        let result = ISHShellExecutor.executeCommandSync(
            command, timeout: 30, lineCallback: nil)
        var output = result.output ?? ""
        let errOutput = result.errorOutput ?? ""
        if !errOutput.isEmpty {
            output += output.isEmpty ? "" : "\n"
            output += errOutput
        }
        return ShellResult(
            exitCode: Int(result.exitCode),
            combinedOutput: output,
            errorOutput: errOutput)
    }

    // MARK: - Helpers (Private)

    private func ensureSSHDirExists() {
        let dirURL = sshDirHostURL
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try? FileManager.default.createDirectory(
                at: dirURL, withIntermediateDirectories: true)
        }
        RootfsManager.shared.ensureParentDirsInMetaDB(for: sshDirLinuxPath)
        RootfsManager.shared.ensureFakefsMetadata(
            for: sshDirLinuxPath, isDirectory: true, mode: 0o040700)
    }

    private static func checkDependencies() -> SSHDependencyStatus {
        func has(_ cmd: String) -> Bool {
            let r = ISHShellExecutor.executeCommandSync(
                "which \(cmd)", timeout: 5, lineCallback: nil)
            return r.exitCode == 0
        }
        return SSHDependencyStatus(
            ssh: has("ssh"),
            sshKeygen: has("ssh-keygen"),
            sshpass: has("sshpass"))
    }

    private static func scanKeys(in dirURL: URL) -> [SSHKeyEntry] {
        guard FileManager.default.fileExists(atPath: dirURL.path) else {
            return []
        }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            atPath: dirURL.path) else { return [] }

        var keyNames = Set<String>()
        for item in items {
            if item.hasSuffix(".pub") {
                keyNames.insert(String(item.dropLast(4)))
            } else if !item.hasSuffix(".pub")
                && item != "config" && item != "known_hosts"
                && !item.hasPrefix(".")
            {
                let privURL = dirURL.appendingPathComponent(item)
                var isDir = ObjCBool(false)
                if fm.fileExists(atPath: privURL.path, isDirectory: &isDir),
                   !isDir.boolValue
                {
                    keyNames.insert(item)
                }
            }
        }

        return keyNames.sorted().compactMap { name -> SSHKeyEntry? in
            let privURL = dirURL.appendingPathComponent(name)
            let pubURL = dirURL.appendingPathComponent("\(name).pub")
            let hasPriv = fm.fileExists(atPath: privURL.path)
            let hasPub = fm.fileExists(atPath: pubURL.path)
            guard hasPriv || hasPub else { return nil }

            var keyType = "unknown"
            var comment: String?
            if hasPub, let pubContent = try? String(
                contentsOf: pubURL, encoding: .utf8)
            {
                let trimmed = pubContent.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let prefix = String(parts[0])
                    if prefix.hasPrefix("ssh-ed25519") {
                        keyType = "ed25519"
                    } else if prefix.hasPrefix("ssh-rsa") {
                        keyType = "rsa"
                    } else if prefix.hasPrefix("ecdsa-sha2-") {
                        keyType = "ecdsa"
                    }
                    if parts.count >= 3 {
                        comment = String(parts[2])
                    }
                }
            } else if hasPriv {
                if let privContent = try? String(
                    contentsOf: privURL, encoding: .utf8)
                {
                    if privContent.contains("OPENSSH PRIVATE KEY") {
                        keyType = "ed25519"
                    } else if privContent.contains("RSA PRIVATE KEY") {
                        keyType = "rsa"
                    } else if privContent.contains("EC PRIVATE KEY") {
                        keyType = "ecdsa"
                    }
                }
            }

            return SSHKeyEntry(
                name: name, keyType: keyType, hasPrivate: hasPriv,
                hasPublicKey: hasPub, comment: comment)
        }
    }

    private static func parseKnownHosts(from url: URL) -> [SSHKnownHostEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let lines = content.components(separatedBy: "\n")
        var entries: [SSHKnownHostEntry] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: " ")
            if parts.count >= 3 {
                let host = String(parts[0])
                let keyType = String(parts[1])
                let fingerprint = String(parts[2])
                entries.append(SSHKnownHostEntry(
                    id: String(idx),
                    host: host.hasPrefix("|") ? "(hashed)" : host,
                    keyType: keyType,
                    fingerprint: fingerprint))
            }
        }
        return entries
    }

    private func writeKnownHosts(_ entries: [SSHKnownHostEntry]) throws {
        let lines = entries.map { "\($0.host) \($0.keyType) \($0.fingerprint)" }
        let content = lines.joined(separator: "\n") + "\n"
        let url = knownHostsHostURL
        try content.write(to: url, atomically: true, encoding: .utf8)
        RootfsManager.shared.ensureFakefsMetadata(
            for: knownHostsLinuxPath, isDirectory: false, mode: 0o100600)
    }

    private func writeConfigFile(_ blocks: [ServerConfigBlock]) throws {
        let content = Self.serializeConfig(blocks)
        let url = configHostURL
        ensureSSHDirExists()
        try content.write(to: url, atomically: true, encoding: .utf8)
        RootfsManager.shared.ensureFakefsMetadata(
            for: configLinuxPath, isDirectory: false, mode: 0o100600)
    }
}

// MARK: - URL Existence Helper

private extension URL {
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
