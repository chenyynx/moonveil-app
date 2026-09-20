// SessionFileReferenceLinks.swift — §0f 渲染桥接的「file:行号 可点化」预处理件。
//
// 官方机制（Views/Chat/Markdown/ChatMarkdownView.swift:44-52）：官方用 Textual
// 渲染 markdown，解析阶段遍历 AttributedString.runs，把「是 inline code、且能被
// `SessionFileReference.inlineReference(_:)` 识别为文件引用」的 run 直接挂上
// `.link = reference.link`（aa-workspace-file://preview?path=…&line=…），点击由
// `SessionChatView` 的 `.environment(\.openURL)` 拦截 → `sheet = .preview`。
//
// 本仓 §0f：正文 markdown 走 Moonveil `SelectableMarkdownView`（自研解析器，
// 不跑官方那条 run 遍历）。等价做法 = 在「送进解析器之前」把命中的 inline code
// 文本重写成 markdown 链接语法 `` [`Foo.swift:42`](aa-workspace-file://…) ``：
//   • SelectableMarkdownView 的 `.link` 节点会递归渲染子节点 → code 节点
//     （等宽字体 + 灰底 pill）保留，只是多了 .link 属性 → 可点（见该件
//     `case .link` / `case .code` 的渲染分支）。
//   • 点击走 SessionChatView 已注入的 `.environment(\.openURL)` 拦截器
//     （`SessionFileReference.reference(from:)` 识别 aa-workspace-file scheme）。
//   • 判定规则一律委托冻结件 `SessionFileReference.inlineReference(_:)`，
//     与官方逐字同源，不自造规则。
//
// 只处理行内反引号 code span，不碰代码块（``` … ```）——官方 run 遍历也只覆盖
// inlinePresentationIntent == .code 的内联 run，代码块不在其列。

import Foundation

enum SessionFileReferenceLinks {
    /// 把 markdown 源文本里的「文件引用型 inline code」重写成可点链接。
    /// 无命中时返回原字符串（不分配新串以外的开销）。
    static func rewrite(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return markdown }
        var output = ""
        output.reserveCapacity(markdown.count)
        var index = markdown.startIndex
        while index < markdown.endIndex {
            let ch = markdown[index]
            if ch == "`" {
                // 找配对的反引号（不跨行；跨行说明是代码块围栏或畸形输入，放弃）
                let start = markdown.index(after: index)
                guard let end = markdown[start...].firstIndex(of: "`"),
                      !markdown[start..<end].contains(where: { $0.isNewline }) else {
                    output.append(ch); index = markdown.index(after: index); continue
                }
                let code = String(markdown[start..<end])
                // 委托冻结件判定：与官方 ChatMarkdownView 同一函数
                if let reference = SessionFileReference.inlineReference(code),
                   let link = reference.link {
                    let encoded = link.absoluteString
                    // 反引号在 URL 片段里不合法 → 不可能出现在 code 里（inlineReference
                    // 已排除含 :// 与换行），percent-encode 兜底
                    let safeCode = code.replacingOccurrences(of: "`", with: "%60")
                    output.append("[`\(safeCode)`](\(encoded))")
                } else {
                    output.append("`\(code)`")
                }
                index = markdown.index(after: end)
            } else {
                output.append(ch); index = markdown.index(after: index)
            }
        }
        return output == markdown ? markdown : output
    }
}
