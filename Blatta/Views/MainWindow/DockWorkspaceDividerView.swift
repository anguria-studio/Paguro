import SwiftUI
import BlattaCore

/// The break between two workspace groups in the collapsed Dock.
///
/// The view reads the pointer state itself, as a cell does. A rail that read it
/// would rebuild its complete cell list, and the fetches behind them, on every
/// mouse event. See the comment in `RailServiceCell.row`.
///
/// The divider is a mark, not a target. The fixed rail viewport receives every
/// click, and the resolver answers a bare divider with no item.
struct DockWorkspaceDividerView: View {
    /// The index of the last item before the divider.
    let afterIndex: Int
    let dockSizing: DockSizing
    let dockMagnification: DockMagnificationState

    var body: some View {
        let transform = dockMagnification.separatorTransform(
            afterIndex: afterIndex,
            sizing: dockSizing
        )

        Divider()
            .padding(
                .horizontal,
                BlattaMetric.Sidebar.workspaceDividerHorizontalInset
            )
            // The divider keeps its resting height. The pointer is converted to
            // a position in the resting stack, so this layout must hold still.
            .frame(height: BlattaMetric.Sidebar.workspaceDividerHeight)
            // The move is drawn and nothing else, exactly as a row moves.
            .visualEffect { [offset = transform.verticalOffset] content, _ in
                content.offset(y: offset)
            }
            .accessibilityHidden(true)
    }
}
