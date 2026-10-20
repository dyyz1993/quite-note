import Foundation
import XCTest
@testable import QuiteNote

private final class MagpieURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class MagpieCatalogServiceTests: XCTestCase {
    private var service: MagpieCatalogService!

    override func setUp() {
        super.setUp()
        MagpieURLProtocol.handler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MagpieURLProtocol.self]
        service = MagpieCatalogService(session: URLSession(configuration: configuration), timeout: 1)
    }

    override func tearDown() {
        MagpieURLProtocol.handler = nil
        service = nil
        super.tearDown()
    }

    func testLoadsCatalogAndSortsModels() {
        MagpieURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/api/hello") == true {
                return (200, Data(#"{"name":"magpie","version":"1"}"#.utf8))
            }
            let json = #"""
            {"data":[{"id":"zcode/GLM-5.3","display_name":"GLM-5.3","owned_by":"zcode","modalities":{"input":["text"]}},{"id":"glm/glm-5.3-flash","display_name":"GLM-5.3-Flash","modalities":{"input":["text","image"]}}]}
            """#
            return (200, Data(json.utf8))
        }
        let expectation = expectation(description: "catalog")
        service.load(baseURL: "http://127.0.0.1:3425") { result in
            switch result {
            case .success((let info, let models)):
                XCTAssertEqual(info, MagpieGatewayInfo(name: "magpie", version: "1"))
                XCTAssertEqual(models.map(\.id), ["zcode/GLM-5.3", "glm/glm-5.3-flash"])
                XCTAssertEqual(models[0].displayName, "GLM-5.3")
                XCTAssertFalse(models[0].supportsImageInput)
                XCTAssertTrue(models[1].supportsImageInput)
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testRejectsNonMagpieService() {
        MagpieURLProtocol.handler = { _ in
            (200, Data(#"{"name":"other","version":"1"}"#.utf8))
        }
        let expectation = expectation(description: "not magpie")
        service.load(baseURL: "http://127.0.0.1:3425") { result in
            if case .failure(.notMagpie) = result {
                // Expected.
            } else {
                XCTFail("Expected notMagpie, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testReportsEmptyCatalog() {
        MagpieURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/api/hello") == true
                ? (200, Data(#"{"name":"magpie"}"#.utf8))
                : (200, Data(#"{"data":[]}"#.utf8))
        }
        let expectation = expectation(description: "empty")
        service.load(baseURL: "http://127.0.0.1:3425") { result in
            if case .failure(.emptyCatalog) = result {
                // Expected.
            } else {
                XCTFail("Expected emptyCatalog, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testReportsHTTPFailure() {
        MagpieURLProtocol.handler = { _ in (500, Data()) }
        let expectation = expectation(description: "failure")
        service.load(baseURL: "http://127.0.0.1:3425") { result in
            if case .failure(.http(500)) = result {
                // Expected.
            } else {
                XCTFail("Expected http(500), got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testRejectsInvalidURL() {
        let expectation = expectation(description: "invalid URL")
        service.load(baseURL: "http://127.0.0.1:3425/#bad url") { result in
            if case .failure(.invalidURL) = result {
                // Expected.
            } else {
                XCTFail("Expected invalidURL, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testReportsUnreachableGatewayWithActionableMessage() {
        let expectation = expectation(description: "unreachable gateway")
        service.load(baseURL: "http://127.0.0.1:1") { result in
            switch result {
            case .failure(.unreachable):
                // Expected: UI can guide the user to install, start, or check Magpie.
                break
            default:
                XCTFail("Expected unreachable, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testMissingModalitiesDefaultsToTextOnlyModel() {
        MagpieURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/api/hello") == true
                ? (200, Data(#"{"name":"magpie"}"#.utf8))
                : (200, Data(#"{"data":[{"id":"glm/glm-4.5-air","display_name":"GLM-4.5-Air"}]}"#.utf8))
        }
        let expectation = expectation(description: "text-only fallback")
        service.load(baseURL: "http://127.0.0.1:3425") { result in
            if case .success((_, let models)) = result {
                XCTAssertEqual(models.map(\.id), ["glm/glm-4.5-air"])
                XCTAssertFalse(models[0].supportsImageInput)
            } else {
                XCTFail("Expected catalog, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }
}
