import Testing

@testable import VirtualDisplay

/// These tests inject class names so no real virtual display is ever created.
@MainActor
struct ShimFailureTests {
    private func expectApiUnavailable(_ names: ShimClassNames) async {
        do {
            _ = try await VirtualDisplay.start(classNames: names)
            Issue.record("start() unexpectedly succeeded")
        } catch {
            guard case .apiUnavailable = error else {
                Issue.record("expected .apiUnavailable, got \(error)")
                return
            }
        }
    }

    @Test func missingClassesThrowApiUnavailable() async {
        await expectApiUnavailable(
            ShimClassNames(
                display: "CGVirtualDisplayDoesNotExist",
                descriptor: "CGVirtualDisplayDescriptor",
                mode: "CGVirtualDisplayMode",
                settings: "CGVirtualDisplaySettings"))
    }

    @Test func displayClassWithWrongShapeThrowsApiUnavailable() async {
        await expectApiUnavailable(
            ShimClassNames(
                display: "NSObject",
                descriptor: "CGVirtualDisplayDescriptor",
                mode: "CGVirtualDisplayMode",
                settings: "CGVirtualDisplaySettings"))
    }

    @Test func descriptorClassWithWrongShapeThrowsApiUnavailable() async {
        // Display class exists (so the shape check on it passes) but the
        // descriptor class lacks the setters, so nothing is ever created.
        await expectApiUnavailable(
            ShimClassNames(
                display: "CGVirtualDisplay",
                descriptor: "NSObject",
                mode: "CGVirtualDisplayMode",
                settings: "CGVirtualDisplaySettings"))
    }

    @Test func errorsCarryAMessage() async {
        do {
            _ = try await VirtualDisplay.start(
                classNames: ShimClassNames(
                    display: "Nope", descriptor: "Nope", mode: "Nope", settings: "Nope"))
            Issue.record("start() unexpectedly succeeded")
        } catch {
            guard case .apiUnavailable(let message) = error else {
                Issue.record("expected .apiUnavailable, got \(error)")
                return
            }
            #expect(!message.isEmpty)
        }
    }
}
