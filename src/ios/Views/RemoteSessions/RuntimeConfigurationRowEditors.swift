// RuntimeConfigurationRowEditors.swift — AA 官方逐字搬运（P2-B，2026-09-21）
//
// 官方源：Views/Devices/RuntimeConfigurationRowEditors.swift（v2.0.0-27-g1bc11f45）。
// 合法差异（铁律①类2·文案落地）：String(localized:) → xcstrings zh-Hans 显示值。
// 依赖：RuntimeConfigurationModel.swift / RuntimeConfigurationRows.swift（AAV2 冻结件）。

import SwiftUI

struct RuntimeEnvironmentRowEditor: View {
    @Bindable var row: RuntimeEnvironmentRow
    let onRemove: () -> Void
    @FocusState private var focusedField: RuntimeConfigurationInput?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("变量名", text: $row.key)
                        .runtimeConfigInput().focused($focusedField, equals: .identifier)
                    TextField("值", text: $row.value)
                        .runtimeConfigInput().focused($focusedField, equals: .value).disabled(row.removesInherited)
                }
                Menu {
                    Toggle("移除继承的变量", isOn: $row.removesInherited)
                    Button("删除环境变量", systemImage: "trash", role: .destructive) {
                        focusedField = nil
                        onRemove()
                    }
                } label: { AppSymbol("ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("变量操作")
            }
        }
        .padding(.vertical, 8)
    }
}

struct RuntimeCustomModelRowEditor: View {
    @Bindable var row: RuntimeCustomModelRow
    let onRemove: () -> Void
    @FocusState private var focusedField: RuntimeConfigurationInput?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("模型").font(.subheadline.weight(.medium))
                Spacer()
                Button("删除自定义模型", appSymbol: "trash", role: .destructive) {
                    focusedField = nil
                    onRemove()
                }.buttonStyle(.borderless).labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            TextField("模型 ID", text: $row.modelID)
                .runtimeConfigInput().focused($focusedField, equals: .identifier)
            TextField("展示名称", text: $row.displayName)
                .runtimeConfigInput().focused($focusedField, equals: .value)
            HStack {
                Text("推理强度").font(.subheadline.weight(.medium))
                Spacer()
                Button("添加强度", appSymbol: "plus") {
                    row.efforts.append(.init())
                }.buttonStyle(.borderless).labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            if row.efforts.isEmpty {
                Text("未设置推理强度。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(row.efforts) { effort in
                Divider()
                RuntimeEffortRowEditor(row: effort) { row.removeEffort(effort.id) }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct RuntimeEffortRowEditor: View {
    @Bindable var row: RuntimeEffortRow
    let onRemove: () -> Void
    @FocusState private var focusedField: RuntimeConfigurationInput?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("强度 ID", text: $row.effortID)
                    .runtimeConfigInput().focused($focusedField, equals: .identifier)
                TextField("强度名称", text: $row.displayName)
                    .runtimeConfigInput().focused($focusedField, equals: .value)
            }
            Button("删除推理强度", appSymbol: "trash", role: .destructive) {
                focusedField = nil
                onRemove()
            }.buttonStyle(.borderless).labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
    }
}

private enum RuntimeConfigurationInput: Hashable { case identifier, value }
