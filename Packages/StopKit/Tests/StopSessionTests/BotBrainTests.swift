import Foundation
import StopCore
@testable import StopSimulation
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
        #expect(bank.rawCategories == Set(DefaultCategories.list(for: language)))
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
            let answers = brain.plan(categories: categories + ["Dinosaur"], letter: letter).answers
            #expect(answers.count == categories.count + 1)
            for answer in answers {
                #expect(fold(answer).hasPrefix(fold(letter)), "\(letter): \(answer)")
            }
        }
    }

    @Test(arguments: [(BotSpeed.fast, 0.75), (.normal, 0.55), (.relaxed, 0.35)])
    func finishRateFollowsSpeed(_ speed: BotSpeed, _ expected: Double) {
        #expect(speed.finishProbability == expected)
        var seeds = SeededRNG(seed: 5)
        var finished = 0
        for _ in 0..<400 {
            var brain = BotBrain(language: .en, speed: speed, seed: seeds.next())
            if brain.plan(categories: DefaultCategories.list(for: .en), letter: "M").finishes { finished += 1 }
        }
        let rate = Double(finished) / 400
        #expect(abs(rate - expected) < 0.08, "\(speed) finish rate \(rate)")
    }

    @Test func guessesAreMarkedSoTheBotScoresThemZero() {
        var seeds = SeededRNG(seed: 3)
        var finishers = 0, strugglers = 0
        for letter in Self.letters {
            var brain = BotBrain(language: .ptBR, speed: .normal, seed: seeds.next())
            let categories = ["Dinossauro", "Animal", "Time de futebol"]
            let plan = brain.plan(categories: categories, letter: letter)
            let unknown = Set(categories.indices.filter {
                BotAnswerBank.load(.ptBR).candidates(category: categories[$0], letter: letter).isEmpty
            })
            // Custom categories (and letters the bank lacks) are always guesses, and so is every late answer.
            #expect(plan.guessed == unknown.union(plan.late), "\(letter)")
            #expect(plan.guessed.isSuperset(of: [0, 2]))
            if plan.finishes { finishers += 1 } else { strugglers += 1 }
        }
        #expect(finishers > 0 && strugglers > 0)
    }

    @Test func strugglersLeaveOneOrTwoBlanksAndAlwaysCustomOnes() {
        var seeds = SeededRNG(seed: 99)
        var strugglers = 0, late = 0
        for _ in 0..<400 {
            var brain = BotBrain(language: .en, speed: .relaxed, seed: seeds.next())
            let plan = brain.plan(categories: DefaultCategories.list(for: .en), letter: "B")
            guard !plan.finishes else { continue }
            strugglers += 1
            late += plan.late.count
        }
        let mean = Double(late) / Double(strugglers)
        #expect(mean >= 1 && mean <= 2.5, "mean blanks \(mean)")
        var brain = BotBrain(language: .ptBR, speed: .relaxed, seed: 1)
        for _ in 0..<20 {
            let plan = brain.plan(categories: ["Dinossauro", "Animal"], letter: "C")
            if !plan.finishes { #expect(plan.late.contains(0)) }
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
        #expect(a.plan(categories: categories, letter: "M") == b.plan(categories: categories, letter: "M"))
        #expect(a.stopDelay() == b.stopDelay())
    }

    /// Three bots of one game (shared seed, indices 0–2) answer a category with ≥3 candidates differently.
    @Test(arguments: languages)
    func botsOfOneGameSpreadTheirAnswers(_ language: GameLanguage) {
        let categories = DefaultCategories.list(for: language)
        let bank = BotAnswerBank.load(language)
        var seeds = SeededRNG(seed: 23)
        var checked = 0
        for round in 1...3 {
            for letter in Self.letters {
                let shared = seeds.next()
                let plans = (0..<3).map { index in
                    var brain = BotBrain(language: language, speed: .normal, seed: seeds.next(), index: index,
                                         sharedSeed: shared)
                    return brain.plan(categories: categories, letter: letter, round: round)
                }
                for (c, category) in categories.enumerated()
                where bank.candidates(category: category, letter: letter).count >= 3 {
                    let answers = plans.map { $0.answers[c] }
                    #expect(Set(answers).count == 3, "\(category) \(letter): \(answers)")
                    checked += 1
                }
            }
        }
        #expect(checked > 100)
    }

    /// A custom category falls back to any bank word for the letter; bots spread across that pool too.
    @Test(arguments: languages)
    func botsSpreadGuessesForCustomCategories(_ language: GameLanguage) {
        let bank = BotAnswerBank.load(language)
        var seeds = SeededRNG(seed: 31)
        var checked = 0
        for letter in Self.letters where bank.anyCandidates(letter: letter).count >= 3 {
            let shared = seeds.next()
            let answers = (0..<3).map { index in
                var brain = BotBrain(language: language, speed: .normal, seed: seeds.next(), index: index,
                                     sharedSeed: shared)
                return brain.plan(categories: ["Dinosaur"], letter: letter, round: 1).answers[0]
            }
            #expect(Set(answers).count == 3, "\(letter): \(answers)")
            checked += 1
        }
        #expect(checked > 15)
    }

    @Test func spreadIsDeterministicAndVariesByRound() {
        let categories = DefaultCategories.list(for: .ptBR)
        func plan(_ index: Int, round: Int) -> BotRoundPlan {
            var brain = BotBrain(language: .ptBR, speed: .normal, seed: 11, index: index, sharedSeed: 99)
            return brain.plan(categories: categories, letter: "M", round: round)
        }
        #expect(plan(1, round: 1) == plan(1, round: 1))
        #expect(plan(1, round: 1).answers != plan(0, round: 1).answers)
        #expect((2...6).contains { plan(0, round: $0).answers != plan(0, round: 1).answers })
    }

    @Test func selfScoreUniqueDuplicateBlank() {
        #expect(BotBrain.selfScore(mine: "Uva", others: ["uva "]) == 5)
        #expect(BotBrain.selfScore(mine: "Ávila", others: ["avila"]) == 5)
        #expect(BotBrain.selfScore(mine: "Uva", others: ["Urso", ""]) == 10)
        #expect(BotBrain.selfScore(mine: "Uva", others: []) == 10)
        #expect(BotBrain.selfScore(mine: "  ", others: ["  "]) == 0)
    }
}
