// vdisplay-demo: creates the "CropCast" virtual display, logs the active display
// count before/during/after, and removes it. Exit 0 only if the count went
// N -> N+1 -> N.
//
// Usage: vdisplay-demo [--seconds N]   (default 10)

import CoreGraphics
import Dispatch
import Foundation
import VirtualDisplay

func log(_ message: String) {
    print("[vdisplay-demo] \(message)")
    fflush(stdout)
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: vdisplay-demo [--seconds N]   (N is a positive integer)\n".utf8))
    exit(2)
}

func parseSeconds(_ args: [String]) -> Int {
    switch args.count {
    case 0:
        return 10
    case 2 where args[0] == "--seconds":
        guard let n = Int(args[1]), n > 0 else { usage() }
        return n
    default:
        usage()
    }
}

func describe(_ rect: CGRect) -> String {
    "origin=(\(Int(rect.origin.x)), \(Int(rect.origin.y))) size=\(Int(rect.width))x\(Int(rect.height))"
}

let seconds = parseSeconds(Array(CommandLine.arguments.dropFirst()))
let before = VirtualDisplay.activeDisplayCount()
log("active displays before: \(before)")

let display: VirtualDisplay
do {
    display = try await VirtualDisplay.start()
} catch {
    log("failed to start virtual display: \(error)")
    exit(1)
}

// Ctrl-C removes the display before exiting.
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    MainActor.assumeIsolated {
        log("SIGINT: stopping")
        display.stop()
        exit(130)
    }
}
sigint.resume()

let bounds = CGDisplayBounds(display.displayID)
let main = CGDisplayBounds(CGMainDisplayID())
log("displayID: \(display.displayID)")
log("mode: \(Int(bounds.width))x\(Int(bounds.height)) (main display: \(describe(main)))")
log("requested origin: (\(Int(display.requestedOrigin.x)), \(Int(display.requestedOrigin.y)))")
log("actual bounds: \(describe(bounds))")
let during = VirtualDisplay.activeDisplayCount()
log("active displays during: \(during)")
log("running for \(seconds) s (Ctrl-C to stop early)")

try? await Task.sleep(for: .seconds(seconds))

display.stop()
log("stopped, waiting for the display to go away")
var after = VirtualDisplay.activeDisplayCount()
let deadline = ContinuousClock.now + .seconds(5)
while after != before && ContinuousClock.now < deadline {
    try? await Task.sleep(for: .milliseconds(100))
    after = VirtualDisplay.activeDisplayCount()
}
log("active displays after: \(after)")

if during == before + 1 && after == before {
    log("OK: \(before) -> \(during) -> \(after)")
    exit(0)
} else {
    log("FAIL: expected \(before) -> \(before + 1) -> \(before), got \(before) -> \(during) -> \(after)")
    exit(1)
}
