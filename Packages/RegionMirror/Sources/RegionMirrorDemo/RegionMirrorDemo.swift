import AppKit
import CoreGraphics
import Foundation
import RegionMirror

/// Manual verification demo for the RegionMirror module.
///
/// Mirrors a 16:9 region of a display into a window (or full-screen on another
/// display with `--target`), moving the region every 2 seconds.
@main
@MainActor
struct RegionMirrorDemo {
    struct Options {
        var target: CGDirectDisplayID?
        var source: CGDirectDisplayID = CGMainDisplayID()
        var seconds: Int?
        var requestPermission = false
    }

    static let usage = """
        usage: regionmirror-demo [--target <displayID>] [--source <displayID>] \
        [--seconds N] [--request-permission]
        """

    static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--target":
                guard let value = iterator.next().flatMap({ UInt32($0) }) else { return nil }
                options.target = value
            case "--source":
                guard let value = iterator.next().flatMap({ UInt32($0) }) else { return nil }
                options.source = value
            case "--seconds":
                guard let value = iterator.next().flatMap({ Int($0) }), value > 0 else { return nil }
                options.seconds = value
            case "--request-permission":
                options.requestPermission = true
            default:
                return nil
            }
        }
        return options
    }

    static func main() {
        guard let options = parse(Array(CommandLine.arguments.dropFirst())) else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(2)
        }

        // Permission is only requested on explicit opt-in, never in automated runs.
        if options.requestPermission {
            _ = CGRequestScreenCaptureAccess()
        }
        guard CGPreflightScreenCaptureAccess() else {
            let names = [
                "Apple_Terminal": "Terminal", "iTerm.app": "iTerm", "vscode": "Visual Studio Code",
            ]
            let program = ProcessInfo.processInfo.environment["TERM_PROGRAM"]
            let terminal = program.map { names[$0] ?? $0 } ?? "your terminal app"
            FileHandle.standardError.write(
                Data(
                    """
                    Screen Recording permission is not granted.
                    Grant it to \(terminal) in System Settings > Privacy & Security > Screen & System \
                    Audio Recording, then restart \(terminal) and run this demo again.
                    (Use --request-permission to trigger the system prompt.)

                    """.utf8))
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in await run(options: options) }
        app.run()
    }

    static func run(options: Options) async {
        guard let sourceFrame = frame(ofDisplay: options.source) else {
            fail("Source display \(options.source) not found.")
        }

        // Output: full-screen MirrorWindow on --target, else a titled window on the main display.
        let renderer: MirrorView
        var mirrorWindow: MirrorWindow?
        var titledWindow: NSWindow?
        if let target = options.target {
            do {
                let window = try MirrorWindow(targetDisplayID: target)
                mirrorWindow = window
                renderer = window.view
                window.show()
            } catch {
                fail("\(error.localizedDescription)")
            }
        } else {
            let view = MirrorView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
            let window = NSWindow(
                contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "RegionMirror demo"
            window.contentView = view
            window.isReleasedWhenClosed = false
            if let main = frame(ofDisplay: CGMainDisplayID()) {
                // Overlaps the region at its first position, so a mirror-in-mirror
                // image would show up there if the app were not excluded.
                window.setFrameOrigin(
                    NSPoint(x: main.minX + 20, y: main.midY - window.frame.height / 2))
            }
            window.orderFrontRegardless()
            titledWindow = window
            renderer = view
        }

        let positions = regionPositions(in: sourceFrame)
        let capture = RegionCapture(sourceDisplayID: options.source)
        capture.onStop = { error in
            print("stream stopped: \(error.localizedDescription)")
            exit(1)
        }

        do {
            try await capture.start(region: positions[0], renderer: renderer.videoRenderer)
        } catch {
            fail("start failed: \(error.localizedDescription)")
        }
        print("capturing display \(options.source), region \(positions[0])")

        var latencies: [String] = []
        var lastFrames = 0
        var tick = 0
        var index = 0
        var direction = 1
        let clock = ContinuousClock()
        while options.seconds.map({ tick < $0 }) ?? true {
            try? await Task.sleep(for: .seconds(1))
            tick += 1
            if tick % 2 == 0 {
                if index + direction < 0 || index + direction >= positions.count { direction = -direction }
                index += direction
                let start = clock.now
                do {
                    try await capture.updateRegion(positions[index])
                    let elapsed = start.duration(to: clock.now)
                    latencies.append(String(format: "%.1f ms", elapsed.milliseconds))
                } catch {
                    latencies.append("failed: \(error.localizedDescription)")
                }
            }
            let frames = capture.deliveredFrameCount
            print("t=\(tick)s frames=\(frames) (+\(frames - lastFrames)) updates=\(latencies)")
            lastFrames = frames
            latencies.removeAll()
        }

        await capture.stop()
        mirrorWindow?.close()
        titledWindow?.close()
        print("done")
        exit(0)
    }

    /// Region positions: 16:9, half the display width, vertically centred, moving
    /// sideways in steps of 25% of the display width without leaving the display.
    static func regionPositions(in display: CGRect) -> [CGRect] {
        let width = display.width / 2
        let height = width * 9 / 16
        let y = display.midY - height / 2
        return [0.0, 0.25, 0.5].map { fraction in
            CGRect(x: display.minX + display.width * fraction, y: y, width: width, height: height)
        }
    }

    static func frame(ofDisplay id: CGDirectDisplayID) -> CGRect? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == id
        }?.frame
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

extension Duration {
    fileprivate var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
