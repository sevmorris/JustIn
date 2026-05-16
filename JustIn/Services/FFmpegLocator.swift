import Foundation

/// Resolves `ffmpeg`/`ffprobe` once and caches the result. `static let` gives
/// thread-safe, run-once initialization. JustIn is non-sandboxed, so launching
/// these binaries via `Process` is permitted.
enum FFmpegLocator {
    static let ffmpegPath: String? = locate("ffmpeg")
    static let ffprobePath: String? = locate("ffprobe")

    static var isAvailable: Bool { ffmpegPath != nil }

    private static func locate(_ tool: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(tool)",
            "/usr/local/bin/\(tool)",
            "/opt/local/bin/\(tool)",
            "/usr/bin/\(tool)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let path = "\(dir)/\(tool)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }
}
