import AppKit
import PaguroCore
import SwiftUI
import XCTest
@testable import Paguro

@MainActor
final class IslandRenderingTests: XCTestCase {
    func testBackgroundContinuesAcrossCameraAreaInCollapsedAlertAndExpandedStates() async throws {
        let event = try NotificationEvent.normalize(
            id: UUID(), serviceID: UUID(), source: .pageNotification,
            title: "Coffee break", body: "Alex: Coffee in ten minutes?", receivedAt: Date()
        )
        let reducer = NotificationIslandReducer()
        let alert = reducer.reduce(.hidden, action: .receive(event))
        let collapsed = reducer.reduce(alert, action: .suspendPresentation)
        let expanded = reducer.reduce(alert, action: .expand)

        for state in [collapsed, alert, expanded] {
            for scheme in [ColorScheme.light, .dark] {
                let model = NotificationIslandPanelModel()
                let content = NotificationIslandPanelContent(
                    event: event, serviceLabel: "Notification Test", serviceIconURL: nil
                )
                model.update(
                    state: state, content: state.currentEvent == nil ? nil : content,
                    recentContents: [content],
                    appearance: NotificationIslandAppearance(glassStyle: .off, transparency: 1),
                    cameraHousingSize: IslandScreenSize(width: 164, height: 38),
                    actions: .none
                )
                let width = switch state.phase {
                case .collapsed: 252.0
                case .alert: 372.0
                default: 432.0
                }
                let height = state.phase == .collapsed ? 38.0 : 120.0
                let view = NotificationIslandPanelView(model: model)
                    .frame(width: width, height: height)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))

                for y in [1, 18, 36] {
                    let pixel = try XCTUnwrap(bitmap.colorAt(x: Int(width / 2), y: y))
                    XCTAssertGreaterThan(pixel.alphaComponent, 0.9,
                                         "The surface must have no camera cutout in \(state.phase), \(scheme)")
                    if state.phase != .collapsed {
                        let neighbor = try XCTUnwrap(bitmap.colorAt(x: Int(width / 2 - 90), y: y))
                        assertSameBackground(pixel, neighbor)
                    }
                }
                // The island still paints its wing right up to the screen edge.
                let wing = try XCTUnwrap(bitmap.colorAt(x: 30, y: 1))
                XCTAssertGreaterThan(wing.alphaComponent, 0.9)

                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Paguro-island-rendering", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("\(state.phase)-\(scheme).png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
                print("Island rendering snapshot: \(url.path)")
                if state.phase == .expanded, scheme == .dark {
                    try await saveNativeSnapshot(of: view, size: CGSize(width: width, height: height),
                                                 name: "expanded-dark-native", in: directory)
                }
            }
        }
    }

    private func saveNativeSnapshot<V: View>(
        of view: V, size: CGSize, name: String, in directory: URL
    ) async throws {
        // ImageRenderer omits AppKit-backed scroll views and controls. Inspect
        // those in a real hosting view, in a panel outside the visible desktop.
        let panel = NSPanel(
            contentRect: CGRect(origin: CGPoint(x: -2000, y: -2000), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        defer { panel.close() }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.safeAreaRegions = []
        panel.contentView = host
        panel.orderBack(nil)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = Double(bitmap.pixelsHigh) / size.height
        for y in [1.0, 18, 36] {
            let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: Int(y * scale)))
            XCTAssertGreaterThan(pixel.alphaComponent, 0.9,
                                 "The native panel must have no camera cutout: \(name)")
            let neighbor = try XCTUnwrap(bitmap.colorAt(
                x: Int((size.width / 2 - 90) * scale), y: Int(y * scale)
            ))
            assertSameBackground(pixel, neighbor)
        }
        let wing = try XCTUnwrap(bitmap.colorAt(x: Int(30 * scale), y: Int(scale)))
        XCTAssertGreaterThan(wing.alphaComponent, 0.9, "The native snapshot must contain the panel")
        let url = directory.appendingPathComponent("\(name).png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        print("Island rendering snapshot: \(url.path)")
    }

    private func assertSameBackground(
        _ center: NSColor, _ neighbor: NSColor, file: StaticString = #filePath, line: UInt = #line
    ) {
        for (actual, expected) in zip(
            [center.redComponent, center.greenComponent, center.blueComponent, center.alphaComponent],
            [neighbor.redComponent, neighbor.greenComponent, neighbor.blueComponent, neighbor.alphaComponent]
        ) {
            XCTAssertEqual(actual, expected, accuracy: 0.02,
                           "The camera area must use the surrounding surface, without a black replica",
                           file: file, line: line)
        }
    }
}
