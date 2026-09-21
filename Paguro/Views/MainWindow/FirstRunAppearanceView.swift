import PaguroCore
import SwiftUI

/// The shell itself previews these saved appearance preferences live.
struct FirstRunAppearanceView: View {
    let allowsActions: Bool
    let saveError: String?

    @Environment(AppState.self) private var appState

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
                            themeChoice(.system, title: "Follow System")
                            themeChoice(.light, title: "Light")
                            themeChoice(.dark, title: "Dark")
                        }
                    }
                    if AppCapabilities.liquidGlassSupported {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Liquid Glass").font(.headline)
                            HStack(spacing: 12) {
                                ForEach(ShellGlassStyle.allCases, id: \.self) { style in
                                    choice(title: style.displayName,
                                           isSelected: appState.liquidGlassStyle == style) {
                                        guard allowsActions, !appState.isLocked else { return }
                                        appState.setLiquidGlassStyle(style)
                                    } preview: {
                                        SetupGlassPreview(style: style)
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
        }
        .disabled(!allowsActions)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your appearance")
    }

    private func themeChoice(_ mode: AppearanceMode, title: String) -> some View {
        choice(title: title, isSelected: appState.appearanceMode == mode) {
            guard allowsActions, !appState.isLocked else { return }
            appState.setAppearanceMode(mode)
        } preview: {
            SetupThemePreview(mode: mode)
        }
    }

    private func choice<Preview: View>(
        title: String, isSelected: Bool, action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                preview()
                    .frame(maxWidth: 144)
                    .frame(height: 76)
                    .accessibilityHidden(true)
                Text(title).font(.paguroBody.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .background(
                .primary.opacity(isSelected ? 0.10 : (appState.liquidGlassStyle == .off ? 0 : 0.04)),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .background {
                if appState.liquidGlassStyle == .off {
                    RoundedRectangle(cornerRadius: 14).fill(PaguroColor.Solid.card)
                }
            }
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

}
