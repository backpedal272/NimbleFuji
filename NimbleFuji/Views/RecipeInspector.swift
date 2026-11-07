import SwiftUI

/// Shows the recipe chosen in the sidebar and lets the user edit it.
struct RecipeInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let recipe = model.recipes.recipe(withID: model.editingRecipeID) {
            RecipeEditor(original: recipe)
                .id(recipe.id)
        } else {
            ContentUnavailableView("No Recipe Selected", systemImage: "camera.filters",
                                   description: Text("Choose a recipe in the sidebar to edit it."))
        }
    }
}

struct RecipeEditor: View {
    @Environment(AppModel.self) private var model
    let original: Recipe
    @State private var draft: Recipe
    @State private var showYAML = false

    init(original: Recipe) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var isDirty: Bool { !draft.hasSameContent(as: original) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
            }

            Section("Comment") {
                PlaceholderEditor(text: optionalText($draft.comment),
                                  placeholder: "When you use this recipe, what you changed from the original…")
            }

            Section("Film Simulation") {
                ChoicePicker("Film Simulation", selection: $draft.filmSimulation)
                if draft.filmSimulation?.isMonochrome ?? false {
                    StepPicker("Monochromatic WC", value: intBinding($draft.monochromaticColorWarmCool), rule: .monochromatic)
                    StepPicker("Monochromatic MG", value: intBinding($draft.monochromaticColorMagentaGreen), rule: .monochromatic)
                }
                ChoicePicker("Grain Effect", selection: $draft.grainEffect)
                ChoicePicker("Color Chrome Effect", selection: $draft.colorChromeEffect)
                ChoicePicker("Color Chrome FX Blue", selection: $draft.colorChromeFXBlue)
            }

            Section("White Balance") {
                ChoicePicker("White Balance", selection: $draft.whiteBalance)
                if draft.whiteBalance == .temperature {
                    KelvinField(value: $draft.whiteBalanceTemperature)
                }
                StepPicker("Shift Red", value: intBinding($draft.whiteBalanceShiftRed), rule: .wbShift)
                StepPicker("Shift Blue", value: intBinding($draft.whiteBalanceShiftBlue), rule: .wbShift)
            }

            Section("Tone") {
                ChoicePicker("Dynamic Range", selection: $draft.dynamicRange)
                ChoicePicker("D-Range Priority", selection: $draft.dynamicRangePriority)
                StepPicker("Highlight", value: $draft.highlightTone, rule: .tone)
                StepPicker("Shadow", value: $draft.shadowTone, rule: .tone)
            }

            Section("Detail") {
                StepPicker("Color", value: intBinding($draft.color), rule: .fourSteps)
                StepPicker("Sharpness", value: intBinding($draft.sharpness), rule: .fourSteps)
                StepPicker("High ISO NR", value: intBinding($draft.noiseReduction), rule: .fourSteps)
                StepPicker("Clarity", value: intBinding($draft.clarity), rule: .clarity)
                ChoicePicker("Smooth Skin", selection: $draft.smoothSkinEffect)
            }

            Section {
                StepPicker("Exposure (EV)", value: $draft.exposureOffset, rule: .exposure)
            } header: {
                Text("Render")
            } footer: {
                Text("Settings left at “As shot” keep the value the photo was taken with.")
                    .foregroundStyle(.secondary)
            }

            let issues = draft.validationIssues()
            if !issues.isEmpty {
                Section {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Origin") {
                TextField("Source", text: optionalText($draft.source), prompt: Text("URL or credit"))
                PlaceholderEditor(text: optionalText($draft.notes),
                                  placeholder: "Where the recipe came from, its history, as imported…")
            }

            Section {
                DisclosureGroup("YAML", isExpanded: $showYAML) {
                    Text((try? draft.toYAML()) ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Revert") { draft = original }
                    .disabled(!isDirty)
                Spacer()
                Button("Save") { model.save(draft) }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(.bar)
        }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding {
            binding.wrappedValue ?? ""
        } set: { newValue in
            binding.wrappedValue = newValue.isEmpty ? nil : newValue
        }
    }

    private func intBinding(_ binding: Binding<Int?>) -> Binding<Double?> {
        Binding {
            binding.wrappedValue.map(Double.init)
        } set: { newValue in
            binding.wrappedValue = newValue.map { Int($0.rounded()) }
        }
    }
}

// MARK: - Controls

/// Multi-line text field with a placeholder.
private struct PlaceholderEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(minHeight: 60, maxHeight: 180)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct ChoicePicker<T: RecipeChoice>: View {
    let title: String
    @Binding var selection: T?

    init(_ title: String, selection: Binding<T?>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("As shot").tag(T?.none)
            Divider()
            ForEach(Array(T.allCases), id: \.self) { value in
                Text(value.label).tag(Optional(value))
            }
        }
    }
}

private struct StepPicker: View {
    let title: String
    @Binding var value: Double?
    let rule: NumericRule

    init(_ title: String, value: Binding<Double?>, rule: NumericRule) {
        self.title = title
        _value = value
        self.rule = rule
    }

    var body: some View {
        Picker(title, selection: $value) {
            Text("As shot").tag(Double?.none)
            Divider()
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(Optional(option))
            }
        }
    }

    /// Includes an off-grid value loaded from YAML so the picker can show it.
    private var options: [Double] {
        var values = rule.values
        if let value, !values.contains(where: { abs($0 - value) < 1e-6 }) {
            values.append(value)
            values.sort()
        }
        return values
    }

    private func label(_ number: Double) -> String {
        if rule.step < 0.5 {
            // Exposure: show thirds as fractions.
            let thirds = Int((number * 3).rounded())
            if thirds == 0 { return "0" }
            let whole = abs(thirds) / 3, remainder = abs(thirds) % 3
            let sign = thirds > 0 ? "+" : "−"
            switch (whole, remainder) {
            case (_, 0): return "\(sign)\(whole)"
            case (0, _): return "\(sign)\(remainder)/3"
            default: return "\(sign)\(whole) \(remainder)/3"
            }
        }
        return Recipe.format(number, signed: true).replacingOccurrences(of: "-", with: "−")
    }
}

private struct KelvinField: View {
    @Binding var value: Int?

    var body: some View {
        let kelvin = Binding<Int> {
            value ?? 5500
        } set: { newValue in
            let rule = NumericRule.kelvin
            let clamped = min(max(Double(newValue), rule.min), rule.max)
            value = Int((clamped / rule.step).rounded() * rule.step)
        }
        LabeledContent("Temperature") {
            HStack(spacing: 4) {
                TextField("Kelvin", value: kelvin, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("K").foregroundStyle(.secondary)
                Stepper("Temperature", value: kelvin, in: 2500...10000, step: 100)
                    .labelsHidden()
            }
        }
        .onAppear { if value == nil { value = 5500 } }
    }
}
