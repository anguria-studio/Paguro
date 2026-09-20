import PaguroCore
import SwiftUI

/// The shell itself previews these saved appearance preferences live.
struct FirstRunAppearanceView: View {
    let allowsActions: Bool
    let canFinish: Bool
    let saveError: String?
    let onBack: () -> Void
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState
    @FocusState private var finishIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Make Paguro yours")
                            .font(.largeTitle.weight(.semibold))
                        Text("Choose how your workspace looks. You can change this later in Settings.")
                            .font(.paguroBody)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Theme").font(.headline)
                        HStack(spacing: 12) {
                            themeChoice(.system, title: "Follow System", symbol: "circle.lefthalf.filled")
                            themeChoice(.light, title: "Light", symbol: "sun.max")
                            themeChoice(.dark, title: "Dark", symbol: "moon.stars")
                        }
                    }
                    if AppCapabilities.liquidGlassSupported {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Liquid Glass").font(.headline)
                            HStack(spacing: 12) {
                                ForEach(ShellGlassStyle.allCases, id: \.self) { style in
                                    choice(title: style.displayName, symbol: glassSymbol(style),
                                           isSelected: appState.liquidGlassStyle == style) {
                                        guard allowsActions, !appState.isLocked else { return }
                                        appState.setLiquidGlassStyle(style)
                                    }
                                }
                            }
                            Text(appState.liquidGlassStyle.explanation)
                                .font(.paguroBody)
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 36, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("These choices change the Paguro shell. Each website controls its own appearance.")
                        .font(.paguroCaption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let saveError {
                Text(saveError)
                    .font(.paguroCaption)
                    .foregroundStyle(.red)
                    .padding(12)
            }
            FirstRunFooter(currentStep: .appearance) {
                Button("Back", action: onBack)
                    .modifier(SetupKeyboardActivation(action: onBack))
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Create workspace", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .modifier(SetupKeyboardActivation(action: onFinish))
                    .focused($finishIsFocused)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canFinish)
            }
        }
        .disabled(!allowsActions)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your appearance")
        .task {
            await Task.yield()
            guard !Task.isCancelled, allowsActions else { return }
            finishIsFocused = true
        }
    }

    private func themeChoice(_ mode: AppearanceMode, title: String, symbol: String) -> some View {
        choice(title: title, symbol: symbol, isSelected: appState.appearanceMode == mode) {
            guard allowsActions, !appState.isLocked else { return }
            appState.setAppearanceMode(mode)
        }
    }

    private func choice(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .frame(height: 36)
                    .accessibilityHidden(true)
                Text(title).font(.paguroBody.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.primary.opacity(isSelected ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.2),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .modifier(SetupKeyboardActivation(action: action))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func glassSymbol(_ style: ShellGlassStyle) -> String {
        switch style {
        case .system: "desktopcomputer"
        case .off: "rectangle.fill"
        case .clear: "rectangle"
        case .regular: "rectangle.on.rectangle"
        }
    }
}
