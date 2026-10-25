import StarterCore
import Testing

@Suite struct CounterTests {
    @Test func startsAtZeroAndCounts() {
        var counter = Counter()
        #expect(counter.label == "0 clicks")
        counter.increment()
        #expect(counter.label == "1 click")
        counter.increment()
        #expect(counter.value == 2)
        counter.reset()
        #expect(counter.value == 0)
    }

    @Test func negativeStartIsClampedToZero() {
        #expect(Counter(value: -3).value == 0)
    }
}
