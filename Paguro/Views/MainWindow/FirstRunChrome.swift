import PaguroCore
import SwiftUI

extension FirstRunStep {
    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .workspace: "Your workspace"
        case .appearance: "Appearance"
        }
    }
}

/// A stable landmark across the setup pages.
struct FirstRunProgress: View {
    let currentStep: FirstRunStep
    let canContinue: Bool
    let onSelect: (FirstRunStep) -> Void
    @State private var hoveredStep: FirstRunStep?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FirstRunStep.allCases, id: \.self) { item in
                if item != .welcome {
                    Capsule()
                        .fill(item.rawValue <= currentStep.rawValue
                            ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25))
                        .frame(width: 24, height: 1)
                        .accessibilityHidden(true)
                }
                stepControl(item)
            }
        }
        .animation(.easeInOut(duration: PaguroMotion.setupSelectionSeconds), value: currentStep)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(currentStep.rawValue) of 3, \(currentStep.title)")
    }

    @ViewBuilder
    private func stepControl(_ item: FirstRunStep) -> some View {
        if item == currentStep {
            step(number: item.rawValue, title: item.title, isCurrent: true, isComplete: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.title), current step")
                .accessibilityAddTraits(.isSelected)
        } else {
            let available = currentStep.canNavigate(to: item, canCreateWorkspace: canContinue)
            Button { onSelect(item) } label: {
                step(number: item.rawValue, title: item.title, isCurrent: false,
                     isComplete: item.rawValue < currentStep.rawValue,
                     isHovered: hoveredStep == item && available)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(SetupKeyboardActivation { onSelect(item) })
            .disabled(!available)
            .onHover { hoveredStep = $0 ? item : nil }
            .accessibilityLabel(item.title)
            .accessibilityRemoveTraits(.isSelected)
            .accessibilityValue(item.rawValue < currentStep.rawValue ? "Completed" : "")
            .accessibilityHint(available
                ? "Go to \(item.title) without saving your workspace"
                : "Enter a workspace name and select at least one service first")
        }
    }

    private func step(
        number: Int, title: String, isCurrent: Bool, isComplete: Bool, isHovered: Bool = false
    ) -> some View {
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
                .foregroundStyle(isHovered ? Color.accentColor : (isCurrent ? Color.primary : Color.secondary))
        }
    }
}

/// Navigation keeps the same baseline on every setup page.
struct FirstRunFooter<Leading: View, Trailing: View>: View {
    let currentStep: FirstRunStep
    let canContinue: Bool
    let onSelect: (FirstRunStep) -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    leading().fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                    FirstRunProgress(currentStep: currentStep, canContinue: canContinue, onSelect: onSelect).fixedSize()
                    trailing().fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(spacing: 16) {
                    FirstRunProgress(currentStep: currentStep, canContinue: canContinue, onSelect: onSelect)
                    HStack {
                        leading()
                        Spacer()
                        trailing()
                    }
                }
            }
            .controlSize(.large)
            .frame(minHeight: 36)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }
}
