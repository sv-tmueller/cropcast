import Foundation

/// Pure logic for resetting CropCast's stale Screen Recording grant with
/// `tccutil`. Nothing here runs a process; the app target does that.
public enum ScreenCaptureReset {
    public static let executablePath = "/usr/bin/tccutil"

    public enum Failure: Error, Equatable, LocalizedError {
        case missingBundleID
        case invalidBundleID(String)
        case launchFailed(String, bundleID: String?)
        case exited(status: Int32, output: String, bundleID: String?)

        public var errorDescription: String? {
            switch self {
            case .missingBundleID:
                return "CropCast has no bundle identifier (it is probably running unbundled, "
                    + "outside CropCast.app).\n\n" + ScreenCaptureReset.fallback(bundleID: nil)
            case .invalidBundleID(let id):
                return "The bundle identifier \"\(id)\" is not valid.\n\n"
                    + ScreenCaptureReset.fallback(bundleID: nil)
            case .launchFailed(let message, let id):
                return "tccutil could not be started: \(message)\n\n"
                    + ScreenCaptureReset.fallback(bundleID: id)
            case .exited(let status, let output, let id):
                let detail = output.isEmpty ? "no output" : output
                return "tccutil exited with status \(status): \(detail)\n\n"
                    + ScreenCaptureReset.fallback(bundleID: id)
            }
        }
    }

    /// The exact `tccutil` arguments, or a failure. An empty id must never become
    /// the two-argument reset of the whole service, and a leading `-` would be
    /// read as an option.
    public static func arguments(bundleID: String?) throws -> [String] {
        guard let bundleID, !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw Failure.missingBundleID }
        guard isValid(bundleID) else { throw Failure.invalidBundleID(bundleID) }
        return ["reset", "ScreenCapture", bundleID]
    }

    /// Success for exit status 0, otherwise `Failure.exited` with tccutil's trimmed output.
    public static func check(exitStatus: Int32, output: String, bundleID: String?) throws {
        guard exitStatus == 0 else {
            throw Failure.exited(
                status: exitStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                bundleID: bundleID)
        }
    }

    static func fallback(bundleID: String?) -> String {
        "To reset it by hand, run in Terminal:\n    tccutil reset ScreenCapture "
            + (bundleID ?? "<bundle identifier>")
    }

    private static func isValid(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, first != "-", first != "." else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
                || ("0"..."9").contains(scalar) || scalar == "." || scalar == "-"
        }
    }
}
