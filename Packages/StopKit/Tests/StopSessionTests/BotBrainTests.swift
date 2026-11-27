import Foundation
import StopCore
import StopSimulation
import StopTestSupport
import Testing

struct BotBrainTests {
    private static let languages: [GameLanguage] = [.en, .ptBR]
    private static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    private func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    @Test(arguments: languages)
    func answerBankCoversEveryDefaultCategory(_ language: GameLanguage) {
        let bank = BotAnswerBank.load(language)
        for category in DefaultCategories.list(for: language) {
            let filled = Self.letters.filter { !bank.candidates(category: category, letter: $0).isEmpty }
            #expect(filled.count >= 18, "\(category) has only \(filled.count) letters")
            for letter in Self.letters {
                #expect(bank.candidates(category: category, letter: letter).count <= 4, "\(category) \(letter)")
            }
        }
    }

    @Test func answerBankMatchesCategoryIgnoringCaseAndAccents() {
        let pt = BotAnswerBank.load(.ptBR)
        let exact = pt.candidates(category: "Profissão", letter: "M")
        #expect(!exact.isEmpty)
        #expect(pt.candidates(category: "profissao", letter: "M") == exact)
        #expect(pt.candidates(category: "  PROFISSÃO ", letter: "m") == exact)
        let en = BotAnswerBank.load(.en)
        #expect(!en.candidates(category: "Movie/TV show", letter: "T").isEmpty)
        #expect(en.candidates(category: "movie/tv SHOW", letter: "T") == en.candidates(category: "Movie/TV show", letter: "T"))
        #expect(en.candidates(category: "Dinosaur", letter: "T").isEmpty)
    }

    @Test(arguments: languages)
    func answersStartWithTheLetter(_ language: GameLanguage) {
        let categories = DefaultCategories.list(for: language)
        let bank = BotAnswerBank.load(language)
        for category in categories {
            for letter in Self.letters {
                for answer in bank.candidates(category: category, letter: letter) {
                    #expect(fold(answer).hasPrefix(fold(letter)), "\(category) \(letter): \(answer)")
                    #expect(answer == answer.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        var seeds = SeededRNG(seed: 17)
        for letter in Self.letters {
            var brain = BotBrain(language: language, speed: .normal, seed: seeds.next())
            let answers = brain.answers(categories: categories, letter: letter)
            #expect(answers.count == categories.count)
            for answer in answers where !AnswerText.isBlank(answer) {
                #expect(fold(answer).hasPrefix(fold(letter)), "\(letter): \(answer)")
            }
        }
    }

    @Test func blankRateIsAboutFifteenPercent() {
        var seeds = SeededRNG(seed: 99)
        var blanks = 0, total = 0
        for _ in 0..<200 {
            var brain = BotBrain(language: .en, speed: .normal, seed: seeds.next())
            let answers = brain.answers(categories: ["Animal", "Fruit", "Color", "Food", "Name"], letter: "B")
            blanks += answers.filter(AnswerText.isBlank).count
            total += answers.count
        }
        let rate = Double(blanks) / Double(total)
        #expect(rate > 0.10 && rate < 0.20, "blank rate \(rate)")
    }

    @Test func botLeavesCustomCategoriesBlank() {
        var seeds = SeededRNG(seed: 3)
        for _ in 0..<20 {
            var brain = BotBrain(language: .ptBR, speed: .fast, seed: seeds.next())
            let answers = brain.answers(categories: ["Dinossauro", "Time de futebol"], letter: "C")
            #expect(answers == ["", ""])
        }
    }

    @Test func stopDelayWithinSpeedWindow() {
        let windows: [(BotSpeed, ClosedRange<Duration>)] = [
            (.relaxed, .seconds(60) ... .seconds(90)),
            (.normal, .seconds(35) ... .seconds(60)),
            (.fast, .seconds(20) ... .seconds(35)),
        ]
        var seeds = SeededRNG(seed: 42)
        for (speed, window) in windows {
            #expect(speed.stopWindow == window)
            var brain = BotBrain(language: .en, speed: speed, seed: seeds.next())
            var samples: Set<Duration> = []
            for _ in 0..<100 {
                let delay = brain.stopDelay()
                #expect(window.contains(delay), "\(speed): \(delay)")
                samples.insert(delay)
            }
            #expect(samples.count > 50, "delays should vary")
        }
    }

    @Test func sameSeedIsDeterministic() {
        var a = BotBrain(language: .ptBR, speed: .normal, seed: 7)
        var b = BotBrain(language: .ptBR, speed: .normal, seed: 7)
        let categories = DefaultCategories.list(for: .ptBR)
        #expect(a.answers(categories: categories, letter: "M") == b.answers(categories: categories, letter: "M"))
        #expect(a.stopDelay() == b.stopDelay())
    }

    @Test func selfScoreUniqueDuplicateBlank() {
        #expect(BotBrain.selfScore(mine: "Uva", others: ["uva "]) == 5)
        #expect(BotBrain.selfScore(mine: "Ávila", others: ["avila"]) == 5)
        #expect(BotBrain.selfScore(mine: "Uva", others: ["Urso", ""]) == 10)
        #expect(BotBrain.selfScore(mine: "Uva", others: []) == 10)
        #expect(BotBrain.selfScore(mine: "  ", others: ["  "]) == 0)
    }
}
