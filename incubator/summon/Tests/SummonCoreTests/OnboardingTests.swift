import SummonCore
import Testing

@Suite struct OnboardingTests {
    @Test func threeStepsForwardToTheEndAndBack() {
        var flow = OnboardingFlow()
        #expect(flow.steps == [.agent, .accessibility, .ready])
        #expect(flow.isFirst && flow.step == .agent)
        var moved = flow.next()
        #expect(moved && flow.step == .accessibility)
        moved = flow.next()
        #expect(moved && flow.isLast && flow.step == .ready)
        moved = flow.next()
        #expect(!moved && flow.step == .ready)
        flow.back()
        flow.back()
        flow.back()
        #expect(flow.step == .agent)
    }

    @Test func showsOnlyOnAFirstLaunchThatNeedsSetup() {
        #expect(OnboardingFlow.launch(completed: false, visualQA: false, hasDefaultAgent: false, accessibilityGranted: false) == .show)
        #expect(OnboardingFlow.launch(completed: false, visualQA: false, hasDefaultAgent: true, accessibilityGranted: false) == .show)
        #expect(OnboardingFlow.launch(completed: false, visualQA: false, hasDefaultAgent: false, accessibilityGranted: true) == .show)
        #expect(OnboardingFlow.launch(completed: false, visualQA: false, hasDefaultAgent: true, accessibilityGranted: true) == .markCompleted)
        #expect(OnboardingFlow.launch(completed: true, visualQA: false, hasDefaultAgent: false, accessibilityGranted: false) == .none)
        #expect(OnboardingFlow.launch(completed: false, visualQA: true, hasDefaultAgent: false, accessibilityGranted: false) == .none)
    }
}
