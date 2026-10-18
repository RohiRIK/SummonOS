/// The saver's one piece of logic: dots drifting inside a rectangle and bouncing off its edges.
/// Replace it with your saver's animation; no drawing here, so it stays tested in StarterCoreTests.
public struct Drift: Equatable, Sendable {
    public struct Dot: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var dx: Double
        public var dy: Double
    }

    public private(set) var dots: [Dot]
    public private(set) var width: Double
    public private(set) var height: Double

    /// Same seed, same dots: previews and tests are repeatable.
    public init(count: Int, width: Double, height: Double, seed: UInt64 = 1) {
        self.width = max(1, width)
        self.height = max(1, height)
        var random = SplitMix64(seed: seed)
        dots = (0..<max(0, count)).map { _ in
            Dot(x: random.unit() * max(1, width), y: random.unit() * max(1, height),
                dx: (random.unit() - 0.5) * 120, dy: (random.unit() - 0.5) * 120)
        }
    }

    /// Moves every dot by its speed (points per second) and bounces it off the edges.
    public mutating func step(seconds: Double) {
        for index in dots.indices {
            var dot = dots[index]
            dot.x += dot.dx * seconds
            dot.y += dot.dy * seconds
            if dot.x < 0 || dot.x > width {
                dot.dx = -dot.dx
                dot.x = min(max(dot.x, 0), width)
            }
            if dot.y < 0 || dot.y > height {
                dot.dy = -dot.dy
                dot.y = min(max(dot.y, 0), height)
            }
            dots[index] = dot
        }
    }

    /// Keeps every dot inside a new size (the preview pane and the screen differ).
    public mutating func resize(width: Double, height: Double) {
        self.width = max(1, width)
        self.height = max(1, height)
        for index in dots.indices {
            dots[index].x = min(dots[index].x, self.width)
            dots[index].y = min(dots[index].y, self.height)
        }
    }
}

/// A tiny seeded generator, so the animation is the same on every run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
