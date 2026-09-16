import CoreText
import Foundation
import UIKit

@MainActor
enum AppFontRegistry {
    private static var registered = false

    /// Registers the bundled brand font with Core Text for the current process.
    static func registerBundledFonts() {
        guard !registered else { return }
        guard let fontURL = Bundle.main.url(
            forResource: "caveat_wght",
            withExtension: "ttf"
        ) else {
            preconditionFailure("Bundled Caveat font is missing")
        }

        var registrationError: Unmanaged<CFError>?
        let registrationSucceeded = CTFontManagerRegisterFontsForURL(
            fontURL as CFURL,
            .process,
            &registrationError
        )
        if !registrationSucceeded {
            let error = registrationError?.takeRetainedValue() as Error? as NSError?
            let fontWasAlreadyRegistered = error?.domain == kCTFontManagerErrorDomain as String
                && error?.code == CTFontManagerError.alreadyRegistered.rawValue
            guard fontWasAlreadyRegistered else {
                let description = error?.localizedDescription ?? "Unknown Core Text error"
                preconditionFailure("Unable to register bundled Caveat font: \(description)")
            }
        }
        registered = true
    }

    // MARK: [B16-CODE-FONT] Geist Mono Medium — code-block face

    /// nonisolated(unsafe): CTFontManagerRegisterFontsForURL is thread-safe and
    /// this lazy one-shot is guarded by the flag itself. Kept OUTSIDE the
    /// @MainActor surface above so TextKit render paths (nonisolated) can fetch
    /// the code face without an actor hop — the verbatim Caveat surface above
    /// is untouched.
    private nonisolated(unsafe) static var geistRegistered = false

    /// [B16-CODE-FONT] 2026-09-17: the code-block face pp picked over SF Mono
    /// in the A/B preview (Claude-style). Soft-fails with a log — the renderer
    /// falls back to Menlo when the bundled face is unavailable, so a packaging
    /// slip must not crash the chat. Caveat above stays fail-fast (verbatim
    /// upstream behavior, brand-critical).
    nonisolated static func geistMonoMedium(_ size: CGFloat) -> UIFont? {
        if !geistRegistered {
            geistRegistered = true
            if let fontURL = Bundle.main.url(forResource: "geistmono_medium", withExtension: "ttf") {
                var registrationError: Unmanaged<CFError>?
                let succeeded = CTFontManagerRegisterFontsForURL(
                    fontURL as CFURL,
                    .process,
                    &registrationError
                )
                if !succeeded {
                    let error = registrationError?.takeRetainedValue() as Error? as NSError?
                    let alreadyRegistered = error?.domain == kCTFontManagerErrorDomain as String
                        && error?.code == CTFontManagerError.alreadyRegistered.rawValue
                    if !alreadyRegistered {
                        AppLogger(category: "AppFontRegistry").error(
                            "[B16-CODE-FONT] Geist Mono registration failed: \(error?.localizedDescription ?? "Unknown Core Text error") — code blocks fall back to Menlo"
                        )
                    }
                }
            } else {
                AppLogger(category: "AppFontRegistry").error(
                    "[B16-CODE-FONT] Bundled geistmono_medium.ttf missing — code blocks fall back to Menlo"
                )
            }
        }
        return UIFont(name: "GeistMono-Medium", size: size)
    }
}
