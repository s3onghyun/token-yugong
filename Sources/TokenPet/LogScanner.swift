import Foundation

// MARK: - Local Claude Code log scanner (no network, no credentials)

/// Incrementally reads ~/.claude/projects/**/*.jsonl. Only assistant lines with message.usage
/// are decoded: tokens for the mountain, output tokens for the live pace; and the limit rejections.
final class LogScanner {
    struct Event { let time: Date; let tokens: Int; let output: Int }

    let root: URL
    private var offsets: [String: UInt64] = [:]
    private var seen = Set<String>()
    private(set) var events: [Event] = []
    /// The newest logged limit hit per window (5-hour, weekly).
    private(set) var hits: [Bool: Limits.Hit] = [:]
    private(set) var lastScanSeconds: Double = 0
    private(set) var bytesRead: UInt64 = 0

    init(root: URL) { self.root = root }

    private static let assistantNeedle = Array(#""type":"assistant""#.utf8)
    private static let usageNeedle = Array(#""usage":{"#.utf8)
    private static let hitNeedle = Array(#""usage_limit_reached""#.utf8)

    func scan(now: Date = Date()) {
        let started = Date()
        let cutoff = now.addingTimeInterval(-7 * 86400)
        let fm = FileManager.default
        guard let it = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in it where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = v.contentModificationDate, mtime >= cutoff, let size = v.fileSize else { continue }
            var off = offsets[url.path] ?? 0
            if UInt64(size) < off { off = 0 }
            if UInt64(size) == off { continue }
            offsets[url.path] = read(url, from: off)
        }
        events.removeAll { $0.time < cutoff }
        hits = hits.filter { $0.value.time >= cutoff }
        events.sort { $0.time < $1.time }
        lastScanSeconds = Date().timeIntervalSince(started)
    }

    /// Returns the offset just past the last complete line consumed.
    private func read(_ url: URL, from start: UInt64) -> UInt64 {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return start }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: start) } catch { return start }
        var consumed = start
        var carry = Data()
        while true {
            let more: Bool = autoreleasepool {
            guard let chunk = try? fh.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
            bytesRead += UInt64(chunk.count)
            carry.append(chunk)
            var lineStart = carry.startIndex
            carry.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                let base = buf.baseAddress!
                var i = 0
                let n = buf.count
                while i < n {
                    guard let nl = memchr(base + i, 0x0A, n - i) else { break }
                    let end = base.distance(to: UnsafeRawPointer(nl))
                    handleLine(UnsafeRawBufferPointer(start: base + i, count: end - i))
                    i = end + 1
                }
                lineStart = carry.startIndex + i
            }
            consumed += UInt64(lineStart - carry.startIndex)
            carry = carry.subdata(in: lineStart..<carry.endIndex)
            return true
            }
            if !more { break }
        }
        return consumed
    }

    private static func contains(_ line: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard line.count >= needle.count, let base = line.baseAddress else { return false }
        return needle.withUnsafeBytes { memmem(base, line.count, $0.baseAddress!, needle.count) != nil }
    }

    private func handleLine(_ line: UnsafeRawBufferPointer) {
        guard Self.contains(line, Self.assistantNeedle), Self.contains(line, Self.usageNeedle),
              let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return }
        if Self.contains(line, Self.hitNeedle), let h = Limits.hit(obj), h.time > (hits[h.week]?.time ?? .distantPast) { hits[h.week] = h }
        guard (obj["isApiErrorMessage"] as? Bool) != true,
              let ts = obj["timestamp"] as? String, let time = Limits.iso.date(from: ts),
              let msg = obj["message"] as? [String: Any], let usage = msg["usage"] as? [String: Any] else { return }
        let key = (msg["id"] as? String ?? "") + "|" + (obj["requestId"] as? String ?? ts)
        guard seen.insert(key).inserted else { return }
        let output = usage["output_tokens"] as? Int ?? 0
        let tokens = (usage["input_tokens"] as? Int ?? 0) + output + (usage["cache_creation_input_tokens"] as? Int ?? 0)
        events.append(Event(time: time, tokens: tokens, output: output))
    }
}
