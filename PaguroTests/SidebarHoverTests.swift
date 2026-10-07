import AppKit
import PaguroCore
import SwiftUI
import XCTest
@testable import Paguro

@MainActor
final class SidebarHoverTests: XCTestCase {
    func testCollapsedServiceHoverBackground() throws {
        let service = ModelFixtures.service(label: "Hover fixture", catalogID: nil)
        try assertHoverBackground { hovered, selected, transform in
            ServiceRowView(
                instance: service,
                isSelected: selected,
                sidebarPresentation: .collapsed,
                glassStyle: .off,
                glassIntensity: 0,
                dockTransform: transform,
                dockTooltipLeadingOffset: 100,
                isDockHovered: hovered,
                action: {}
            )
        }
    }

    func testCollapsedWorkspaceHoverBackground() throws {
        let space = Space(name: "Hover fixture")
        try assertHoverBackground { hovered, selected, transform in
            WorkspaceCellView(
                space: space,
                isSelected: selected,
                sidebarPresentation: .collapsed,
                glassStyle: .off,
                glassIntensity: 0,
                dockTransform: transform,
                dockTooltipLeadingOffset: 100,
                isDockHovered: hovered,
                action: {}
            )
        }
    }

    private func assertHoverBackground<Content: View>(
        @ViewBuilder content: (Bool, Bool, DockIconTransform) -> Content
    ) throws {
        for scheme in [ColorScheme.light, .dark] {
            func alpha(hovered: Bool, selected: Bool = false, scale: CGFloat = 1) throws -> CGFloat {
                let renderer = ImageRenderer(content: content(
                    hovered, selected, DockIconTransform(scale: scale)
                )
                    .frame(width: 62, height: 44)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 1
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                // Icons grow to the right, leaving this leading padding clear.
                return try XCTUnwrap(bitmap.colorAt(x: 16, y: 22)).alphaComponent
            }

            XCTAssertEqual(try alpha(hovered: false), 0, accuracy: 0.005)
            XCTAssertEqual(try alpha(hovered: true), scheme == .light ? 0.04 : 0.12, accuracy: 0.005)
            XCTAssertEqual(try alpha(hovered: true, selected: true),
                           try alpha(hovered: false, selected: true), accuracy: 0.005)
            XCTAssertEqual(try alpha(hovered: true, scale: 1.5), 0, accuracy: 0.005)
        }
    }
}
