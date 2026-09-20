// V2PairingCommand.swift — AA 官方 Models/Chat/V2PairingCommand.swift 逐字搬运。
// 类型适配：V2ConnectorCreateResponse → facade 的 RemoteConnectorCreateResponse
// （字段同名 connector/connectorToken/tokenPrefix）。

import Foundation

enum V2PairingCommand {
    static func start(server: URL, credential: RemoteConnectorCreateResponse) -> String {
        "uvx anywhere-cli start --server-url \(quote(server.absoluteString)) --connector-id \(quote(credential.connector.id)) --connector-token \(quote(credential.connectorToken))"
    }
    static func pair(server: URL) -> String { "uvx anywhere-cli pair \(quote(server.absoluteString))" }
    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
}
