//
//  CustomConnectorForm.swift
//  MinisApp
//
//  Add-your-own connector form: name, HTTP server URL, custom headers
//  (key-value rows), and JSON import. Saves into MCPStore as a regular
//  server entry.
//
//  Redesigned as a native grouped Form: system section chrome, standard
//  labeled field rows, swipe-to-delete headers with a blue add row, a
//  DisclosureGroup for JSON import, and the module's black capsule Save
//  (matches ConnectorDetailSheet's CTA language). Sheet chrome is fully
//  system — inline nav title, plain close key, system grabber; no custom
//  header band.
//

import SwiftUI

struct CustomConnectorForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var headers: [HeaderRow] = []
    @State private var jsonText: String = ""
    @State private var showJSON: Bool = false

    @State private var errorMessage: String?
    @State private var showError: Bool = false

    private struct HeaderRow: Identifiable, Hashable {
        let id = UUID()
        var key: String = ""
        var value: String = ""
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    labeledField(
                        AppLocalized("Name"),
                        AppLocalized("My MCP Server"),
                        text: $name
                    )
                    labeledField(
                        AppLocalized("Server URL"),
                        AppLocalized("https://example.com/mcp"),
                        text: $url
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                Section {
                    ForEach($headers) { $row in
                        HStack(spacing: 12) {
                            TextField(AppLocalized("Key"), text: $row.key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Divider()
                                .frame(height: 20)
                            TextField(AppLocalized("Value"), text: $row.value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .onDelete { headers.remove(atOffsets: $0) }

                    Button {
                        headers.append(HeaderRow())
                    } label: {
                        Label(AppLocalized("Add Header"), systemImage: "plus")
                    }
                } header: {
                    Text(AppLocalized("Headers"))
                } footer: {
                    Text(headers.isEmpty
                         ? AppLocalized("No custom headers.")
                         : AppLocalized("Swipe to delete"))
                }

                Section {
                    DisclosureGroup(isExpanded: $showJSON) {
                        TextEditor(text: $jsonText)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 100)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(AppLocalized("Import")) {
                            importJSON()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    } label: {
                        Text(AppLocalized("Import from JSON"))
                    }
                }

                Section {
                    Button(action: save) {
                        Text(AppLocalized("Save"))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .foregroundStyle(canSave ? Color.white : Color(red: 0.6, green: 0.6, blue: 0.62))
                    .background(
                        canSave ? Color.black : Color(red: 0.92, green: 0.92, blue: 0.93),
                        in: Capsule()
                    )
                    .disabled(!canSave)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppLocalized("Custom Connector"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.92), .large])
        .presentationCornerRadius(36)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .presentationDragIndicator(.visible)
        .alert(AppLocalized("Couldn't Save"), isPresented: $showError) {
            Button(AppLocalized("OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Rows

    /// Apple-settings style row: fixed secondary label + filling text field.
    private func labeledField(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: text)
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }

        var headerDict: [String: String] = [:]
        for row in headers {
            let k = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { continue }
            headerDict[k] = row.value
        }

        var cfg = MCPServerConfig(id: trimmedName, enabled: true)
        cfg.url = trimmedURL
        if !headerDict.isEmpty { cfg.headers = headerDict }
        store.add(cfg)
        dismiss()
    }

    private func importJSON() {
        do {
            let imported = try store.importJSON(jsonText)
            // Prefill the form with the first imported server for review.
            if let first = imported.first {
                name = first.id
                url = first.url ?? ""
                headers = (first.headers ?? [:]).map { HeaderRow(key: $0.key, value: $0.value) }
                jsonText = ""
                showJSON = false
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
