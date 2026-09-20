// WorkspaceFileExportPicker.swift — AA 官方 Views/Devices/WorkspaceFileExportPicker.swift 逐字搬运（P1-CHAT 批，远端线聊天页强依赖）。
//
// 合法差异字据（铁律①④）：
// - 零 API 差异：全文逐字（UIDocumentPickerViewController / UIActivityViewController）。
//
import SwiftUI
import UIKit

struct WorkspaceFileExportPicker: UIViewControllerRepresentable {
    let file: WorkspaceDownloadedFile
    let onFinish: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file.url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (String?) -> Void
        init(onFinish: @escaping (String?) -> Void) { self.onFinish = onFinish }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(nil) }
    }
}

struct WorkspaceFileActivitySheet: UIViewControllerRepresentable {
    let file: WorkspaceDownloadedFile
    let onFinish: (String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in onFinish(error?.localizedDescription) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
