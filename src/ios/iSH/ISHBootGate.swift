//
//  ISHBootGate.swift
//  MinisApp
//
//  Single shared, thread-safe entry point for booting the iSH kernel.
//  Mirrors the boot sequence previously inlined in
//  AIChatViewModel.ensureKernelBooted().
//
//  SSH settings flows use this so a guest command is never executed before
//  the kernel is up. Previously that failed synchronously with
//  "kernel not booted — refusing to execute /bin/sh" and (before the
//  continuation fix) leaked the Swift continuation, hanging the Settings
//  UI on the add-server spinner forever.
//

import Foundation

private let ishBootQueue = DispatchQueue(label: "com.minisapp.ish.boot")
private let ishBootLogger = AppLogger(category: "ISHBoot")

/// Boot the iSH kernel if it isn't already booted.
///
/// Safe to call from any thread and from concurrent tasks: callers serialize
/// on a private queue, and losers re-check `isBooted` after the winner
/// finishes, returning immediately.
///
/// Synchronous, and slow on first boot (rootfs install + kernel init), so
/// callers must hop off the main thread before calling.
enum ISHBootGate {
    static func ensureBooted() throws {
        if ISHKernel.shared.isBooted { return }
        try ishBootQueue.sync {
            if ISHKernel.shared.isBooted { return }

            let installStart = CFAbsoluteTimeGetCurrent()
            try RootfsManager.shared.installIfNeeded()
            let installElapsed = (CFAbsoluteTimeGetCurrent() - installStart) * 1000
            ishBootLogger.info("[Boot] installIfNeeded: \(String(format: "%.1f", installElapsed))ms")

            let kernelStart = CFAbsoluteTimeGetCurrent()
            let rootPath = RootfsManager.shared.rootfsPath.path
            let err = ISHKernel.shared.boot(withRootPath: rootPath)
            let kernelElapsed = (CFAbsoluteTimeGetCurrent() - kernelStart) * 1000
            ishBootLogger.info("[Boot] kernel boot call: \(String(format: "%.1f", kernelElapsed))ms")
            guard err >= 0 else {
                throw ISHBootError.bootFailed(code: Int(err))
            }

            // Wire fakefs change events into the iCloud Sync v2
            // SessionFile dirty pipeline. Must be done after boot
            // (the C-side dispatch source is created by this call)
            // and before any bind mount, so the first realfs op
            // already has a consumer registered.
            installSessionFileChangeTracker(kernel: ISHKernel.shared)

            // Install per-session path-translate hook. Must run
            // before any session task is spawned so the first
            // /var/minis/* access already routes correctly.
            MinisFsRouter.shared.installHook()

            RootfsManager.shared.applyDefaultMountOverlay()
        }
    }
}

enum ISHBootError: LocalizedError {
    case bootFailed(code: Int)

    var errorDescription: String? {
        switch self {
        case .bootFailed(let code):
            return AppLocalized("iSH kernel failed to start (code \(code))")
        }
    }
}
