import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public enum WindowCapturer {
    public enum CaptureError: LocalizedError {
        case windowNotFound
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .windowNotFound: return "未找到目标窗口（已取消抓拍，绝不回退全屏）"
            case .encodingFailed: return "窗口图像编码失败"
            }
        }
    }

    /// Captures ONLY the single target window identified by CGWindowID via ScreenCaptureKit.
    /// Zero full-screen fallback: if the window is minimized, closed, or missing, throws windowNotFound.
    public static func captureWindowJPEG(windowID: CGWindowID, quality: CGFloat = 0.78) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        let scale: CGFloat = 1.0
        let maxW: CGFloat = 1440
        let aspect = max(scWindow.frame.height, 1) / max(scWindow.frame.width, 1)
        let targetW = min(scWindow.frame.width * scale, maxW)
        let targetH = max(targetW * aspect, 200)
        config.width = Int(targetW)
        config.height = Int(targetH)
        config.showsCursor = false
        config.capturesAudio = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw CaptureError.encodingFailed
        }
        return jpeg
    }
}
