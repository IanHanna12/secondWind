import XCTest
@testable import SecondWindApplication
@testable import SecondWindCore

final class CleanupReviewTests: XCTestCase {
    func testSafeFindingExplainsRegenerationAndRecovery() {
        let finding = makeFinding(risk: .safe, action: .cleanup, confidence: .exact)

        let candidate = CleanupReviewBuilder().build(findings: [finding]).first

        XCTAssertEqual(candidate?.reason.origin, "Built-in cache rule")
        XCTAssertEqual(candidate?.reason.explanation, "This cache is recreated when needed.")
        XCTAssertEqual(candidate?.regeneration, .recreatedAutomatically)
        XCTAssertEqual(candidate?.recovery, .available)
    }

    func testReviewRequiredFindingNeverPromisesRegeneration() {
        let finding = makeFinding(risk: .reviewRequired, action: .cleanup, confidence: .needsUserReview)

        let candidate = CleanupReviewBuilder().build(findings: [finding]).first

        XCTAssertEqual(candidate?.regeneration, .notGuaranteed)
        XCTAssertEqual(candidate?.recovery, .available)
    }

    func testProtectedFindingCannotOfferRecovery() {
        let finding = makeFinding(risk: .protected, action: .none, confidence: .needsUserReview)

        let candidate = CleanupReviewBuilder().build(findings: [finding]).first

        XCTAssertEqual(candidate?.regeneration, .notApplicable)
        XCTAssertEqual(candidate?.recovery, .unavailable)
    }

    private func makeFinding(risk: Risk, action: SupportedAction, confidence: MatchConfidence) -> Finding {
        Finding(
            ruleID: "fixture",
            ruleVersion: 1,
            title: "Fixture cache",
            path: "/fixture-home/Library/Caches/com.example.fixture",
            byteSize: 1_024,
            category: .caches,
            origin: "Built-in cache rule",
            explanation: "This cache is recreated when needed.",
            risk: risk,
            supportedAction: action,
            confidence: confidence
        )
    }
}
