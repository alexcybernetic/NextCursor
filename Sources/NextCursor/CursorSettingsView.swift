import SwiftUI

struct CursorSettingsView: View {
    @ObservedObject var store: CursorSettingsStore
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            Section("Pointer") {
                Picker("Shape", selection: store.binding(for: \.shape)) {
                    ForEach(CursorShapeKind.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }

                Toggle(
                    "Motion inertia",
                    isOn: store.binding(for: \.usesPointerInertia)
                )

                ValueSlider(
                    title: "Size",
                    value: store.binding(for: \.pointerSize),
                    range: CursorAppearanceSettings.sizeRange,
                    step: 1,
                    label: { "\(Int($0)) pt" }
                )

                ValueSlider(
                    title: "Border width",
                    value: store.binding(for: \.borderWidth),
                    range: CursorAppearanceSettings.borderWidthRange,
                    step: 0.5,
                    label: { $0 < 0.01 ? "None" : String(format: "%.1f pt", $0) }
                )

                // Light and dark sit on one row per property: the two are a
                // single decision about one colour, not two separate settings.
                appearanceHeader
                colourRow("Fill", light: \.lightFill, dark: \.darkFill)
                colourRow("Border", light: \.lightBorder, dark: \.darkBorder)
            }

            Section("Snapped control") {
                ValueSlider(
                    title: "Padding",
                    value: store.binding(for: \.controlPadding),
                    range: CursorAppearanceSettings.controlPaddingRange,
                    step: 0.5,
                    label: { String(format: "%.1f pt", $0) }
                )

                ValueSlider(
                    title: "Border width",
                    value: store.binding(for: \.controlBorderWidth),
                    range: CursorAppearanceSettings.controlBorderWidthRange,
                    step: 0.25,
                    label: { $0 < 0.01 ? "None" : String(format: "%.2f pt", $0) }
                )

                appearanceHeader
                colourRow("Fill", light: \.lightControlFill, dark: \.darkControlFill)
                colourRow("Border", light: \.lightControlBorder, dark: \.darkControlBorder)
            }

            Section {
                Text(
                    "The shape applies to the free pointer. Over a control the "
                        + "pointer still takes that control's shape."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Reset to defaults") {
                        isShowingResetConfirmation = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        // A grouped Form scrolls, so it reports no intrinsic height. Without a
        // minimum the hosting controller sizes the content to zero and the
        // window opens as a bare title bar.
        .frame(minWidth: 380, minHeight: 480)
        .confirmationDialog(
            "Reset all pointer settings?",
            isPresented: $isShowingResetConfirmation
        ) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var appearanceHeader: some View {
        LabeledContent("") {
            HStack(spacing: 0) {
                Text("Light").frame(width: Self.wellColumnWidth)
                Text("Dark").frame(width: Self.wellColumnWidth)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func colourRow(
        _ title: String,
        light: WritableKeyPath<CursorAppearanceSettings, StoredColor>,
        dark: WritableKeyPath<CursorAppearanceSettings, StoredColor>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                colourWell(light)
                colourWell(dark)
            }
        }
    }

    private func colourWell(
        _ keyPath: WritableKeyPath<CursorAppearanceSettings, StoredColor>
    ) -> some View {
        ColorPicker("", selection: color(for: keyPath))
            .labelsHidden()
            .frame(width: Self.wellColumnWidth)
    }

    private static let wellColumnWidth: CGFloat = 64

    private func color(
        for keyPath: WritableKeyPath<CursorAppearanceSettings, StoredColor>
    ) -> Binding<Color> {
        Binding(
            get: { store.settings[keyPath: keyPath].color },
            set: { store.set(StoredColor(color: $0), for: keyPath) }
        )
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                Text(label(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }
}
