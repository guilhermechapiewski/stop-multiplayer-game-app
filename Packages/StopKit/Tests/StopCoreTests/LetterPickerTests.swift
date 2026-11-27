import Testing
import StopTestSupport
@testable import StopCore

@Test func picksAllLettersWithoutRepeatingThenResets() {
    var rng = SeededRNG(seed: 1); var used: [String] = []; var seen: [String] = []
    for _ in 0..<26 { let r = LetterPicker.pick(used: used, using: &rng); seen.append(r.letter); used = r.used }
    #expect(Set(seen).count == 26); #expect(Set(seen) == Set(LetterPicker.alphabet))
    let next = LetterPicker.pick(used: used, using: &rng)
    #expect(next.used == [next.letter])            // reset after exhaustion
}

@Test func rerollPutsTheCurrentLetterBackAndNeverPicksItOrAUsedOne() {
    var rng = SeededRNG(seed: 3)
    for _ in 0..<50 {
        let r = LetterPicker.reroll(current: "C", used: ["A", "B", "C"], using: &rng)
        #expect(!["A", "B", "C"].contains(r.letter))
        #expect(r.used == ["A", "B", r.letter])
    }
}

@Test func rerollWithNoLetterLeftStartsOverWithoutTheCurrentOne() {
    var rng = SeededRNG(seed: 3)
    let used = LetterPicker.alphabet.filter { $0 != "Q" } + ["Q"]
    for _ in 0..<50 {
        let r = LetterPicker.reroll(current: "Q", used: used, using: &rng)
        #expect(r.letter != "Q")
        #expect(r.used == [r.letter])
    }
}

@Test func alphabetIsFull() { #expect(LetterPicker.alphabet.count == 26); #expect(LetterPicker.alphabet.contains("K")) }

@Test func seededRNGIsDeterministic() {
    var a = SeededRNG(seed: 42); var b = SeededRNG(seed: 42)
    #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
}
