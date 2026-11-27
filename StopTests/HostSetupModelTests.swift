import Foundation
import StopCore
import StopSession
import Testing
@testable import Stop

@MainActor
struct HostSetupModelTests {
    let store = InMemoryGameStore()

    func makeModel(language: GameLanguage = .en) async -> HostSetupModel {
        let model = HostSetupModel(store: store, language: language)
        await model.load()
        return model
    }

    @Test func setupStartsWithDefaultsSelected() async {
        let model = await makeModel()
        let defaults = DefaultCategories.list(for: .en)
        #expect(model.available == defaults)
        #expect(model.selected == Array(defaults.prefix(6)))
        #expect(model.stopsRequired == 1)
        #expect(!model.allowGiveUp)
        #expect(model.canCreate)
    }

    @Test func defaultsFollowLanguage() async {
        let model = await makeModel(language: .ptBR)
        #expect(model.selected == Array(DefaultCategories.list(for: .ptBR).prefix(6)))
    }

    @Test func customCategoryPersistedAndSelected() async {
        let model = await makeModel()

        await model.addCustom("  Cartoons  ")

        #expect(model.available.last == "Cartoons")
        #expect(model.selected.last == "Cartoons")
        #expect(model.isCustom("Cartoons"))
        #expect(await store.loadCustomCategories() == ["Cartoons"])

        let reopened = await makeModel()
        #expect(reopened.available.contains("Cartoons"))
        #expect(!reopened.selected.contains("Cartoons"))
    }

    @Test func addingExistingCategorySelectsItWithoutDuplicating() async {
        let model = await makeModel()
        model.toggle("Animal")
        #expect(!model.selected.contains("Animal"))

        await model.addCustom("animal")
        await model.addCustom("   ")

        #expect(model.available.filter { $0.lowercased() == "animal" }.count == 1)
        #expect(model.selected.contains("Animal"))
        #expect(await store.loadCustomCategories().isEmpty)
    }

    @Test func addingBeforeLoadKeepsRememberedCategories() async {
        await store.saveCustomCategories(["Cartoons"])
        let model = HostSetupModel(store: store, language: .en)

        await model.addCustom("Bands")
        await model.load()

        #expect(model.available.suffix(2) == ["Cartoons", "Bands"])
        #expect(model.selected.last == "Bands")
        #expect(await store.loadCustomCategories() == ["Cartoons", "Bands"])
    }

    @Test func longNamesAreCutAndTrimmed() async {
        let model = await makeModel()
        await model.addCustom("  " + String(repeating: "a", count: 29) + " tail")
        #expect(model.selected.last == String(repeating: "a", count: 29))
    }

    @Test func deletingCustomCategoryForgetsIt() async {
        let model = await makeModel()
        await model.addCustom("Cartoons")

        await model.deleteCustom("Cartoons")

        #expect(!model.available.contains("Cartoons"))
        #expect(!model.selected.contains("Cartoons"))
        #expect(await store.loadCustomCategories().isEmpty)
    }

    @Test func deletingBeforeLoadKeepsOtherRememberedCategories() async {
        await store.saveCustomCategories(["Cartoons", "Bands"])
        let model = HostSetupModel(store: store, language: .en)

        await model.deleteCustom("Cartoons")

        #expect(model.isCustom("Bands"))
        #expect(!model.available.contains("Cartoons"))
        #expect(await store.loadCustomCategories() == ["Bands"])
    }

    @Test func toggleAppendsAndRemoves() async {
        let model = await makeModel()
        model.toggle("Job")
        #expect(model.selected.last == "Job")
        model.toggle("Name")
        #expect(!model.selected.contains("Name"))
    }

    @Test func cannotCreateWithZeroCategories() async {
        let model = await makeModel()
        for category in model.selected { model.toggle(category) }
        #expect(model.selected.isEmpty)
        #expect(!model.canCreate)
    }

    @Test func moveReordersSelected() async {
        let model = await makeModel()
        model.move(from: IndexSet(integer: 0), to: 3)
        #expect(model.selected.prefix(3) == ["Animal", "Fruit", "Name"])
    }

    @Test func stopsRequiredMinimumOne() async {
        let model = await makeModel()
        model.stopsRequired = 0
        #expect(model.stopsRequired == 1)
        model.stopsRequired = -3
        #expect(model.stopsRequired == 1)
        model.stopsRequired = 3
        #expect(model.stopsRequired == 3)
    }

    @Test func settingsReflectChoices() async {
        let model = await makeModel()
        model.toggle("Job")
        model.stopsRequired = 2
        model.allowGiveUp = true
        let settings = model.settings()
        #expect(settings.categories == Array(DefaultCategories.list(for: .en).prefix(6)) + ["Job"])
        #expect(settings.stopsRequired == 2)
        #expect(settings.allowGiveUp)
    }
}
