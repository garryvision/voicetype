import Foundation

private var failures = 0

private func expectEqual(_ actual: String, _ expected: String, _ context: String) {
    guard actual != expected else { return }
    failures += 1
    print("FAIL \(context): got \(actual.debugDescription), expected \(expected.debugDescription)")
}

private func expect(_ condition: @autoclosure () -> Bool, _ context: String) {
    guard !condition() else { return }
    failures += 1
    print("FAIL \(context)")
}

let cleanerCases: [(String, String)] = [
    ("Il faut être hyper factuel. Sous-titrage Société Radio-Canada", "Il faut être hyper factuel."),
    ("Thank you. Thank you.", ""),
    ("[BLANK_AUDIO]", ""),
    ("Bonjour Sous-titres réalisés par la communauté d'Amara.org", "Bonjour"),
    ("Merci.", "Merci."),
    ("You know what, on lance YouTube demain.", "You know what, on lance YouTube demain."),
    ("Je regarde des sous-titres en anglais pour apprendre.", "Je regarde des sous-titres en anglais pour apprendre."),
    ("Ligne un\nligne  deux", "Ligne un ligne deux"),
    ("que penses-tu du Mvp? j'espère que ça marche. il ya un souci.",
     "Que penses-tu du MVP ? J'espère que ça marche. Il y a un souci."),
    ("Il ya un souci avec Ilya.", "Il y a un souci avec Ilya."),
    ("version 2.5 du site", "Version 2.5 du site"),
]

for (input, expected) in cleanerCases {
    expectEqual(TranscriptCleaner.clean(input), expected, "cleaner \(input)")
}

switch ProcessRunner.run("/bin/echo", ["bonjour"], timeout: 1) {
case .success(let output):
    expectEqual(output, "bonjour\n", "captures stdout")
case .failure(let reason):
    failures += 1
    print("FAIL captures stdout: \(reason)")
}

let started = Date()
let timeoutResult = ProcessRunner.run("/bin/sleep", ["1"], timeout: 0.05)
let elapsed = Date().timeIntervalSince(started)
switch timeoutResult {
case .success:
    failures += 1
    print("FAIL silent process should time out")
case .failure(let reason):
    expectEqual(reason, "sleep timeout", "timeout reason")
}
expect(elapsed < 0.5, "timeout returned after \(String(format: "%.2f", elapsed))s")

let comparisonDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("vt_comparison_test_\(UUID().uuidString)")
try FileManager.default.createDirectory(at: comparisonDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: comparisonDirectory) }
let sourceAudio = comparisonDirectory.appendingPathComponent("source.wav")
let fixture = Data("audio fixture".utf8)
try fixture.write(to: sourceAudio)
do {
    let first = try ComparisonAudio.makeCopy(of: sourceAudio, in: comparisonDirectory)
    let second = try ComparisonAudio.makeCopy(of: sourceAudio, in: comparisonDirectory)
    let firstData = try Data(contentsOf: first)
    let secondData = try Data(contentsOf: second)
    expect(first != second, "comparison copies must use unique paths")
    expect(firstData == fixture, "first comparison copy changed data")
    expect(secondData == fixture, "second comparison copy changed data")
} catch {
    failures += 1
    print("FAIL comparison copy: \(error)")
}

if failures == 0 {
    print("PASS \(cleanerCases.count + 5) tests")
} else {
    print("FAIL \(failures) assertions")
    exit(1)
}
