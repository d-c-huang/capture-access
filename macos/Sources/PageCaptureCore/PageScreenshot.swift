import Foundation

/// A single screenshot on a reusable browser connection. Select the current
/// page again each time because the client may replace its renderer between shots.
public enum PageScreenshot {
    private struct TargetList: Decodable { let targetInfos: [PageTarget] }
    private struct Attachment: Decodable { let sessionId: String }
    private struct Screenshot: Decodable { let data: String }

    public static func capturePNG(using connection: DebuggerPipe, application: URL) async throws -> Data {
        let targets = try await connection.request("Target.getTargets", timeout: 0.5)
        let list = try JSONDecoder().decode(TargetList.self, from: targets)
        let candidates = list.targetInfos.filter { $0.belongsToMainPage(in: application) }
        let target = try await selectTarget(candidates, using: connection)
        let parameters = try JSONSerialization.data(withJSONObject: ["targetId": target.targetId, "flatten": true])
        let response = try await connection.request("Target.attachToTarget", parameters: parameters)
        let attachment = try JSONDecoder().decode(Attachment.self, from: response)
        guard !attachment.sessionId.isEmpty else { throw PageCaptureError.malformedMessage }

        do {
            let options = Data(#"{"format":"png","fromSurface":true,"captureBeyondViewport":false}"#.utf8)
            let result = try await connection.request("Page.captureScreenshot", parameters: options,
                                                      sessionID: attachment.sessionId, timeout: 10)
            let screenshot = try JSONDecoder().decode(Screenshot.self, from: result)
            guard let png = Data(base64Encoded: screenshot.data), !png.isEmpty else {
                throw PageCaptureError.invalidImage
            }
            await detach(attachment.sessionId, using: connection)
            return png
        } catch {
            await detach(attachment.sessionId, using: connection)
            throw error
        }
    }

    private static func selectTarget(_ candidates: [PageTarget], using connection: DebuggerPipe) async throws -> PageTarget {
        if candidates.count <= 1 {
            guard let target = candidates.first else { throw PageCaptureError.pageUnavailable }
            return target
        }
        var focused: Set<String> = [], visible: Set<String> = []
        var firstProbeError: Error?
        for target in candidates {
            try Task.checkCancellation()
            var attachedSession: String?
            do {
                let parameters = try JSONSerialization.data(withJSONObject: ["targetId": target.targetId, "flatten": true])
                let attached = try await connection.request("Target.attachToTarget", parameters: parameters, timeout: 1)
                let attachment = try JSONDecoder().decode(Attachment.self, from: attached)
                guard !attachment.sessionId.isEmpty else { throw PageCaptureError.malformedMessage }
                attachedSession = attachment.sessionId
                let query = Data(#"{"expression":"({focused:document.hasFocus(),visible:document.visibilityState==='visible'})","returnByValue":true}"#.utf8)
                let response = try await connection.request("Runtime.evaluate", parameters: query,
                                                            sessionID: attachment.sessionId, timeout: 1)
                let decoded = try JSONSerialization.jsonObject(with: response) as? [String: Any]
                guard let value = (decoded?["result"] as? [String: Any])?["value"] as? [String: Bool],
                      let isFocused = value["focused"], let isVisible = value["visible"] else {
                    throw PageCaptureError.malformedMessage
                }
                if isFocused { focused.insert(target.targetId) }
                if isVisible { visible.insert(target.targetId) }
            } catch {
                if let attachedSession { await detach(attachedSession, using: connection) }
                if Task.isCancelled || (error as? PageCaptureError) == .connectionClosed { throw error }
                // A renderer may close between listing and probing it. Other
                // targets can still provide an unambiguous focused window.
                if firstProbeError == nil { firstProbeError = error }
                continue
            }
            if let attachedSession { await detach(attachedSession, using: connection) }
        }
        try Task.checkCancellation()
        let confirmedFocus = candidates.filter { focused.contains($0.targetId) }
        if confirmedFocus.count == 1 { return confirmedFocus[0] }
        // An unprobed page might be the focused one. Never substitute a merely
        // visible page when any probe failed, because that can pick a wrong window.
        if let firstProbeError { throw firstProbeError }
        return try PageTarget.selectVisible(from: candidates, focusedIDs: focused, visibleIDs: visible)
    }

    private static func detach(_ sessionID: String, using connection: DebuggerPipe) async {
        // The browser-level command takes sessionId in params, not in the
        // flattened routing field. A vanished target must not discard a good image.
        guard let parameters = try? JSONSerialization.data(withJSONObject: ["sessionId": sessionID]) else { return }
        _ = try? await connection.request("Target.detachFromTarget", parameters: parameters, timeout: 1)
    }
}
