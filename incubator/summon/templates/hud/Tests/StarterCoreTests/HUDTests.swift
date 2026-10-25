import CoreGraphics
import Foundation
import StarterCore
import Testing

@Suite struct StopwatchTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func keepsTimeAcrossPauses() {
        var watch = Stopwatch()
        #expect(watch.state == .idle)
        watch.start(at: start)
        #expect(watch.state == .running)
        #expect(watch.elapsed(at: start.addingTimeInterval(10)) == 10)
        watch.pause(at: start.addingTimeInterval(10))
        #expect(watch.state == .paused)
        #expect(watch.elapsed(at: start.addingTimeInterval(100)) == 10)
        watch.start(at: start.addingTimeInterval(100))
        #expect(watch.elapsed(at: start.addingTimeInterval(105)) == 15)
        watch.reset()
        #expect(watch.state == .idle)
        #expect(watch.elapsed(at: start) == 0)
    }

    @Test func toggleStartsAndPauses() {
        var watch = Stopwatch()
        watch.toggle(at: start)
        #expect(watch.state == .running)
        watch.toggle(at: start.addingTimeInterval(3))
        #expect(watch.state == .paused)
    }

    @Test func clockBackwardsNeverGoesNegative() {
        var watch = Stopwatch()
        watch.start(at: start)
        #expect(watch.elapsed(at: start.addingTimeInterval(-5)) == 0)
    }

    @Test func formatsWithoutHoursUnderAnHour() {
        #expect(Stopwatch.format(7) == "0:07")
        #expect(Stopwatch.format(754.9) == "12:34")
        #expect(Stopwatch.format(3723) == "1:02:03")
    }
}

@Suite struct CornerSnapTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let window = CGSize(width: 200, height: 60)

    @Test func restsInTheNearestCorner() {
        let nearTopRight = CGRect(x: 700, y: 600, width: 200, height: 60)
        #expect(CornerSnap.corner(for: nearTopRight, velocity: .zero, in: screen) == .topRight)
        let nearBottomLeft = CGRect(x: 50, y: 40, width: 200, height: 60)
        #expect(CornerSnap.corner(for: nearBottomLeft, velocity: .zero, in: screen) == .bottomLeft)
    }

    @Test func aThrowCarriesItAcross() {
        let leftSide = CGRect(x: 300, y: 600, width: 200, height: 60) // center x 400: left half
        #expect(CornerSnap.corner(for: leftSide, velocity: CGVector(dx: 1500, dy: 0), in: screen) == .topRight)
        #expect(CornerSnap.corner(for: leftSide, velocity: CGVector(dx: 0, dy: -3000), in: screen) == .bottomLeft)
    }

    @Test func framesSitInsideTheMargin() {
        #expect(CornerSnap.frame(of: window, in: .topLeft, of: screen) == CGRect(x: 16, y: 724, width: 200, height: 60))
        #expect(CornerSnap.frame(of: window, in: .bottomRight, of: screen) == CGRect(x: 784, y: 16, width: 200, height: 60))
    }

    @Test func worksOnASecondScreen() {
        let second = CGRect(x: 1000, y: -200, width: 800, height: 600)
        let frame = CornerSnap.frame(of: window, in: .bottomLeft, of: second)
        #expect(frame.origin == CGPoint(x: 1016, y: -184))
        #expect(CornerSnap.corner(for: frame, velocity: .zero, in: second) == .bottomLeft)
    }
}
