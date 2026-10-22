// vdisplay-demo: creates the "CropCast" virtual display, logs the active display
// count before/during/after, and removes it. With --cycles N it does that N
// times in one process. Exit 0 only if every cycle went N -> N+1 -> N.
//
// Usage: vdisplay-demo [--seconds N] [--cycles N]   (defaults: 10 s, 1 cycle)

import AppKit
import CoreGraphics
import Dispatch
import Foundation
import VirtualDisplay
import VirtualDisplayDemoSupport

func log(_ message: String) {
    print("[vdisplay-demo] \(message)")
    fflush(stdout)
}

func usage() -> Never {
    FileHandle.standardError.write(
        Data("usage: vdisplay-demo [--seconds N] [--cycles N]   (N is a positive integer)\n".utf8))
    exit(2)
}

func describe(_ rect: CGRect) -> String {
    "origin=(\(Int(rect.origin.x)), \(Int(rect.origin.y))) size=\(Int(rect.width))x\(Int(rect.height))"
}

func activeDisplayCount() -> Int {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success else { return 0 }
    return Int(count)
}

func describeMode(of displayID: CGDirectDisplayID) -> String {
    guard let mode = CGDisplayCopyDisplayMode(displayID) else { return "unknown" }
    return "\(mode.pixelWidth)x\(mode.pixelHeight) px @ \(mode.refreshRate) Hz"
}

/// The display of the cycle in progress, so Ctrl-C can remove it.
enum Running {
    @MainActor static var display: VirtualDisplay?
}

/// Runs one start/stop cycle. Returns nil if the display could not be started.
@MainActor func runCycle(seconds: Int) async -> CycleResult? {
    let before = activeDisplayCount()
    log("active displays before: \(before)")

    let display: VirtualDisplay
    do {
        display = try await VirtualDisplay.start()
    } catch {
        log("failed to start virtual display: \(error)")
        return nil
    }
    Running.display = display

    let bounds = CGDisplayBounds(display.displayID)
    let main = CGDisplayBounds(CGMainDisplayID())
    log("displayID: \(display.displayID)")
    log("mode: \(describeMode(of: display.displayID)) (main display: \(describe(main)))")
    log("requested origin: (\(Int(display.requestedOrigin.x)), \(Int(display.requestedOrigin.y)))")
    log("actual bounds: \(describe(bounds))")
    let during = activeDisplayCount()
    log("active displays during: \(during)")
    log("running for \(seconds) s (Ctrl-C to stop early)")

    try? await Task.sleep(for: .seconds(seconds))

    display.stop()
    Running.display = nil
    log("stopped, waiting for the display to go away")
    var after = activeDisplayCount()
    let deadline = ContinuousClock.now + .seconds(5)
    while after != before && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(50))
        after = activeDisplayCount()
    }
    log("active displays after: \(after)")
    return CycleResult(before: before, during: during, after: after)
}

@MainActor func runDemo(_ options: DemoOptions) async -> Int32 {
    var failures = 0
    for cycle in 1...options.cycles {
        if options.cycles > 1 { log("cycle \(cycle)/\(options.cycles)") }
        if let result = await runCycle(seconds: options.seconds), result.isOK {
            log("OK: \(result.before) -> \(result.during) -> \(result.after)")
        } else {
            failures += 1
            log("FAIL: cycle \(cycle) did not go N -> N+1 -> N")
        }
    }
    if options.cycles > 1 { log("\(options.cycles - failures)/\(options.cycles) cycles passed") }
    return failures == 0 ? 0 : 1
}

guard let options = DemoOptions.parse(Array(CommandLine.arguments.dropFirst())) else { usage() }

// Ctrl-C removes the display before exiting.
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    MainActor.assumeIsolated {
        log("SIGINT: stopping")
        Running.display?.stop()
        exit(130)
    }
}
sigint.resume()

// The main thread must run the AppKit event loop, as the menu bar app does.
// With Swift's async main (top-level `await`) or a bare CFRunLoopRun(), this
// process's CoreGraphics display list stops updating after a display
// reconfiguration: the display is already gone system-wide, but
// CGGetActiveDisplayList in this process still lists it, and the next start()
// throws .didNotComeOnline. See the package README.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    exit(await runDemo(options))
}
app.run()
