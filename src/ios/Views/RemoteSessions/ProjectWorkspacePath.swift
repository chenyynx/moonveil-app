// ProjectWorkspacePath.swift — AA 官方 Models/Chat/ProjectWorkspacePath.swift
// 逐字搬运（路径规范化 / 项目匹配 / 命名 / 父目录；remote 路径比较遵循服务端
// 语义，不按 iPhone 本地文件系统）。
//
// 唯一适配：文件末尾官方对 V2Project 的 ProjectReuseRequired 保持原样（本仓
// RemoteKit 内部类型同模块可见，无需改动）。

import Foundation

/// Remote path comparison follows the server, not the filesystem of this phone.
nonisolated enum ProjectWorkspacePath {
    static func project(in projects: [RemoteProject], connectorID: String, path: String, deviceOS: String?) -> RemoteProject? {
        guard let key = key(path, deviceOS: deviceOS) else { return nil }
        return projects.first { $0.connectorId == connectorID && self.key($0.workspacePath, deviceOS: deviceOS) == key }
    }

    static func name(_ path: String) -> String {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = value.range(of: "^[A-Za-z]:[/\\\\]", options: .regularExpression) != nil || value.hasPrefix("\\\\")
        let parts = (windows ? value.replacingOccurrences(of: "\\", with: "/") : value).split(separator: "/")
        if parts.isEmpty || (windows && (parts.count == 1 || (value.hasPrefix("\\\\") && parts.count == 2))) {
            return "Workspace"
        }
        return String(parts.last!)
    }

    // [CIFIX-DASHBOARD 2026-09-21] 官方 V2Project 重载：官方逐字冻结件
    // V2DashboardRepository:172 以 [V2Project] 调用（单模块解析需此签名）；
    // RemoteProject 版保留给 app 层 facade 调用方（RemoteNewSessionModel resolver）。
    // 逻辑与 RemoteProject 版逐字同构（官方原版逻辑，字段同构）。
    static func availableName(_ name: String, projects: [V2Project], ignoring id: String? = nil) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String((trimmed.isEmpty ? "Workspace" : trimmed).unicodeScalars.prefix(255))
        let names = Set(projects.filter { $0.id != id }.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    static func availableName(_ name: String, projects: [RemoteProject], ignoring id: String? = nil) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String((trimmed.isEmpty ? "Workspace" : trimmed).unicodeScalars.prefix(255))
        let names = Set(projects.filter { $0.id != id }.map(\.name))
        var candidate = base
        var suffix = 1
        while names.contains(candidate) {
            let ending = " (\(suffix))"
            candidate = String(base.unicodeScalars.prefix(255 - ending.count)) + ending
            suffix += 1
        }
        return candidate
    }

    static func parent(_ path: String) -> String? {
        guard let normalized = key(path, deviceOS: nil) else { return nil }
        let windows = normalized.range(of: "^[a-z]:/", options: .regularExpression) != nil || path.hasPrefix("\\\\")
        let slashes = windows ? path.replacingOccurrences(of: "\\", with: "/") : path
        var parts = slashes.split(separator: "/")
        if windows, parts.count == 1 { return "" } // Connector fs/list's Windows drive picker.
        if slashes.hasPrefix("//"), parts.count <= 2 { return nil }
        guard !parts.isEmpty else { return nil }
        parts.removeLast()
        if windows { return (slashes.hasPrefix("//") ? "//" : "") + parts.joined(separator: "/") + (parts.count == 1 ? "/" : "") }
        return (slashes.hasPrefix("//") ? "//" : "/") + parts.joined(separator: "/")
    }

    static func key(_ value: String, deviceOS: String?) -> String? {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let drive = path.range(of: "^[A-Za-z]:[/\\\\]", options: .regularExpression) != nil
        let windows = deviceOS == "windows" || drive || path.hasPrefix("\\\\")
        if windows {
            let normalized = path.replacingOccurrences(of: "\\", with: "/")
            guard drive || normalized.hasPrefix("//") else { return nil }
            let parts = normalized.split(separator: "/").filter { $0 != "." }
            if !drive && parts.count < 2 { return nil }
            var result = (drive ? "" : "//") + parts.joined(separator: "/")
            if drive && parts.count == 1 { result += "/" }
            // PureWindowsPath preserves '..'; resolving it here would disagree with the server.
            return result.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        guard path.hasPrefix("/") else { return nil }
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(part) }
        }
        return (path.hasPrefix("//") && !path.hasPrefix("///") ? "//" : "/") + parts.joined(separator: "/")
    }
}

struct ProjectReuseRequired: LocalizedError {
    // [CIFIX-DASHBOARD 2026-09-21] 字段类型回归官方原版 V2Project（官方
    // Models/Chat/ProjectWorkspacePath.swift:72）。FILES-HOME 批适配成 RemoteProject
    // 属过度适配——唯一 throw 点是官方逐字冻结件 V2DashboardRepository:168（传
    // V2Project），app 层无任何调用方。errorDescription 只消费 .name，两型同构。
    let project: V2Project
    var errorDescription: String? { String(localized: "这个目录已属于项目「\(project.name)」。") }
}
