import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Paguro

@MainActor
final class SidebarAnimationTests: XCTestCase {
    func testSidebarKeepsOneIconThroughExpansionAndCollapse() async throws {
        let state = PresentationState()
        let lifetime = IconLifetime()
        let view = SidebarProbe(state: state, lifetime: lifetime)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        host.layoutSubtreeIfNeeded()
        try await waitUntil { lifetime.views.count == 1 }
        let icon = try XCTUnwrap(lifetime.views.first)

        for size: CGFloat in [14, 22, 44] {
            state.dockIconSize = size
            for collapsed in [true, false, true, false] {
                state.isCollapsed = collapsed
                host.layoutSubtreeIfNeeded()
                let expectedSize = collapsed ? size : PaguroMetric.Sidebar.expandedIconSize
                try await waitUntil {
                    host.layoutSubtreeIfNeeded()
                    return abs(icon.frame.width - expectedSize) < 0.01
                }
                XCTAssertEqual(lifetime.views.count, 1, "The icon must not be replaced")
                XCTAssertEqual(icon.frame.height, expectedSize, accuracy: 0.01)
            }
        }
    }

    func testServiceIconStaysOpaqueAndSingleDuringBothTransitions() async throws {
        let fixture = try ServiceFixture()
        defer { fixture.window.close() }
        try await waitUntil { fixture.state.hasAppeared }
        fixture.host.layoutSubtreeIfNeeded()

        for collapsed in [true, false] {
            var finished = false
            withAnimation(.linear(duration: 0.6), completionCriteria: .removed) {
                fixture.state.isCollapsed = collapsed
            } completion: {
                finished = true
            }
            let deadline = Date().addingTimeInterval(3)
            repeat {
                try await Task.sleep(for: .milliseconds(30))
                _ = try sampleIcon(in: fixture.host)
            } while !finished && Date() < deadline
            XCTAssertTrue(finished, "The animation must complete")
        }
    }

    func testServiceIconStaysVisibleWhenTheAnimationReversesBeforeCompletion() async throws {
        let fixture = try ServiceFixture()
        defer { fixture.window.close() }
        try await waitUntil { fixture.state.hasAppeared }
        let initial = try sampleIcon(in: fixture.host)
        var completedSteps: Set<Int> = []

        for (step, collapsed) in [true, false, true, false].enumerated() {
            let start = try sampleIcon(in: fixture.host)
            let isLastStep = step == 3
            let targetCenter = collapsed ? fixture.host.bounds.midX : initial.centerX
            let minimumTravel = min(8, abs(targetCenter - start.centerX) / 4)
            withAnimation(.linear(duration: isLastStep ? 0.3 : 4), completionCriteria: .removed) {
                fixture.state.isCollapsed = collapsed
            } completion: {
                completedSteps.insert(step)
            }

            let deadline = Date().addingTimeInterval(6)
            var current = start
            repeat {
                try await Task.sleep(for: .milliseconds(30))
                current = try sampleIcon(in: fixture.host)
                if !isLastStep && abs(current.centerX - start.centerX) > minimumTravel { break }
            } while !completedSteps.contains(step) && Date() < deadline

            if isLastStep {
                XCTAssertTrue(completedSteps.contains(step), "The final animation must complete")
                XCTAssertEqual(current.centerX, initial.centerX, accuracy: 1)
                XCTAssertEqual(current.width, initial.width, accuracy: 1)
            } else {
                XCTAssertGreaterThan(abs(current.centerX - start.centerX), minimumTravel)
                XCTAssertFalse(completedSteps.contains(step), "Reverse while the icon is moving")
            }
        }
    }

    private func sampleIcon(in host: NSHostingView<ServiceProbe>) throws -> IconSample {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // The fixture holds the icon on this centerline in both presentations.
        let y = bitmap.pixelsHigh / 2
        let columns = (0..<bitmap.pixelsWide).filter { x in
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                return false
            }
            return color.redComponent > 0.8 && color.greenComponent < 0.4
                && color.blueComponent < 0.3
        }
        if columns.isEmpty {
            let attachment = XCTAttachment(
                data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                uniformTypeIdentifier: "public.png"
            )
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let first = try XCTUnwrap(columns.first, "The icon must remain visible")
        let last = try XCTUnwrap(columns.last)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        XCTAssertLessThanOrEqual(CGFloat(last - first + 1), 23 * scale,
                                 "The transition must not draw two separated icons")
        XCTAssertGreaterThanOrEqual(CGFloat(columns.count), 16 * scale,
                                    "The icon must not fade away")
        return IconSample(
            centerX: CGFloat(first + last + 1) / (2 * scale),
            width: CGFloat(last - first + 1) / scale
        )
    }

    private struct IconSample {
        let centerX: CGFloat
        let width: CGFloat
    }

    @MainActor
    private final class ServiceFixture {
        let state = PresentationState()
        let host: NSHostingView<ServiceProbe>
        let window: NSWindow

        init() throws {
            let service = ModelFixtures.service(label: "Animation fixture", catalogID: nil)
            let image = NSImage(size: NSSize(width: 44, height: 44), flipped: false) { bounds in
                NSColor.red.setFill()
                bounds.fill()
                return true
            }
            service.customIconData = try XCTUnwrap(image.tiffRepresentation)
            host = NSHostingView(rootView: ServiceProbe(state: state, service: service))
            host.sizingOptions = []
            host.safeAreaRegions = []
            window = NSWindow(
                contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 100),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    @Observable
    final class PresentationState {
        var isCollapsed = false
        var dockIconSize: CGFloat = 22
        var hasAppeared = false
    }

    private final class IconLifetime {
        var views: [NSView] = []
    }

    private struct IconProbe: NSViewRepresentable {
        let lifetime: IconLifetime

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            lifetime.views.append(view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private struct SidebarProbe: View {
        let state: PresentationState
        let lifetime: IconLifetime

        var body: some View {
            SidebarItemContent(
                isCollapsed: state.isCollapsed,
                dockIconSize: state.dockIconSize,
                dockItemSize: state.dockIconSize + 14
            ) {
                let size = state.isCollapsed ? state.dockIconSize : PaguroMetric.Sidebar.expandedIconSize
                IconProbe(lifetime: lifetime).frame(width: size, height: size)
            } label: {
                Text("A long service or workspace name").lineLimit(1)
            }
            .frame(width: 300, height: 100)
        }
    }

    private struct ServiceProbe: View {
        let state: PresentationState
        let service: ServiceInstance

        var body: some View {
            ServiceRowView(
                instance: service,
                isSelected: false,
                sidebarPresentation: state.isCollapsed ? .collapsed : .expanded,
                action: {}
            )
            .frame(width: 300, height: 100)
            .background(.black)
            .environment(\.colorScheme, .dark)
            .onAppear { state.hasAppeared = true }
        }
    }
}
