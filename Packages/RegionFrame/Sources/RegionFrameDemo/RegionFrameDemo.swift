import AppKit
import CoreGraphics
import Foundation
import RegionFrame

/// Manual verification demo for the RegionFrame module.
///
/// Shows the frame overlay on a display, optionally applies a preset or cycles
/// through them, and prints every region change with 16:9 and containment checks.
/// It persists into its own defaults suite, never the app's.
@main
@MainActor
struct RegionFrameDemo {
    static let suiteName = "com.github.sv-tmueller.cropcast.regionframe-demo"

    struct Options {
        var list = false
        var display: CGDirectDisplayID?
        var preset: RegionPreset?
        var cyclePresets = false
        var seconds: Int?
        var reset = false
    }

    static let usage = """
        usage: regionframe-demo [--list] [--display <displayID|number>] [--preset left|center|right] \
        [--cycle-presets] [--seconds N] [--reset]
        """

    static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--list":
                options.list = true
            case "--display":
                guard let value = iterator.next().flatMap({ UInt32($0) }) else { return nil }
                options.display = value
            case "--preset":
                switch iterator.next() {
                case "left": options.preset = .left
                case "center": options.preset = .center
                case "right": options.preset = .right
                default: return nil
                }
            case "--cycle-presets":
                options.cyclePresets = true
            case "--seconds":
                guard let value = iterator.next().flatMap({ Int($0) }), value > 0 else { return nil }
                options.seconds = value
            case "--reset":
                options.reset = true
            default:
                return nil
            }
        }
        return options
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let options = parse(Array(CommandLine.arguments.dropFirst())) else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(2)
        }

        if options.list {
            list()
            exit(0)
        }

        // Never `.standard`: the demo must not touch the app's saved region.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            FileHandle.standardError.write(Data("cannot open defaults suite \(suiteName)\n".utf8))
            exit(1)
        }
        if options.reset {
            defaults.removePersistentDomain(forName: suiteName)
            print("reset: removed saved regions in suite \(suiteName)")
        }

        var displayID: CGDirectDisplayID?
        if let requested = options.display {
            guard let resolved = resolveDisplay(requested) else {
                FileHandle.standardError.write(Data("no connected display with id or number \(requested); see --list\n".utf8))
                exit(1)
            }
            displayID = resolved
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let overlay = FrameOverlay(defaults: defaults)
        overlay.regionDidChange = { report($0) }
        print("suite: \(suiteName)")
        print("windowNumbers: \(overlay.windowNumbers)")

        overlay.show(on: displayID)
        if let preset = options.preset {
            overlay.apply(preset: preset, on: displayID)
        }

        var timer: Timer?
        if options.cyclePresets {
            var index = 0
            let presets = RegionPreset.allCases
            overlay.apply(preset: presets[index], on: displayID)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    index = (index + 1) % presets.count
                    overlay.apply(preset: presets[index], on: displayID)
                }
            }
        }

        if let seconds = options.seconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
                MainActor.assumeIsolated {
                    timer?.invalidate()
                    overlay.hide()
                    defaults.synchronize()
                    print("done")
                    exit(0)
                }
            }
        } else {
            print("running until interrupted (Ctrl-C); drag the frame by hand")
        }
        app.run()
    }

    /// Accepts a `CGDirectDisplayID` or the 1-based display number printed by `--list`.
    static func resolveDisplay(_ value: UInt32) -> CGDirectDisplayID? {
        let ids = NSScreen.screens.compactMap {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        }
        if ids.contains(value) { return value }
        return ids.indices.contains(Int(value) - 1) ? ids[Int(value) - 1] : nil
    }

    static func list() {
        for (index, screen) in NSScreen.screens.enumerated() {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            print("display \(index + 1): id=\(id) frame=\(format(screen.frame)) visibleFrame=\(format(screen.visibleFrame)) scale=\(screen.backingScaleFactor)")
        }
    }

    static func report(_ region: FrameRegion) {
        let rect = region.rect
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID
        }
        let local = screen.map { rect.offsetBy(dx: -$0.frame.minX, dy: -$0.frame.minY) }
        let ratio = rect.width * 9 == rect.height * 16 ? "ok" : "FAIL"
        let inside = screen.map { $0.frame.contains(rect) } == true ? "ok" : "FAIL"
        print("display \(region.displayID) global=\(format(rect)) local=\(local.map(format) ?? "?") 16:9=\(ratio) inside=\(inside)")
    }

    static func format(_ rect: CGRect) -> String {
        func number(_ value: CGFloat) -> String { String(format: "%g", Double(value)) }
        return "(\(number(rect.minX)),\(number(rect.minY)),\(number(rect.width)),\(number(rect.height)))"
    }
}
