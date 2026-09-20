import SwiftUI

/// A stable landmark across both setup pages and the optional website form.
struct FirstRunProgress: View {
    let isChoosingServices: Bool

    var body: some View {
        HStack(spacing: 14) {
            step(number: 1, title: "Welcome", isCurrent: !isChoosingServices, isComplete: isChoosingServices)
            Capsule()
                .fill(isChoosingServices ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25))
                .frame(width: 48, height: 1)
                .accessibilityHidden(true)
            step(number: 2, title: "Your workspace", isCurrent: isChoosingServices, isComplete: false)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: PaguroMotion.setupSelectionSeconds), value: isChoosingServices)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(isChoosingServices ? "Step 2 of 2, Your workspace" : "Step 1 of 2, Welcome")
    }

    private func step(number: Int, title: String, isCurrent: Bool, isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.12))
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(number)")
                        .font(.paguroCaption.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                }
            }
            .frame(width: 26, height: 26)
            Text(title)
                .font(.paguroBody.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }
}

/// Navigation keeps the same baseline on every setup page.
struct FirstRunFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                leading()
                Spacer()
                trailing()
            }
            .controlSize(.large)
            .frame(minHeight: 36)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }
}
