import Foundation
import StopCore
import StopSession
import StopSimulation
import Testing
@testable import Stop

@MainActor
struct PracticeSetupModelTests {
    let store = InMemoryGameStore()

    func makeModel(language: GameLanguage = .en) -> PracticeSetupModel {
        PracticeSetupModel(store: store, language: language)
    }

    @Test func practiceSetupDefaults() {
        let model = makeModel()
        #expect(model.botCount == 3)
        #expect(model.speed == .normal)
        #expect(model.botNames == ["Robo Ana", "Robo Ben", "Robo Cris"])
        #expect(model.maxStops == 4)
        #expect(model.setup.selected == Array(DefaultCategories.list(for: .en).prefix(6)))
        #expect(model.setup.stopsRequired == 1)
        #expect(model.canStart)
    }

    @Test func botCountStaysWithinOneToFive() {
        let model = makeModel()
        model.botCount = 0
        #expect(model.botCount == 1)
        model.botCount = 9
        #expect(model.botCount == 5)
        #expect(PracticeSetupModel.botRange == 1...5)
    }

    @Test(arguments: [
        (GameLanguage.en, ["Robo Ana", "Robo Ben", "Robo Cris", "Robo Dani", "Robo Edu"]),
        (GameLanguage.ptBR, ["Robô Ana", "Robô Beto", "Robô Cris", "Robô Dani", "Robô Edu"]),
    ])
    func botNamesAreLocalizedInFixedOrder(language: GameLanguage, names: [String]) {
        let model = makeModel(language: language)
        model.botCount = 5
        #expect(model.botNames == names)
        model.botCount = 2
        #expect(model.botNames == Array(names.prefix(2)))
    }

    @Test func botNamesAreRecognized() {
        for name in PracticeSetupModel.botNames(for: .en) + PracticeSetupModel.botNames(for: .ptBR) {
            #expect(PracticeSetupModel.isBotName(name))
            #expect(PracticeSetupModel.isBotName(name + " 2"))
        }
        #expect(!PracticeSetupModel.isBotName("Gui"))
        #expect(!PracticeSetupModel.isBotName("Roberto"))
        #expect(!PracticeSetupModel.isBotName("Robo"))
    }

    @Test func fewerBotsLowerTheStopsRequired() {
        let model = makeModel()
        model.botCount = 5
        model.setup.stopsRequired = 6
        model.botCount = 2
        #expect(model.maxStops == 3)
        #expect(model.setup.stopsRequired == 3)
    }

    @Test func cannotStartWithoutCategories() {
        let model = makeModel()
        for category in model.setup.selected { model.setup.toggle(category) }
        #expect(!model.canStart)
    }

    @Test func customCategoriesAreFlaggedForTheBotsNote() async {
        let model = makeModel()
        await model.setup.load()
        #expect(!model.hasCustomCategories)
        await model.setup.addCustom("Board games")
        #expect(model.hasCustomCategories)
    }

    @Test func practiceStartsWithTheLastHostedCategories() async {
        await store.saveLastCategories(["City", "Animal"])
        let model = makeModel()
        await model.setup.load()
        #expect(model.setup.selected == ["City", "Animal"])
        #expect(model.setup.stopsRequired == 1)
        #expect(!model.setup.allowGiveUp)
    }

    @Test func practiceHasSilentModeToo() {
        let model = makeModel()
        #expect(!model.settings().silentScoring)
        model.setup.silentScoring = true
        #expect(model.settings().silentScoring)
    }

    @Test func practiceFallsBackToDefaultsWhenFewLastCategoriesRemain() async {
        await store.saveLastCategories(["Dinosaur", "Bands", "City"])
        let model = makeModel()
        await model.setup.load()
        #expect(model.setup.selected == Array(DefaultCategories.list(for: .en).prefix(6)))
    }

    @Test func settingsComeFromTheSharedOptions() {
        let model = makeModel()
        model.setup.allowGiveUp = true
        model.setup.stopsRequired = 2
        let settings = model.settings()
        #expect(settings.categories == model.setup.selected)
        #expect(settings.stopsRequired == 2)
        #expect(settings.allowGiveUp)
    }
}
