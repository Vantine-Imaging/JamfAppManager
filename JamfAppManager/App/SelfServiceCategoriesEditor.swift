import SwiftUI

/// Checklist of Self Service categories with per-category Display/Feature
/// toggles, editing a `[SelfServiceCategory]` selection.
struct SelfServiceCategoriesEditor: View {
    let categories: [NamedID]
    @Binding var selection: [SelfServiceCategory]

    var body: some View {
        if categories.isEmpty {
            Text("No categories defined on this server.")
                .foregroundStyle(.secondary)
        }
        ForEach(categories) { category in
            row(category: category)
        }
    }

    private func row(category: NamedID) -> some View {
        let displayBinding = Binding(
            get: { selection.contains { $0.id == category.id } },
            set: { on in
                selection.removeAll { $0.id == category.id }
                if on {
                    selection.append(
                        SelfServiceCategory(id: category.id, name: category.name, displayIn: true, featureIn: false)
                    )
                }
            }
        )
        let featureBinding = Binding(
            get: { selection.first { $0.id == category.id }?.featureIn ?? false },
            set: { on in
                if let index = selection.firstIndex(where: { $0.id == category.id }) {
                    selection[index].featureIn = on
                }
            }
        )
        return HStack {
            Text(category.name ?? "ID \(category.id)")
            Spacer()
            Toggle("Display", isOn: displayBinding)
                .toggleStyle(.checkbox)
            Toggle("Feature", isOn: featureBinding)
                .toggleStyle(.checkbox)
                .disabled(!displayBinding.wrappedValue)
        }
    }
}
