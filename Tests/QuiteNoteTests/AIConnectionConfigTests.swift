import XCTest
@testable import QuiteNote

final class AIConnectionConfigTests: XCTestCase {
    func testNewInstallationDefaultsToMagpie() {
        XCTAssertEqual(
            AIConnectionResolver.resolvedKind(storedKind: nil, hasLegacyAIConfig: false),
            .magpie
        )
    }

    func testLegacyConfigurationMigratesToCustomOpenAI() {
        XCTAssertEqual(
            AIConnectionResolver.resolvedKind(storedKind: nil, hasLegacyAIConfig: true),
            .customOpenAI
        )
    }

    func testMagpieUsesGatewayTokenAndSeparateBaseURL() {
        let snapshot = AIConnectionResolver.snapshot(
            kind: .magpie,
            customBaseURL: "https://custom.example/v1",
            customModel: "custom-model",
            customAPIKey: "custom-key",
            magpieBaseURL: "http://127.0.0.1:3425"
        )
        XCTAssertEqual(snapshot.kind, .magpie)
        XCTAssertEqual(snapshot.baseURL, "http://127.0.0.1:3425")
        XCTAssertEqual(snapshot.bearerToken, "magpie-quite-note")
    }

    func testChatRequestUsesCurrentSnapshot() throws {
        let snapshot = AIConnectionSnapshot(
            kind: .magpie,
            baseURL: "http://127.0.0.1:3425",
            model: "glm/glm-5.3-flash",
            bearerToken: "magpie-quite-note"
        )
        let request = try AIConnectionResolver.chatURLRequest(
            snapshot: snapshot,
            systemPrompt: "system",
            userPrompt: "user",
            temperature: 0.3,
            maxTokens: 100,
            requiresJSON: true
        )
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:3425/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer magpie-quite-note")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "glm/glm-5.3-flash")
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
    }

    func testConnectionsKeepIndependentModels() {
        let magpie = AIConnectionResolver.snapshot(
            kind: .magpie,
            customBaseURL: "https://custom.example/v1",
            customModel: "custom-model",
            customAPIKey: "custom-key",
            magpieBaseURL: "http://127.0.0.1:3425"
        )
        let custom = AIConnectionResolver.snapshot(
            kind: .customOpenAI,
            customBaseURL: "https://custom.example/v1",
            customModel: "custom-model",
            customAPIKey: "custom-key",
            magpieBaseURL: magpie.baseURL
        )
        XCTAssertEqual(custom.model, "custom-model")
        XCTAssertNotEqual(magpie.bearerToken, custom.bearerToken)
    }

    func testMissingModelPreventsRequests() {
        let snapshot = AIConnectionSnapshot(
            kind: .magpie,
            baseURL: "http://127.0.0.1:3425/v1",
            model: " ",
            bearerToken: "magpie-quite-note"
        )
        XCTAssertFalse(snapshot.isReady)
    }

    func testModelSearchMatchesIDAndDisplayName() {
        let model = MagpieModel(id: "glm/glm-5.3-flash", displayName: "GLM-5.3-Flash", owner: nil, supportsImageInput: true)
        XCTAssertTrue(model.matches("glm"))
        XCTAssertTrue(model.matches("Flash"))
        XCTAssertFalse(model.matches("gemini"))
    }

    func testMultimodalChatRequestEncodesImageURLAndKeepsJSONMode() throws {
        let snapshot = AIConnectionSnapshot(
            kind: .magpie,
            baseURL: "http://127.0.0.1:3425",
            model: "group/auto-gpt-6-luna",
            bearerToken: "magpie-quite-note"
        )
        let image = AIImageData(mimeType: "image/png", base64: "aW1hZ2UtYml0cw==")
        let request = try AIConnectionResolver.multimodalChatURLRequest(
            snapshot: snapshot,
            systemPrompt: "system",
            userPrompt: "user",
            images: [image],
            temperature: 0.3,
            maxTokens: 100,
            requiresJSON: true
        )

        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:3425/chat/completions")
        XCTAssertEqual(request.timeoutInterval, 90)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(user["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        let imagePart = try XCTUnwrap(content.last)
        XCTAssertEqual(imagePart["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,aW1hZ2UtYml0cw==")
    }
}

