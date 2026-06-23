import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Thin wrapper over Apple's on-device language model (the Foundation Models
/// framework). Its job is to answer one question cheaply — "can we run this
/// generation locally, for free, right now?" — and to run it when the answer is
/// yes. When it isn't (macOS below 26, ineligible hardware, Apple Intelligence
/// switched off, or the model still downloading), callers fall back to the cloud
/// provider.
///
/// OpenFish targets macOS 14, so the framework is compiled out on SDKs that lack
/// it (`#if canImport`) and every live entry point is runtime-gated with
/// `if #available(macOS 26, *)`. Safe to call from anywhere on any supported OS.
///
/// This is OpenFish's own seam — not tied to any earlier project's plumbing.
enum OnDeviceModel {

    /// Whether the on-device model can be used, and if not, why — for logging,
    /// fallback decisions, and (optionally) telling the user how to enable it.
    enum Status: Equatable, CustomStringConvertible {
        case available
        case unsupportedOS          // running below macOS 26
        case deviceNotEligible      // hardware without Apple Intelligence
        case intelligenceNotEnabled // user hasn't turned Apple Intelligence on
        case modelNotReady          // eligible + enabled, still downloading
        case frameworkMissing       // built against an SDK without FoundationModels

        var isAvailable: Bool { self == .available }

        var description: String {
            switch self {
            case .available: return "available"
            case .unsupportedOS: return "unavailable (needs macOS 26+)"
            case .deviceNotEligible: return "unavailable (device not eligible)"
            case .intelligenceNotEnabled: return "unavailable (Apple Intelligence off)"
            case .modelNotReady: return "unavailable (model downloading)"
            case .frameworkMissing: return "unavailable (framework not in SDK)"
            }
        }
    }

    /// Current runtime availability. Cheap, synchronous, safe on every OS.
    static var status: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .intelligenceNotEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .deviceNotEligible
                }
            @unknown default:
                return .deviceNotEligible
            }
        } else {
            return .unsupportedOS
        }
        #else
        return .frameworkMissing
        #endif
    }

    static var isAvailable: Bool { status.isAvailable }

    /// Thrown when the on-device model can't be used — the caller's signal to fall
    /// back to the cloud provider.
    enum GenerationError: Error { case unavailable(Status) }

    /// Run a single-shot prompt on the on-device model. Throws
    /// `GenerationError.unavailable` if the model isn't usable. `instructions`, if
    /// given, are system-style guidance; we fold them into the prompt so the call
    /// stays on the API surface verified to exist on this SDK. (Can move to native
    /// `Instructions` once a real consumer needs the separation.)
    static func respond(to prompt: String, instructions: String? = nil) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard isAvailable else { throw GenerationError.unavailable(status) }
            let composed = instructions.map { "\($0)\n\n\(prompt)" } ?? prompt
            let session = LanguageModelSession()
            let response = try await session.respond(to: composed)
            return response.content
        } else {
            throw GenerationError.unavailable(.unsupportedOS)
        }
        #else
        throw GenerationError.unavailable(.frameworkMissing)
        #endif
    }

    /// Ergonomic fallback seam: returns the on-device result, or nil when the model
    /// isn't available so the caller can route to the cloud:
    ///
    ///     let text = await OnDeviceModel.respondIfAvailable(to: prompt)
    ///               ?? cloudProvider.generate(prompt)
    static func respondIfAvailable(to prompt: String, instructions: String? = nil) async -> String? {
        do {
            return try await respond(to: prompt, instructions: instructions)
        } catch {
            Log.debug("on-device model unavailable, falling back: \(error)")
            return nil
        }
    }
}
