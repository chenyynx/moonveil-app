//
//  CustomConnectorForm.swift
//  MinisApp
//
//  Add-your-own connector form: name, HTTP server URL, custom headers
//  (key-value rows), and JSON import. Saves into MCPStore as a regular
//  server entry. Chrome matches ConnectorDetailSheet (tinted canvas,
//  36pt top radius, grabber, liquid-glass close).
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
        ZStack(alignment: .top) {
            Color(red: 0.961, green: 0.961, blue: 0.961)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        formCard {
                            fieldRow(
                                label: AppLocalized("Name"),
                                placeholder: AppLocalized("My MCP Server"),
                                text: $name
                            )
                            Divider().background(cardDivider)
                            fieldRow(
                                label: AppLocalized("Server URL"),
                                placeholder: AppLocalized("https://example.com/mcp"),
                                text: $url
                            )
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        }

                        formCard {
                            HStack {
                                Text(AppLocalized("Headers"))
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button(action: { headers.append(HeaderRow()) }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.bottom, 4)

                            if headers.isEmpty {
                                Text(AppLocalized("No custom headers."))
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.745, green: 0.745, blue: 0.753))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach($headers) { $row in
                                    HStack(spacing: 8) {
                                        TextField(AppLocalized("Key"), text: $row.key)
                                            .font(.system(size: 14))
                                            .autocapitalization(.none)
                                            .padding(10)
                                            .background(Color(red: 0.961, green: 0.961, blue: 0.961))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        TextField(AppLocalized("Value"), text: $row.value)
                                            .font(.system(size: 14))
                                            .autocapitalization(.none)
                                            .padding(10)
                                            .background(Color(red: 0.961, green: 0.961, blue: 0.961))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        Button(action: { headers.removeAll { $0.id == row.id } }) {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(Color(red: 0.9, green: 0.25, blue: 0.25))
                                        }
                                    }
                                }
                            }
                        }

                        formCard {
                            Button(action: { showJSON.toggle() }) {
                                HStack {
                                    Text(AppLocalized("Import from JSON"))
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Image(systemName: showJSON ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.62))
                                }
                            }

                            if showJSON {
                                TextEditor(text: $jsonText)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .background(Color(red: 0.961, green: 0.961, blue: 0.961))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .autocapitalization(.none)

                                Button(action: importJSON) {
                                    Text(AppLocalized("Import"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.black)
                                        .clipShape(Capsule())
                                }
                                .padding(.top, 6)
                            }
                        }

                        Button(action: save) {
                            Text(AppLocalized("Save"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(canSave ? .white : Color(red: 0.6, green: 0.6, blue: 0.62))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(canSave ? Color.black : Color(red: 0.92, green: 0.92, blue: 0.93))
                                .clipShape(Capsule())
                        }
                        .disabled(!canSave)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.fraction(0.92)])
        .presentationCornerRadius(36)
        .presentationBackground(Color(red: 0.961, green: 0.961, blue: 0.961))
        .presentationDragIndicator(.hidden)
        .alert(AppLocalized("Couldn't Save"), isPresented: $showError) {
            Button(AppLocalized("OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack(alignment: .top) {
            Color(red: 0.729, green: 0.729, blue: 0.729)
                .frame(height: 47)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(red: 0.49, green: 0.49, blue: 0.498))
                .frame(width: 35, height: 5)
                .padding(.top, 8)

            HStack {
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.tint(.white.opacity(0.55)).interactive(), in: Circle())
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.leading, 16)

                Spacer()

                Text(AppLocalized("Custom Connector"))
                    .font(.system(size: 15, weight: .bold))
                    .padding(.trailing, 60) // optically recenter against the close button
            }
            .padding(.top, 1)
        }
        .frame(height: 47)
    }

    private var cardDivider: Color {
        Color(red: 0.78, green: 0.78, blue: 0.79)
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.494, green: 0.49, blue: 0.51))
            TextField(placeholder, text: text)
                .font(.system(size: 15))
        }
        .padding(.vertical, 4)
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
