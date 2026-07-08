import Foundation
import Observation

/// Persists templates as JSON in the app's Application Support container.
@MainActor
@Observable
final class TemplateStore {
    private(set) var templates: [SettingsTemplate] = []

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: "JamfAppManager", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "templates.json")
        load()
    }

    func templates(for catalog: AppCatalog) -> [SettingsTemplate] {
        templates.filter { $0.catalog == catalog }
    }

    func template(id: UUID?) -> SettingsTemplate? {
        templates.first { $0.id == id }
    }

    @discardableResult
    func add(_ template: SettingsTemplate) -> SettingsTemplate {
        var new = template
        if new.name.isEmpty { new.name = "Untitled Template" }
        templates.append(new)
        persist()
        return new
    }

    func update(_ template: SettingsTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        persist()
    }

    func remove(_ template: SettingsTemplate) {
        templates.removeAll { $0.id == template.id }
        persist()
    }

    @discardableResult
    func duplicate(_ template: SettingsTemplate) -> SettingsTemplate {
        var copy = template
        copy.id = UUID()
        copy.name += " Copy"
        templates.append(copy)
        persist()
        return copy
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([SettingsTemplate].self, from: data)
        else { return }
        templates = saved
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(templates) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
