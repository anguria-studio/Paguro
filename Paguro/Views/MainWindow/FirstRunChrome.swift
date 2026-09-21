import SwiftUI

enum FirstRunStep: Int, CaseIterable {
    case welcome = 1
    case workspace
    case appearance

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
                step(number: item.rawValue, title: item.title,
                     isCurrent: item == currentStep, isComplete: item.rawValue < currentStep.rawValue)
            }
        }
        .animation(.easeInOut(duration: PaguroMotion.setupSelectionSeconds), value: currentStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(currentStep.rawValue) of 3, \(currentStep.title)")
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let currentStep: FirstRunStep
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    leading().fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                    FirstRunProgress(currentStep: currentStep).fixedSize()
                    trailing().fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(spacing: 16) {
                    FirstRunProgress(currentStep: currentStep)
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
        .background(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : 0.35))
    }
}
