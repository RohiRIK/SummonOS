import StarterCore
import Testing

@Suite struct OnboardingFlowTests {
    @Test func permissionsStepOnlyWhenNeeded() {
        #expect(OnboardingFlow(needsPermissions: false).steps == [.welcome, .ready])
        #expect(OnboardingFlow(needsPermissions: true).steps == [.welcome, .permissions, .ready])
    }

    @Test func goesForwardToTheEndAndBackToTheStart() {
        var flow = OnboardingFlow(needsPermissions: true)
        #expect(flow.isFirst && flow.step == .welcome)
        var moved = flow.next()
        #expect(moved && flow.step == .permissions)
        moved = flow.next()
        #expect(moved && flow.isLast && flow.step == .ready)
        moved = flow.next()
        #expect(!moved && flow.step == .ready)
        flow.back()
        flow.back()
        flow.back()
        #expect(flow.step == .welcome)
    }
}
