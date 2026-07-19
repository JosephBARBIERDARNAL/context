import ContextCore
import XCTest

@testable import Context

final class ModelParametersTests: XCTestCase {
    func testModelDefaultsContainNoOverrides() {
        let options = GenerationOptions.modelDefaults

        XCTAssertEqual(options.thinking, .modelDefault)
        XCTAssertNil(options.temperature)
        XCTAssertNil(options.numCtx)
        XCTAssertNil(options.numPredict)
        XCTAssertNil(options.seed)
        XCTAssertNil(options.stop)
        XCTAssertNil(options.topK)
        XCTAssertNil(options.topP)
        XCTAssertNil(options.minP)
        XCTAssertNil(options.repeatLastN)
        XCTAssertNil(options.repeatPenalty)
        XCTAssertNil(options.tfsZ)
        XCTAssertNil(options.mirostat)
        XCTAssertNil(options.mirostatEta)
        XCTAssertNil(options.mirostatTau)
    }

    func testThinkingModesHaveStableLabels() {
        XCTAssertEqual(
            ThinkingMode.allCases.map(\.label),
            ["Model Default", "On", "Off", "Low", "Medium", "High"])
    }
}
