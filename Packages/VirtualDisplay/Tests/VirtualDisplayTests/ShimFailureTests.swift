import CoreGraphics
import Foundation
import Testing

@testable import VirtualDisplay

/// A descriptor look-alike with every setter the shim sends except
/// `setWhitePoint:`. It is only ever probed with `respondsToSelector:`, never
/// instantiated, so no display is created.
@objc(CropCastTestDescriptorWithoutWhitePoint)
final class DescriptorWithoutWhitePoint: NSObject {
    @objc func setName(_: String?) {}
    @objc func setVendorID(_: UInt32) {}
    @objc func setProductID(_: UInt32) {}
    @objc func setSerialNum(_: UInt32) {}
    @objc func setMaxPixelsWide(_: UInt32) {}
    @objc func setMaxPixelsHigh(_: UInt32) {}
    @objc func setSizeInMillimeters(_: CGSize) {}
    @objc func setRedPrimary(_: CGPoint) {}
    @objc func setGreenPrimary(_: CGPoint) {}
    @objc func setBluePrimary(_: CGPoint) {}
    @objc func setQueue(_: DispatchQueue?) {}
}

/// These tests inject class names so no real virtual display is ever created.
@MainActor
struct ShimFailureTests {
    @Test func descriptorMissingAColorSetterThrowsApiUnavailable() async {
        await expectApiUnavailable(
            ShimClassNames(
                display: "CGVirtualDisplay",
                descriptor: "CropCastTestDescriptorWithoutWhitePoint",
                mode: "CGVirtualDisplayMode",
                settings: "CGVirtualDisplaySettings"))
    }

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
