import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ModelParametersView()
                .tabItem {
                    Label("Model Parameters", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 560, height: 610)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            SettingsHeader(
                icon: "gearshape.fill",
                title: "General",
                subtitle: "Choose how Context looks and which model new chats use.")

            Divider()

            Form {
                Section("Application") {
                    Picker("Appearance", selection: $state.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .help("Controls the app’s light or dark appearance")

                    if state.models.isEmpty {
                        LabeledContent("Default model", value: "No local models available")
                    } else {
                        Picker("Default model", selection: $state.defaultModel) {
                            ForEach(state.models, id: \.name) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .help("The model selected when you start a new chat")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct SettingsHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }
}
