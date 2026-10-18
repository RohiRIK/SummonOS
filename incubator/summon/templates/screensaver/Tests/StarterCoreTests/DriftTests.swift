import StarterCore
import Testing

@Suite struct DriftTests {
    @Test func sameSeedSameDots() {
        #expect(Drift(count: 5, width: 100, height: 50, seed: 7) == Drift(count: 5, width: 100, height: 50, seed: 7))
        #expect(Drift(count: 5, width: 100, height: 50, seed: 7) != Drift(count: 5, width: 100, height: 50, seed: 8))
    }

    @Test func dotsStayInsideForever() {
        var drift = Drift(count: 20, width: 300, height: 200)
        for _ in 0..<2_000 {
            drift.step(seconds: 1.0 / 30)
        }
        for dot in drift.dots {
            #expect((0...300).contains(dot.x) && (0...200).contains(dot.y))
        }
    }

    @Test func resizeClampsToTheNewSize() {
        var drift = Drift(count: 20, width: 1_000, height: 1_000)
        drift.resize(width: 50, height: 40)
        #expect(drift.dots.allSatisfy { $0.x <= 50 && $0.y <= 40 })
    }
}
