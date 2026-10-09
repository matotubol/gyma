import XCTest
@testable import GymaCore

final class WatchWeightInputTests: XCTestCase {
    func testParsesTrimmedWholeAndFractionalWeightsWithEitherDecimalSeparator() {
        for (text, expected) in [("0", 0.0), ("1000", 1000.0), (" 42.5\n", 42.5), ("42,5", 42.5),
                                 (".5", 0.5), (",5", 0.5), ("00.25", 0.25), ("40.", 40.0)] {
            XCTAssertEqual(WatchWeightInput.parse(text), expected, text)
        }
        XCTAssertEqual(WatchWeightInput.parse("1,000"), 1, "A single separator is decimal, never thousands grouping.")
    }

    func testRejectsInvalidAmbiguousAndOutOfRangeInput() {
        for text in ["", " \n", ".", ",", "-1", "-0", "+10", "1000.1", "1001", "42 kg", "42kg", "kg42",
                     "1,000.5", "1.000,5", "1,000,000", "1.000.000", "1 000", "1\u{00A0}000", "4\n2",
                     "4e1", "1E-1", "NaN", "nan", "Infinity", "∞", "４２", "42..5", "42,,5"] {
            XCTAssertNil(WatchWeightInput.parse(text), text)
        }
        XCTAssertNil(WatchWeightInput.parse("0." + String(repeating: "0", count: 400) + "1"))
    }

    func testFormatterRoundTripsExistingFractionalWeightsWithoutGroupingOrExponents() throws {
        for weight in [0.0, 1.0, 42.5, 42.125, 42.12345678901234, 999.9999999999999, 1000.0,
                       0.0000001, 1e-100, Double.leastNormalMagnitude, Double.leastNonzeroMagnitude] {
            let text = WatchWeightInput.text(for: weight)
            XCTAssertFalse(text.contains("e"), text)
            XCTAssertFalse(text.contains(","), text)
            XCTAssertFalse(text.contains(" "), text)
            XCTAssertEqual(try XCTUnwrap(WatchWeightInput.parse(text), text), weight, text)
        }
        XCTAssertEqual(WatchWeightInput.text(for: 40), "40")
        XCTAssertEqual(WatchWeightInput.text(for: 0), "0")
    }

    func testInvalidExistingValueDoesNotProduceConfirmableText() {
        for weight in [-1.0, 1000.01, Double.infinity, -Double.infinity, Double.nan] {
            let text = WatchWeightInput.text(for: weight)
            XCTAssertEqual(text, "")
            XCTAssertNil(WatchWeightInput.parse(text))
        }
    }
}
