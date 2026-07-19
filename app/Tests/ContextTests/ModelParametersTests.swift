import Foundation
import Testing

@testable import Context

@Suite("Model parameters")
struct ModelParametersTests {
    @Test func modelDefaultsContainNoOverrides() {
        let options = GenerationOptions.modelDefaults

        #expect(options.thinking == .modelDefault)
        #expect(!options.hasRuntimeOverrides)
        #expect(options.stop == nil)
    }

    @Test func thinkingModesHaveStableLabels() {
        #expect(
            ThinkingMode.allCases.map(\.label)
                == ["Model Default", "On", "Off", "Low", "Medium", "High"])
    }

    @Test func optionsRoundTripThroughPreferencesJSON() throws {
        let options = GenerationOptions(
            thinking: .high,
            temperature: 0.4,
            stop: ["END"],
            topP: 0.8)
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(GenerationOptions.self, from: data) == options)
    }
}
