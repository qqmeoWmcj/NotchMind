import AppKit
import Foundation

@MainActor
public final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let onURLDetected: @MainActor (String) -> Void

    public init(onURLDetected: @escaping @MainActor (String) -> Void) {
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.onURLDetected = onURLDetected
    }

    public func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.count < 1024
        else { return }

        guard URLCanonicalizer.isSupportedWebURL(text) else { return }
        // Only auto-trigger on video/knowledge URLs (Bilibili, YouTube, GitHub, arXiv, HuggingFace)
        let lower = text.lowercased()
        let autoHosts = ["bilibili.com", "b23.tv", "youtube.com", "youtu.be", "github.com", "arxiv.org", "huggingface.co"]
        guard autoHosts.contains(where: { lower.contains($0) }) else { return }
        onURLDetected(text)
    }
}
