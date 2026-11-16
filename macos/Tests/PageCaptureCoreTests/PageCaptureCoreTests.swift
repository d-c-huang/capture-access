import Foundation
import XCTest
@testable import PageCaptureCore

final class PageCaptureCoreTests: XCTestCase {
    private let application = URL(fileURLWithPath: "/Applications/Example Client.app")

    func testAcceptsDifferentRoutesInsideSelectedApplication() throws {
        let page = target(id: "current", path: application.path + "/Contents/Resources/app.asar/index.html", fragment: "/any-route")
        let other = target(id: "other", path: "/Applications/Other.app/Contents/Resources/app.asar/index.html", fragment: "/main")
        XCTAssertEqual(try PageTarget.select(from: [other, page], application: application), page)
        XCTAssertThrowsError(try PageTarget.select(from: [page, page], application: application)) {
            XCTAssertEqual($0 as? PageCaptureError, .ambiguousPage)
        }
    }

    func testRejectsLookalikePathsAndNonPageTargets() throws {
        let candidates = [
            target(id: "sibling", path: application.path + "-other/Contents/Resources/app.asar/index.html", fragment: "/main"),
            try JSONDecoder().decode(PageTarget.self, from: Data(#"{"targetId":"devtools","type":"page","url":"devtools://devtools/bundled/inspector.html"}"#.utf8)),
            try JSONDecoder().decode(PageTarget.self, from: Data(#"{"targetId":"worker","type":"service_worker","url":"https://example.com"}"#.utf8))
        ]
        XCTAssertThrowsError(try PageTarget.select(from: candidates, application: application)) {
            XCTAssertEqual($0 as? PageCaptureError, .pageUnavailable)
        }
    }

    func testRemoteApplicationPageUsesOwnedPipeAndFocusedWindow() throws {
        let web = try JSONDecoder().decode(PageTarget.self, from: Data(#"{"targetId":"web","type":"page","url":"https://example.com/app"}"#.utf8))
        let local = target(id: "local", path: application.path + "/Contents/Resources/app/index.html", fragment: "")
        XCTAssertEqual(try PageTarget.select(from: [web], application: application), web)
        XCTAssertEqual(try PageTarget.selectVisible(from: [web, local], focusedIDs: ["web"], visibleIDs: ["web", "local"]), web)
        XCTAssertEqual(try PageTarget.selectVisible(from: [web, local], focusedIDs: [], visibleIDs: ["local"]), local)
        XCTAssertThrowsError(try PageTarget.selectVisible(from: [web, local], focusedIDs: [], visibleIDs: ["web", "local"])) {
            XCTAssertEqual($0 as? PageCaptureError, .ambiguousPage)
        }
    }

    func testChunkedResponseAndUnrelatedEvents() async throws {
        let peer = Peer()
        defer { peer.close() }
        let request = Task { try await peer.connection.request("Page.captureScreenshot", sessionID: "chosen-page") }
        let command = try await peer.command()
        XCTAssertEqual(command["sessionId"] as? String, "chosen-page")
        let id = try XCTUnwrap(command["id"] as? Int)
        let bytes = Data("{\"method\":\"Target.changed\"}\0{\"id\":\(id),\"result\":{\"data\":\"png-value\"}}\0".utf8)
        try peer.reply(bytes.prefix(11))
        try peer.reply(bytes.dropFirst(11))
        let result = try await request.value
        XCTAssertEqual((try JSONSerialization.jsonObject(with: result) as? [String: String])?["data"], "png-value")
    }

    func testCorrelatesResponsesArrivingInReverseOrder() async throws {
        let peer = Peer()
        defer { peer.close() }
        let first = Task { try await peer.connection.request("First") }
        let a = try await peer.command()
        let second = Task { try await peer.connection.request("Second") }
        let b = try await peer.command()
        let firstID = try XCTUnwrap(a["id"] as? Int)
        let secondID = try XCTUnwrap(b["id"] as? Int)
        try peer.reply(Data("{\"id\":\(secondID),\"result\":{\"value\":2}}\0{\"id\":\(firstID),\"result\":{\"value\":1}}\0".utf8))
        let results = try await [first.value, second.value]
        XCTAssertEqual((try JSONSerialization.jsonObject(with: results[0]) as? [String: Int])?["value"], 1)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: results[1]) as? [String: Int])?["value"], 2)
    }

    func testProtocolFailureAndDeadlineDoNotHang() async throws {
        let peer = Peer()
        defer { peer.close() }
        let request = Task { try await peer.connection.request("Rejected") }
        let command = try await peer.command()
        let id = try XCTUnwrap(command["id"] as? Int)
        try peer.reply(Data("{\"id\":\(id),\"error\":{\"code\":-32000}}\0".utf8))
        do { _ = try await request.value; XCTFail("Expected protocol rejection") }
        catch { XCTAssertEqual(error as? PageCaptureError, .rejected(-32000)) }
        do { _ = try await peer.connection.request("NoReply", timeout: 0.03); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? PageCaptureError, .timeout) }
    }

    func testCancellationClosesConnectionAndResumesPendingRequest() async throws {
        let peer = Peer()
        defer { peer.close() }
        let request = Task { try await peer.connection.request("Waiting") }
        _ = try await peer.command()
        request.cancel()
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? PageCaptureError, .connectionClosed) }
        do { _ = try await peer.connection.request("AfterCancel"); XCTFail("Expected closed pipe") }
        catch { XCTAssertEqual(error as? PageCaptureError, .connectionClosed) }
    }

    func testRepeatedScreenshotsSelectFreshTargetsAndDetach() async throws {
        let peer = Peer()
        defer { peer.close() }
        for index in 1...2 {
            let expected = Data("image-payload-\(index)".utf8)
            let capture = Task { try await PageScreenshot.capturePNG(using: peer.connection, application: application) }
            let command = try await prepareScreenshot(peer, targetID: "renderer-\(index)", sessionID: "session-\(index)")
            try peer.result(for: command, value: ["data": expected.base64EncodedString()])
            try await completeDetach(peer, sessionID: "session-\(index)")
            let image = try await capture.value
            XCTAssertEqual(image, expected)
        }
    }

    func testScreenshotFailureDetachesAndAllowsAnotherCapture() async throws {
        let peer = Peer()
        defer { peer.close() }
        let failed = Task { try await PageScreenshot.capturePNG(using: peer.connection, application: application) }
        let first = try await prepareScreenshot(peer, targetID: "old-renderer", sessionID: "failed-session")
        let id = try XCTUnwrap(first["id"] as? Int)
        try peer.reply(Data("{\"id\":\(id),\"error\":{\"code\":-32000}}\0".utf8))
        try await completeDetach(peer, sessionID: "failed-session")
        do { _ = try await failed.value; XCTFail("Expected screenshot rejection") }
        catch { XCTAssertEqual(error as? PageCaptureError, .rejected(-32000)) }

        let retried = Task { try await PageScreenshot.capturePNG(using: peer.connection, application: application) }
        let second = try await prepareScreenshot(peer, targetID: "new-renderer", sessionID: "retry-session")
        let expected = Data("recovered-image".utf8)
        try peer.result(for: second, value: ["data": expected.base64EncodedString()])
        try await completeDetach(peer, sessionID: "retry-session")
        let image = try await retried.value
        XCTAssertEqual(image, expected)
    }

    func testFailedBackgroundAttachStillCapturesUniquelyFocusedPage() async throws {
        let peer = Peer()
        defer { peer.close() }
        let expected = Data("focused-window-image".utf8)
        let capture = Task { try await PageScreenshot.capturePNG(using: peer.connection, application: application) }
        try await sendTwoTargets(peer)

        let staleAttach = try await peer.command()
        XCTAssertEqual(staleAttach["method"] as? String, "Target.attachToTarget")
        XCTAssertEqual((staleAttach["params"] as? [String: Any])?["targetId"] as? String, "background")
        try peer.reject(staleAttach, code: -32000)
        try await completeProbe(peer, targetID: "foreground", sessionID: "focus-probe", focused: true, visible: true)

        let attach = try await peer.command()
        XCTAssertEqual(attach["method"] as? String, "Target.attachToTarget")
        XCTAssertEqual((attach["params"] as? [String: Any])?["targetId"] as? String, "foreground")
        try peer.result(for: attach, value: ["sessionId": "image-session"])
        let screenshot = try await peer.command()
        XCTAssertEqual(screenshot["method"] as? String, "Page.captureScreenshot")
        XCTAssertEqual(screenshot["sessionId"] as? String, "image-session")
        try peer.result(for: screenshot, value: ["data": expected.base64EncodedString()])
        try await completeDetach(peer, sessionID: "image-session")
        let png = try await capture.value
        XCTAssertEqual(png, expected)
    }

    func testFailedBackgroundProbeDoesNotFallBackToMerelyVisiblePage() async throws {
        let peer = Peer()
        defer { peer.close() }
        let capture = Task { try await PageScreenshot.capturePNG(using: peer.connection, application: application) }
        try await sendTwoTargets(peer)

        let attach = try await peer.command()
        XCTAssertEqual(attach["method"] as? String, "Target.attachToTarget")
        XCTAssertEqual((attach["params"] as? [String: Any])?["targetId"] as? String, "background")
        try peer.result(for: attach, value: ["sessionId": "failed-probe"])
        let evaluate = try await peer.command()
        XCTAssertEqual(evaluate["method"] as? String, "Runtime.evaluate")
        try peer.reject(evaluate, code: -32000)
        // Even rejected probes must detach their temporary session.
        try await completeDetach(peer, sessionID: "failed-probe")
        try await completeProbe(peer, targetID: "foreground", sessionID: "visible-probe", focused: false, visible: true)

        do { _ = try await capture.value; XCTFail("Expected uncertain focus to preserve the probe error") }
        catch { XCTAssertEqual(error as? PageCaptureError, .rejected(-32000)) }
    }

    private func sendTwoTargets(_ peer: Peer) async throws {
        let command = try await peer.command()
        XCTAssertEqual(command["method"] as? String, "Target.getTargets")
        let pages = ["background", "foreground"].map { id in
            target(id: id, path: application.path + "/Contents/Resources/app.asar/index.html", fragment: "/" + id)
        }
        try peer.result(for: command, value: ["targetInfos": pages.map { ["targetId": $0.targetId, "type": $0.type, "url": $0.url] }])
    }

    private func completeProbe(_ peer: Peer, targetID: String, sessionID: String, focused: Bool, visible: Bool) async throws {
        let attach = try await peer.command()
        XCTAssertEqual(attach["method"] as? String, "Target.attachToTarget")
        XCTAssertEqual((attach["params"] as? [String: Any])?["targetId"] as? String, targetID)
        try peer.result(for: attach, value: ["sessionId": sessionID])
        let evaluate = try await peer.command()
        XCTAssertEqual(evaluate["method"] as? String, "Runtime.evaluate")
        XCTAssertEqual(evaluate["sessionId"] as? String, sessionID)
        try peer.result(for: evaluate, value: ["result": ["value": ["focused": focused, "visible": visible]]])
        try await completeDetach(peer, sessionID: sessionID)
    }

    func testLateTimedOutResponseDoesNotPolluteReusedConnection() async throws {
        let peer = Peer()
        defer { peer.close() }
        let expired = Task { try await peer.connection.request("Expired", timeout: 0.03) }
        let oldCommand = try await peer.command()
        do { _ = try await expired.value; XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? PageCaptureError, .timeout) }

        let current = Task { try await peer.connection.request("Current") }
        let newCommand = try await peer.command()
        try peer.result(for: oldCommand, value: ["value": "stale"])
        try peer.result(for: newCommand, value: ["value": "fresh"])
        let response = try await current.value
        XCTAssertEqual((try JSONSerialization.jsonObject(with: response) as? [String: String])?["value"], "fresh")
    }

    private func prepareScreenshot(_ peer: Peer, targetID: String, sessionID: String) async throws -> [String: Any] {
        let page = target(id: targetID, path: application.path + "/Contents/Resources/app.asar/index.html", fragment: "/main/chat")
        let list = try await peer.command()
        XCTAssertEqual(list["method"] as? String, "Target.getTargets")
        try peer.result(for: list, value: ["targetInfos": [["targetId": page.targetId, "type": page.type, "url": page.url]]])

        let attach = try await peer.command()
        XCTAssertEqual(attach["method"] as? String, "Target.attachToTarget")
        let parameters = try XCTUnwrap(attach["params"] as? [String: Any])
        XCTAssertEqual(parameters["targetId"] as? String, targetID)
        XCTAssertEqual(parameters["flatten"] as? Bool, true)
        try peer.result(for: attach, value: ["sessionId": sessionID])

        let capture = try await peer.command()
        XCTAssertEqual(capture["method"] as? String, "Page.captureScreenshot")
        XCTAssertEqual(capture["sessionId"] as? String, sessionID)
        return capture
    }

    private func completeDetach(_ peer: Peer, sessionID: String) async throws {
        let detach = try await peer.command()
        XCTAssertEqual(detach["method"] as? String, "Target.detachFromTarget")
        XCTAssertNil(detach["sessionId"], "Detach must be routed to the browser")
        XCTAssertEqual((detach["params"] as? [String: String])?["sessionId"], sessionID)
        try peer.result(for: detach, value: [:])
    }

    private func target(id: String, path: String, fragment: String) -> PageTarget {
        var location = URLComponents(url: URL(fileURLWithPath: path), resolvingAgainstBaseURL: false)!
        location.fragment = fragment
        let bytes = try! JSONSerialization.data(withJSONObject: ["targetId": id, "type": "page", "url": location.string!])
        return try! JSONDecoder().decode(PageTarget.self, from: bytes)
    }
}

private final class Peer: @unchecked Sendable {
    let input = Pipe(), output = Pipe()
    let connection: DebuggerPipe
    private let commandLock = NSLock()
    private var commandBuffer = Data()
    init() {
        connection = DebuggerPipe(reader: output.fileHandleForReading, writer: input.fileHandleForWriting)
    }
    func command() async throws -> [String: Any] {
        try await Task.detached { try self.readCommand() }.value
    }
    private func readCommand() throws -> [String: Any] {
        commandLock.lock()
        defer { commandLock.unlock() }
        while true {
            if let end = commandBuffer.firstIndex(of: 0) {
                let bytes = Data(commandBuffer[..<end])
                commandBuffer.removeSubrange(...end)
                return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            }
            let chunk = input.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw PageCaptureError.connectionClosed }
            commandBuffer.append(chunk)
        }
    }
    func result(for command: [String: Any], value: [String: Any]) throws {
        let id = try XCTUnwrap(command["id"] as? Int)
        var bytes = try JSONSerialization.data(withJSONObject: ["id": id, "result": value])
        bytes.append(0)
        try reply(bytes)
    }
    func reject(_ command: [String: Any], code: Int) throws {
        let id = try XCTUnwrap(command["id"] as? Int)
        var bytes = try JSONSerialization.data(withJSONObject: ["id": id, "error": ["code": code]])
        bytes.append(0)
        try reply(bytes)
    }
    func reply<T: DataProtocol>(_ bytes: T) throws { try output.fileHandleForWriting.write(contentsOf: Data(bytes)) }
    func close() {
        connection.close()
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
    }
}
