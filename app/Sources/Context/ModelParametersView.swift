import SwiftUI

extension ThinkingMode {
    var label: String {
        switch self {
        case .modelDefault: "Model Default"
        case .on: "On"
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

struct ModelParametersView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            HStack {
                SettingsHeader(
                    icon: "slider.horizontal.3",
                    title: "Model Parameters",
                    subtitle: "Global overrides applied to every new response.")
                Spacer(minLength: 0)
                Button("Reset All") {
                    state.generationOptions = .modelDefaults
                }
                .disabled(state.generationOptions == .modelDefaults)
                .buttonStyle(.bordered)
                .padding(.trailing, 20)
            }

            Divider()

            Form {
                Section("Thinking") {
                    Picker(selection: $state.generationOptions.thinking) {
                        ForEach(ThinkingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    } label: {
                        ParameterLabel(
                            "Mode",
                            help: "Controls whether supported models expose their reasoning")
                    }
                }

                Section("Generation") {
                    OptionalNumberRow(
                        "Temperature", value: $state.generationOptions.temperature,
                        defaultValue: 0.8, help: "Higher values make responses more creative")
                    OptionalNumberRow(
                        "Context size", value: $state.generationOptions.numCtx,
                        defaultValue: 4096, help: "Maximum number of input tokens remembered")
                    OptionalNumberRow(
                        "Maximum tokens", value: $state.generationOptions.numPredict,
                        defaultValue: 512, help: "Maximum output length; -1 is unlimited")
                    OptionalNumberRow(
                        "Seed", value: $state.generationOptions.seed, defaultValue: 0,
                        help: "Repeats results more consistently with the same prompt")
                }

                Section("Sampling") {
                    OptionalNumberRow(
                        "Top K", value: $state.generationOptions.topK, defaultValue: 40,
                        help: "Limits selection to the most likely tokens")
                    OptionalNumberRow(
                        "Top P", value: $state.generationOptions.topP, defaultValue: 0.9,
                        help: "Keeps tokens within a cumulative probability")
                    OptionalNumberRow(
                        "Min P", value: $state.generationOptions.minP, defaultValue: 0.0,
                        help: "Drops tokens far less likely than the best token")
                    OptionalNumberRow(
                        "Tail free", value: $state.generationOptions.tfsZ, defaultValue: 1.0,
                        help: "Reduces low-probability tokens; 1 disables it")
                }

                Section("Repetition") {
                    OptionalNumberRow(
                        "Lookback", value: $state.generationOptions.repeatLastN,
                        defaultValue: 64, help: "How many recent tokens are checked for repetition")
                    OptionalNumberRow(
                        "Penalty", value: $state.generationOptions.repeatPenalty,
                        defaultValue: 1.1, help: "How strongly repeated text is discouraged")
                }

                Section("Mirostat") {
                    Picker(selection: $state.generationOptions.mirostat) {
                        Text("Model Default").tag(UInt8?.none)
                        Text("Disabled").tag(UInt8?.some(0))
                        Text("Version 1").tag(UInt8?.some(1))
                        Text("Version 2").tag(UInt8?.some(2))
                    } label: {
                        ParameterLabel(
                            "Mode", help: "Adaptive sampling that targets consistent surprise")
                    }
                    OptionalNumberRow(
                        "Learning rate", value: $state.generationOptions.mirostatEta,
                        defaultValue: 0.1, help: "How quickly Mirostat adjusts its sampling")
                    OptionalNumberRow(
                        "Target entropy", value: $state.generationOptions.mirostatTau,
                        defaultValue: 5.0, help: "Target balance between focus and variety")
                }

                Section {
                    TextEditor(text: stopSequences)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 72)
                    Text("Enter one sequence per line. Leave empty to use the model default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    ParameterLabel(
                        "Stop Sequences", help: "Ends generation when any listed text appears")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var stopSequences: Binding<String> {
        Binding(
            get: { state.generationOptions.stop?.joined(separator: "\n") ?? "" },
            set: { text in
                let values = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                state.generationOptions.stop = values.isEmpty ? nil : values
            })
    }
}

private struct OptionalNumberRow<Value>: View
where Value: LosslessStringConvertible & Equatable & Sendable {
    let title: String
    @Binding var value: Value?
    let defaultValue: Value
    let help: String

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(_ title: String, value: Binding<Value?>, defaultValue: Value, help: String) {
        self.title = title
        _value = value
        self.defaultValue = defaultValue
        self.help = help
        _text = State(initialValue: value.wrappedValue.map { String($0) } ?? String(defaultValue))
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Toggle("Override", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                TextField("Value", text: $text)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .disabled(value == nil)
                    .focused($isFocused)
                    .onSubmit(commit)
                if value != nil && Value(text) == nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help("Enter a valid number")
                }
            }
        } label: {
            ParameterLabel(title, help: help)
        }
        .onChange(of: value) {
            if let value, !isFocused {
                text = String(value)
            }
        }
        .onChange(of: isFocused) {
            if !isFocused { commit() }
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { value != nil },
            set: { enabled in
                value = enabled ? (Value(text) ?? defaultValue) : nil
            })
    }

    private func commit() {
        guard value != nil, let parsed = Value(text) else { return }
        value = parsed
    }
}

private struct ParameterLabel: View {
    let title: String
    let help: String

    init(_ title: String, help: String) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help(help)
        }
    }
}
