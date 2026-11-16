import Foundation

/// Null-delimited CDP messages over a private child-process pipe. All protocol
/// state and continuations belong to one serial queue; cancellation closes it.
public final class DebuggerPipe: @unchecked Sendable {
    private struct Pending {
        let continuation: CheckedContinuation<Data, Error>
        let deadline: DispatchWorkItem
    }
    private let reader: FileHandle
    private let writer: FileHandle
    private let queue = DispatchQueue(label: "local.captureaccess.page-protocol")
    private var buffer = Data()
    private var pending: [Int: Pending] = [:]
    private var nextID = 1
    private var closed = false
    private let readerLock = NSLock()
    private var readerClosed = false

    public init(reader: FileHandle, writer: FileHandle) {
        self.reader = reader
        self.writer = writer
        reader.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            // read(upToCount:) tries to fill the requested length on a pipe on
            // macOS. availableData returns the current chunk without waiting
            // for an entire screenshot-sized buffer or EOF.
            self.readerLock.lock()
            guard !self.readerClosed else { self.readerLock.unlock(); return }
            let chunk = handle.availableData
            self.readerLock.unlock()
            self.queue.async {
                if chunk.isEmpty { self.closeLocked() }
                else { self.receive(chunk) }
            }
        }
    }

    public func request(_ method: String, parameters: Data = Data("{}".utf8),
                        sessionID: String? = nil, timeout: TimeInterval = 5) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !self.closed else {
                        continuation.resume(throwing: PageCaptureError.connectionClosed)
                        return
                    }
                    let id = self.nextID
                    self.nextID += 1
                    do {
                        var message: [String: Any] = ["id": id, "method": method,
                            "params": try JSONSerialization.jsonObject(with: parameters)]
                        if let sessionID { message["sessionId"] = sessionID }
                        var bytes = try JSONSerialization.data(withJSONObject: message)
                        bytes.append(0)
                        let deadline = DispatchWorkItem { [weak self] in
                            self?.finish(id, result: .failure(PageCaptureError.timeout))
                        }
                        self.pending[id] = Pending(continuation: continuation, deadline: deadline)
                        self.queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
                        do { try self.writer.write(contentsOf: bytes) }
                        catch { self.closeLocked() }
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.close() }
    }

    public func close() { queue.async { self.closeLocked() } }

    private func receive(_ chunk: Data) {
        guard !closed else { return }
        buffer.append(chunk)
        guard buffer.count <= 128 * 1024 * 1024 else { closeLocked(); return }
        while let end = buffer.firstIndex(of: 0) {
            let bytes = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            do {
                guard let message = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                    throw PageCaptureError.malformedMessage
                }
                guard let id = message["id"] as? Int, pending[id] != nil else { continue }
                if let error = message["error"] as? [String: Any] {
                    finish(id, result: .failure(PageCaptureError.rejected(error["code"] as? Int ?? 0)))
                } else if let result = message["result"] as? [String: Any] {
                    finish(id, result: .success(try JSONSerialization.data(withJSONObject: result)))
                } else {
                    finish(id, result: .failure(PageCaptureError.malformedMessage))
                }
            } catch { closeLocked(); return }
        }
    }

    private func finish(_ id: Int, result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.deadline.cancel()
        request.continuation.resume(with: result)
    }

    private func closeLocked() {
        guard !closed else { return }
        closed = true
        reader.readabilityHandler = nil
        readerLock.lock()
        readerClosed = true
        try? reader.close()
        readerLock.unlock()
        try? writer.close()
        for id in Array(pending.keys) { finish(id, result: .failure(PageCaptureError.connectionClosed)) }
        buffer.removeAll()
    }
}
