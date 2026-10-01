import SwiftUI

/// Keeps the icon and label in one hierarchy while the sidebar changes width.
struct SidebarItemContent<Icon: View, Label: View>: View {
    let isCollapsed: Bool
    let dockIconSize: CGFloat
    let dockItemSize: CGFloat
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: isCollapsed ? 0 : 8) {
            icon()

            label()
                .frame(maxWidth: .infinity)
                .frame(width: isCollapsed ? 0 : nil)
                .opacity(isCollapsed ? 0 : 1)
                .clipped()
                .accessibilityHidden(isCollapsed)
        }
        .padding(.horizontal, isCollapsed ? (dockItemSize - dockIconSize) / 2 : 8)
        .frame(
            width: isCollapsed ? dockItemSize : PaguroMetric.Sidebar.rowWidth,
            height: isCollapsed ? dockItemSize : PaguroMetric.Sidebar.rowHeight
        )
    }
}
