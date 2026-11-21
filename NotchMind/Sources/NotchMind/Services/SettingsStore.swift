import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    @Published public var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }
    @Published public var modelName: String {
        didSet { defaults.set(modelName, forKey: Keys.modelName) }
    }
    @Published public var vaultPath: String {
        didSet { defaults.set(vaultPath, forKey: Keys.vaultPath) }
    }
    @Published public var dataPath: String {
        didSet { defaults.set(dataPath, forKey: Keys.dataPath) }
    }
    @Published public var capsuleStyle: CapsuleStyle {
        didSet { defaults.set(capsuleStyle.rawValue, forKey: Keys.capsuleStyle) }
    }
    @Published public var glassStylePreset: GlassStylePreset {
        didSet { defaults.set(glassStylePreset.rawValue, forKey: Keys.glassStylePreset) }
    }
    @Published public var glassTintIntensity: Double {
        didSet {
            defaults.set(glassTintIntensity, forKey: Keys.glassTintIntensity)
            let derived = GlassToneTier.from(intensity: glassTintIntensity)
            if glassToneTier != derived {
                glassToneTier = derived
            }
        }
    }
    @Published public var glassToneTier: GlassToneTier {
        didSet {
            defaults.set(glassToneTier.rawValue, forKey: Keys.glassToneTier)
        }
    }
    @Published public var externalDisplayPlacement: ExternalDisplayPlacement {
        didSet { defaults.set(externalDisplayPlacement.rawValue, forKey: Keys.externalDisplayPlacement) }
    }
    @Published public var externalDisplayCustomXRatio: Double {
        didSet { defaults.set(externalDisplayCustomXRatio, forKey: Keys.externalDisplayCustomXRatio) }
    }
    @Published public var externalDisplayCustomYOffset: Double {
        didSet { defaults.set(externalDisplayCustomYOffset, forKey: Keys.externalDisplayCustomYOffset) }
    }
    @Published public var allowScreenRecording: Bool {
        didSet { defaults.set(allowScreenRecording, forKey: Keys.allowScreenRecording) }
    }
    @Published public var autoCompanionEnabled: Bool {
        didSet { defaults.set(autoCompanionEnabled, forKey: Keys.autoCompanion) }
    }
    @Published public var clipboardWatchEnabled: Bool {
        didSet { defaults.set(clipboardWatchEnabled, forKey: Keys.clipboardWatch) }
    }
    @Published public var captureIntervalSeconds: Double {
        didSet { defaults.set(captureIntervalSeconds, forKey: Keys.captureInterval) }
    }
    @Published public var allowedSiteKeywords: [String] {
        didSet { defaults.set(allowedSiteKeywords, forKey: Keys.allowedSites) }
    }
    @Published public var monitoringMode: MonitoringMode {
        didSet {
            defaults.set(monitoringMode.rawValue, forKey: Keys.monitoringMode)
            autoCompanionEnabled = (monitoringMode != .manual)
        }
    }
    @Published public var focusGoalTitle: String {
        didSet { defaults.set(focusGoalTitle, forKey: Keys.focusGoalTitle) }
    }
    @Published public var focusKeywords: [String] {
        didSet { defaults.set(focusKeywords, forKey: Keys.focusKeywords) }
    }
    @Published public var projectContext: String {
        didSet { defaults.set(projectContext, forKey: Keys.projectContext) }
    }
    @Published public var projectFeedbackPath: String {
        didSet { defaults.set(projectFeedbackPath, forKey: Keys.projectFeedbackPath) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiKey = "notchmind.geminiApiKey"
        static let modelName = "notchmind.geminiModel"
        static let vaultPath = "notchmind.vaultPath"
        static let dataPath = "notchmind.dataPath"
        static let capsuleStyle = "notchmind.capsuleStyle"
        static let glassStylePreset = "notchmind.glassStylePreset"
        static let glassTintIntensity = "notchmind.glassTintIntensity"
        static let glassToneTier = "notchmind.glassToneTier"
        static let externalDisplayPlacement = "notchmind.externalDisplayPlacement"
        static let externalDisplayCustomXRatio = "notchmind.externalDisplayCustomXRatio"
        static let externalDisplayCustomYOffset = "notchmind.externalDisplayCustomYOffset"
        static let allowScreenRecording = "notchmind.allowScreenRecording"
        static let autoCompanion = "notchmind.autoCompanion"
        static let clipboardWatch = "notchmind.clipboardWatch"
        static let captureInterval = "notchmind.captureInterval"
        static let allowedSites = "notchmind.allowedSites"
        static let monitoringMode = "notchmind.monitoringMode"
        static let focusGoalTitle = "notchmind.focusGoalTitle"
        static let focusKeywords = "notchmind.focusKeywords"
        static let projectContext = "notchmind.projectContext"
        static let projectFeedbackPath = "notchmind.projectFeedbackPath"
    }

    public init() {
        let projectRoot = Self.discoverProjectRoot()
        let env = Self.parseEnvFile(at: projectRoot.appendingPathComponent(".env"))

        let storedKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.apiKey = storedKey.isEmpty ? (env["GEMINI_API_KEY"] ?? "") : storedKey

        let storedModel = defaults.string(forKey: Keys.modelName) ?? ""
        let rawModel = storedModel.isEmpty ? (env["GEMINI_MODEL"] ?? "gemini-3.8-flash") : storedModel
        self.modelName = Self.resolveModelAlias(rawModel)

        let envVault = env["OBSIDIAN_VAULT_PATH"] ?? ""
        let defaultVault = envVault.isEmpty
            ? projectRoot.appendingPathComponent("vault").path
            : envVault
        let storedVault = defaults.string(forKey: Keys.vaultPath) ?? ""
        self.vaultPath = storedVault.isEmpty ? defaultVault : storedVault

        let defaultData = projectRoot.appendingPathComponent("data").path
        let storedData = defaults.string(forKey: Keys.dataPath) ?? ""
        self.dataPath = storedData.isEmpty ? defaultData : storedData

        let rawStyle = defaults.string(forKey: Keys.capsuleStyle) ?? CapsuleStyle.liquidGlass.rawValue
        self.capsuleStyle = CapsuleStyle(rawValue: rawStyle) ?? .liquidGlass

        let rawPreset = defaults.string(forKey: Keys.glassStylePreset) ?? GlassStylePreset.regular.rawValue
        self.glassStylePreset = GlassStylePreset(rawValue: rawPreset) ?? .regular

        let initialIntensity: Double
        if defaults.object(forKey: Keys.glassTintIntensity) == nil {
            initialIntensity = 0.50
        } else {
            initialIntensity = min(max(defaults.double(forKey: Keys.glassTintIntensity), 0.0), 1.0)
        }
        self.glassTintIntensity = initialIntensity

        let rawTier = defaults.string(forKey: Keys.glassToneTier)
        if let rawTier, let tier = GlassToneTier(rawValue: rawTier) {
            self.glassToneTier = tier
        } else {
            self.glassToneTier = GlassToneTier.from(intensity: initialIntensity)
        }

        let rawPlacement = defaults.string(forKey: Keys.externalDisplayPlacement) ?? ExternalDisplayPlacement.topCenter.rawValue
        self.externalDisplayPlacement = ExternalDisplayPlacement(rawValue: rawPlacement) ?? .topCenter

        self.externalDisplayCustomXRatio = defaults.object(forKey: Keys.externalDisplayCustomXRatio) != nil
            ? min(max(defaults.double(forKey: Keys.externalDisplayCustomXRatio), 0.0), 1.0)
            : 0.5

        self.externalDisplayCustomYOffset = defaults.object(forKey: Keys.externalDisplayCustomYOffset) != nil
            ? max(0.0, defaults.double(forKey: Keys.externalDisplayCustomYOffset))
            : 0.0

        if defaults.object(forKey: Keys.allowScreenRecording) == nil {
            self.allowScreenRecording = false
        } else {
            self.allowScreenRecording = defaults.bool(forKey: Keys.allowScreenRecording)
        }

        if defaults.object(forKey: Keys.autoCompanion) == nil {
            self.autoCompanionEnabled = true
        } else {
            self.autoCompanionEnabled = defaults.bool(forKey: Keys.autoCompanion)
        }

        if defaults.object(forKey: Keys.clipboardWatch) == nil {
            self.clipboardWatchEnabled = true
        } else {
            self.clipboardWatchEnabled = defaults.bool(forKey: Keys.clipboardWatch)
        }

        let interval = defaults.double(forKey: Keys.captureInterval)
        self.captureIntervalSeconds = interval >= 5 ? interval : 18

        let savedSites = defaults.stringArray(forKey: Keys.allowedSites)
        self.allowedSiteKeywords = (savedSites?.isEmpty == false)
            ? savedSites!
            : ["bilibili", "哔哩哔哩", "youtube"]

        let rawMode = defaults.string(forKey: Keys.monitoringMode) ?? MonitoringMode.manual.rawValue
        let mode = MonitoringMode(rawValue: rawMode) ?? .manual
        self.monitoringMode = mode
        self.autoCompanionEnabled = (mode != .manual)

        self.focusGoalTitle = defaults.string(forKey: Keys.focusGoalTitle) ?? ""
        self.focusKeywords = defaults.stringArray(forKey: Keys.focusKeywords) ?? []
        self.projectContext = defaults.string(forKey: Keys.projectContext) ?? ""
        self.projectFeedbackPath = defaults.string(forKey: Keys.projectFeedbackPath) ?? ""
    }

    public var currentFocusGoal: FocusGoal {
        FocusGoal(
            title: focusGoalTitle,
            keywords: focusKeywords,
            projectContext: projectContext,
            feedbackFilePath: projectFeedbackPath
        )
    }

    public func applyGlassToneTier(_ tier: GlassToneTier) {
        self.glassToneTier = tier
        self.glassTintIntensity = tier.targetIntensity
        switch tier {
        case .clear:
            self.glassStylePreset = .clear
        case .regular:
            self.glassStylePreset = .regular
        case .tinted:
            self.glassStylePreset = .tintedDark
        }
    }

    public var vaultURL: URL { URL(fileURLWithPath: vaultPath, isDirectory: true) }
    public var dataURL: URL { URL(fileURLWithPath: dataPath, isDirectory: true) }

    public static func resolveModelAlias(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "3.8f": return "gemini-3.8-flash"
        case "4h": return "gemini-4-hydrogen"
        case "4a": return "gemini-4-argon"
        default: return trimmed.isEmpty ? "gemini-3.8-flash" : trimmed
        }
    }

    private static func discoverProjectRoot() -> URL {
        let candidates: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ai-hotspot-creator"),
        ]
        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".env").path)
                || FileManager.default.fileExists(atPath: dir.appendingPathComponent("vault").path)
            {
                return dir
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ai-hotspot-creator")
    }

    public static func parseEnvFile(at url: URL) -> [String: String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }
            map[key] = value
        }
        return map
    }
}
