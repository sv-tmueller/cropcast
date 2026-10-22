/// Command-line options of `vdisplay-demo`.
public struct DemoOptions: Equatable, Sendable {
    /// How long each cycle keeps the display up.
    public var seconds: Int
    /// How many start/stop cycles to run in one process.
    public var cycles: Int

    public init(seconds: Int = 10, cycles: Int = 1) {
        self.seconds = seconds
        self.cycles = cycles
    }

    /// Parses `[--seconds N] [--cycles N]` (positive integers, each at most
    /// once, any order). Returns nil for anything else.
    public static func parse(_ args: [String]) -> DemoOptions? {
        var options = DemoOptions()
        var seen = Set<String>()
        var index = 0
        while index < args.count {
            let flag = args[index]
            guard flag == "--seconds" || flag == "--cycles", seen.insert(flag).inserted,
                index + 1 < args.count, let value = Int(args[index + 1]), value > 0
            else { return nil }
            if flag == "--seconds" { options.seconds = value } else { options.cycles = value }
            index += 2
        }
        return options
    }
}

/// Active display counts around one start/stop cycle.
public struct CycleResult: Equatable, Sendable {
    public var before: Int
    public var during: Int
    public var after: Int

    public init(before: Int, during: Int, after: Int) {
        self.before = before
        self.during = during
        self.after = after
    }

    /// True only for N -> N+1 -> N.
    public var isOK: Bool { during == before + 1 && after == before }
}
