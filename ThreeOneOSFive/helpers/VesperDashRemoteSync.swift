import Combine
import Foundation
import SwiftUI

enum VesperStringVault {
    static let novaAPIBaseURL: String = {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "NOVA_API_BASE_URL") as? String,
              let url = URL(string: configured), url.scheme?.lowercased() == "https", url.host != nil,
              !url.host!.hasSuffix(".example") else { return "" }
        return configured.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }()
    static var vesperDashClientSessionURL: String { novaAPIBaseURL }
    static var vesperDashPatchesURL: String { novaAPIBaseURL }
    static var vesperDashSettingsURL: String { novaAPIBaseURL }
    private static func decode(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.map { $0 ^ 0x5A }, as: UTF8.self)
    }
    static let vesperChannelURL = decode([50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 12, 63, 41, 42, 63, 40, 31, 34, 46, 40, 63, 52, 59, 54])
    static let nullzthURL = decode([50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 20, 47, 54, 54, 0, 46, 50])
    static let nullzthChannelURL = decode([50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 113, 111, 18, 18, 59, 0, 47, 40, 18, 10, 27, 99, 50, 21, 13, 23, 98])
    static let tiktokURL = decode([50, 46, 46, 42, 41, 96, 117, 117, 45, 45, 45, 116, 46, 51, 49, 46, 53, 49, 116, 57, 53, 55, 117, 26, 63, 54, 5, 48, 63, 60, 40, 35, 5, 5, 5, 101, 5, 40, 103, 107, 124, 5, 46, 103, 0, 14, 119, 99, 99, 49, 109, 43, 25, 35, 42, 31, 51, 108, 45])
    static let telegramBaseURL = decode([46, 46, 42, 42, 117, 117, 46, 55, 117])
}
struct VesperDashManifest: Decodable {
    let version: Int
    let global_paused: Bool
    let patches: [RemotePatch]
    let all_patches: [RemotePatch]?
    let package_passwords: [String]?
}

struct VesperReleasePolicy: Decodable {
    let latestBuild: Int
    let minimumBuild: Int
    let downloadURL: URL
    let updateMessage: String

    private enum CodingKeys: String, CodingKey {
        case latestBuild = "latest_build"
        case minimumBuild = "minimum_build"
        case downloadURL = "download_url"
        case updateMessage = "update_message"
    }

    var displayUpdateMessage: String {
        let value = updateMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "IPA UPDATED, PLEASE DOWNLOAD NEW VERSION" : String(value.prefix(240))
    }
}

struct RemotePatch: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: String?
    let game: String
    let bundle_id: String
    let target_path: String
    let target_paths: [String]?
    let filename: String
    let sha256: String
    let version: String
    let download_url: String
    let image_url: String?
    let status_text: String?
    let sort_order: Int?
    let enabled: Bool
    let paused: Bool

    var normalizedCategory: String {
        let value = (category ?? "aim").lowercased()
        if value == "hologram" { return "weapons" }
        return ["aim", "esp", "body", "weapons", "skin"].contains(value) ? value : "aim"
    }

    var normalizedStatus: String {
        let value = status_text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "NO STATUS" : String(value.prefix(180))
    }

    var displayStatusText: String {
        let value = status_text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(value.prefix(180))
    }

    var normalizedOrder: Int {
        sort_order ?? 1000
    }

    var normalizedTargetPaths: [String] {
        let values = (target_paths ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return values.isEmpty ? [target_path] : values
    }
}

struct ManifestHTTPError: LocalizedError {
    let statusCode: Int
    var errorDescription: String? { "API returned HTTP \(statusCode)" }
}

enum VesperDashRemoteSync {
    static let manifestURL = URL(string: VesperStringVault.vesperDashPatchesURL + "/patches")!

    static func fetchReleasePolicy() async throws -> VesperReleasePolicy {
        var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)!
        components.path = (URL(string: VesperStringVault.novaAPIBaseURL)?.path ?? "/api") + "/release-policy"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let policy = try JSONDecoder().decode(VesperReleasePolicy.self, from: data)
        guard policy.latestBuild >= 1,
              policy.minimumBuild >= 0,
              policy.minimumBuild <= policy.latestBuild,
              policy.downloadURL.scheme?.lowercased() == "https",
              policy.downloadURL.user == nil,
              policy.downloadURL.password == nil else {
            throw URLError(.cannotParseResponse)
        }
        return policy
    }

    static func downloadPackageFile(
        for remote: RemotePatch,
        sessionToken: String,
        using session: URLSession,
        into directory: URL
    ) async throws -> URL {
        guard let url = validDownloadURL(for: remote) else {
            throw PatchPackageError.remoteImportFailed
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let (temporaryURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw PatchPackageError.remoteImportFailed
        }
        let destination = directory.appendingPathComponent("\(UUID().uuidString).download")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func fetchManifest(sessionToken: String) async throws -> VesperDashManifest {
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            if (400..<500).contains(http.statusCode) && http.statusCode != 408 && http.statusCode != 429 {
                throw ManifestHTTPError(statusCode: http.statusCode)
            }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(VesperDashManifest.self, from: data)
    }

    static func validDownloadURL(for patch: RemotePatch) -> URL? {
        guard let url = URL(string: patch.download_url, relativeTo: manifestURL)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == manifestURL.host?.lowercased(),
              url.user == nil, url.password == nil,
              patch.bundle_id == "com.dts.freefireth" || patch.bundle_id == "com.dts.freefiremax",
              patch.filename.lowercased().hasSuffix(".3105") else { return nil }
        return url
    }

    static func validImageURL(for patch: RemotePatch) -> URL? {
        guard let value = patch.image_url,
              let url = URL(string: value, relativeTo: manifestURL)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == manifestURL.host?.lowercased(),
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}


struct VesperAppSettings: Decodable {
    private enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case developerName = "developer_name"
        case developerSubtitle = "developer_subtitle"
        case channelName = "channel_name"
        case channelHandle = "channel_handle"
        case channelURL = "channel_url"
        case ownerName = "owner_name"
        case ownerHandle = "owner_handle"
        case ownerURL = "owner_url"
        case footerText = "footer_text"
    }

    let appName: String
    let developerName: String
    let developerSubtitle: String
    let channelName: String
    let channelHandle: String
    let channelURL: String
    let ownerName: String
    let ownerHandle: String
    let ownerURL: String
    let footerText: String

    static let fallback = VesperAppSettings(
        appName: "NOVA",
        developerName: "Yagami",
        developerSubtitle: "NOVA Developer",
        channelName: "NOVA Official Channel",
        channelHandle: "Discord",
        channelURL: "https://discord.gg/VqkjH4pJv",
        ownerName: "NOVA Owner",
        ownerHandle: "@Rybkx",
        ownerURL: "https://discord.gg/VqkjH4pJv",
        footerText: "NOVA • READY"
    )

    init(appName: String, developerName: String, developerSubtitle: String, channelName: String, channelHandle: String, channelURL: String, ownerName: String, ownerHandle: String, ownerURL: String, footerText: String) {
        self.appName = appName; self.developerName = developerName; self.developerSubtitle = developerSubtitle
        self.channelName = channelName; self.channelHandle = channelHandle; self.channelURL = channelURL
        self.ownerName = ownerName; self.ownerHandle = ownerHandle; self.ownerURL = ownerURL; self.footerText = footerText
    }

    init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        let f = VesperAppSettings.fallback
        func currentValue(_ key: CodingKeys, fallback: String) throws -> String {
            let value = try d.decodeIfPresent(String.self, forKey: key) ?? fallback
            return value.lowercased().contains("vesper") ? fallback : value
        }
        appName = try currentValue(.appName, fallback: f.appName)
        developerName = try currentValue(.developerName, fallback: f.developerName)
        developerSubtitle = try currentValue(.developerSubtitle, fallback: f.developerSubtitle)
        channelName = try currentValue(.channelName, fallback: f.channelName)
        channelHandle = try currentValue(.channelHandle, fallback: f.channelHandle)
        channelURL = try currentValue(.channelURL, fallback: f.channelURL)
        ownerName = try currentValue(.ownerName, fallback: f.ownerName)
        ownerHandle = try currentValue(.ownerHandle, fallback: f.ownerHandle)
        ownerURL = try currentValue(.ownerURL, fallback: f.ownerURL)
        footerText = try currentValue(.footerText, fallback: f.footerText)
    }
}

extension VesperDashRemoteSync {
    static let settingsURL = URL(string: VesperStringVault.vesperDashSettingsURL + "/settings")!

    static func fetchAppSettings() async throws -> VesperAppSettings {
        let (data, response) = try await URLSession.shared.data(from: settingsURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(VesperAppSettings.self, from: data)
    }
}


struct NOVARemoteDocument: Decodable, Identifiable, Sendable {
    let id: Int
    let filename: String
    let sizeBytes: Int
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case filename
        case sizeBytes = "size_bytes"
        case updatedAt = "updated_at"
    }
}

private struct NOVARemoteDocumentManifest: Decodable {
    let version: Int
    let files: [NOVARemoteDocument]
}

struct NOVAStoredDocument: Identifiable, Equatable, Sendable {
    let id: Int
    let filename: String
    let sizeBytes: Int
    let updatedAt: String?

    var isRecentlyUploaded: Bool {
        guard let updatedAt else { return false }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt)
        guard let date else { return false }
        let age = Date().timeIntervalSince(date)
        return age >= 0 && age < 7 * 24 * 60 * 60
    }
}

@MainActor
final class NOVARemoteDocumentSyncStore: ObservableObject {
    @Published private(set) var files: [NOVAStoredDocument] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var hasError = false
    @Published private(set) var requiresActivation = false
    @Published private(set) var lastSyncedAt: Date?

    private let maximumFileBytes = 25 * 1024 * 1024
    private let managedDirectoryName = "NOVAReceivedFiles"
    private let fileManager = FileManager.default

    func sync(sessionToken: String?) async {
        guard !isSyncing else { return }
        guard let sessionToken, !sessionToken.isEmpty else {
            requiresActivation = true
            return
        }

        isSyncing = true
        hasError = false
        requiresActivation = false
        defer { isSyncing = false }

        do {
            let manifest = try await fetchManifest(sessionToken: sessionToken)
            guard manifest.version == 1 else { throw URLError(.cannotParseResponse) }
            let directory = try managedDirectory(createIfNeeded: true)
            var expectedNames = Set<String>()
            var storedFiles: [NOVAStoredDocument] = []

            for remote in manifest.files {
                guard remote.id > 0,
                      remote.sizeBytes > 0,
                      remote.sizeBytes <= maximumFileBytes,
                      Self.isSafeFilename(remote.filename) else {
                    throw URLError(.cannotParseResponse)
                }
                let localName = "\(remote.id)__\(remote.filename)"
                guard expectedNames.insert(localName).inserted else {
                    throw URLError(.cannotParseResponse)
                }
                let destination = directory.appendingPathComponent(localName, isDirectory: false)
                let cachedFileIsValid = try hasValidCachedFile(at: destination, expectedSize: remote.sizeBytes)
                if !cachedFileIsValid {
                    let data = try await download(remote, sessionToken: sessionToken)
                    guard data.count == remote.sizeBytes, data.count <= maximumFileBytes else {
                        throw URLError(.cannotParseResponse)
                    }
                    try data.write(to: destination, options: .atomic)
                }
                storedFiles.append(NOVAStoredDocument(
                    id: remote.id,
                    filename: remote.filename,
                    sizeBytes: remote.sizeBytes,
                    updatedAt: remote.updatedAt
                ))
            }

            try removeStaleManagedFiles(in: directory, retaining: expectedNames)
            files = storedFiles.sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
            lastSyncedAt = Date()
            hasError = false
            requiresActivation = false
        } catch let error as ManifestHTTPError {
            hasError = true
            requiresActivation = error.statusCode == 401 || error.statusCode == 403
        } catch {
            hasError = true
        }
    }

    func clearManagedFiles() {
        files = []
        hasError = false
        requiresActivation = true
        lastSyncedAt = nil
        guard let directory = try? managedDirectory(createIfNeeded: false) else { return }
        try? removeStaleManagedFiles(in: directory, retaining: [])
    }

    private func fetchManifest(sessionToken: String) async throws -> NOVARemoteDocumentManifest {
        var request = URLRequest(url: try documentsURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw ManifestHTTPError(statusCode: http.statusCode) }
        return try JSONDecoder().decode(NOVARemoteDocumentManifest.self, from: data)
    }

    private func download(_ remote: NOVARemoteDocument, sessionToken: String) async throws -> Data {
        var request = URLRequest(url: try documentDownloadURL(id: remote.id))
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw ManifestHTTPError(statusCode: http.statusCode) }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().split(separator: ";", maxSplits: 1).first
        guard contentType == "application/octet-stream" else { throw URLError(.cannotParseResponse) }
        return data
    }

    private func documentsURL() throws -> URL {
        try apiBaseURL()
            .appendingPathComponent("client", isDirectory: true)
            .appendingPathComponent("documents", isDirectory: false)
    }

    private func documentDownloadURL(id: Int) throws -> URL {
        try apiBaseURL()
            .appendingPathComponent("client", isDirectory: true)
            .appendingPathComponent("documents", isDirectory: true)
            .appendingPathComponent(String(id), isDirectory: true)
            .appendingPathComponent("download", isDirectory: false)
    }

    private func apiBaseURL() throws -> URL {
        guard let url = URL(string: VesperStringVault.novaAPIBaseURL),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            throw URLError(.badURL)
        }
        return url
    }

    private func managedDirectory(createIfNeeded: Bool) throws -> URL {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw URLError(.resourceUnavailable)
        }
        let root = applicationSupport.standardizedFileURL
        let directory = root.appendingPathComponent(managedDirectoryName, isDirectory: true).standardizedFileURL
        guard directory.deletingLastPathComponent() == root else { throw URLError(.badURL) }
        if createIfNeeded {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else if !fileManager.fileExists(atPath: directory.path) {
            throw URLError(.fileDoesNotExist)
        }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw URLError(.cannotWriteToFile) }
        return directory
    }

    private func hasValidCachedFile(at url: URL, expectedSize: Int) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory != true, values.isSymbolicLink != true else { throw URLError(.cannotWriteToFile) }
        return values.fileSize == expectedSize
    }

    private func removeStaleManagedFiles(in directory: URL, retaining names: Set<String>) throws {
        let rootPath = directory.standardizedFileURL.path + "/"
        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        for child in children {
            let childPath = child.standardizedFileURL.path
            guard childPath.hasPrefix(rootPath), Self.isManagedFilename(child.lastPathComponent) else { continue }
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory != true, values.isSymbolicLink != true else { continue }
            if !names.contains(child.lastPathComponent) { try fileManager.removeItem(at: child) }
        }
    }

    private static func isManagedFilename(_ name: String) -> Bool {
        guard let separator = name.range(of: "__") else { return false }
        let identifier = name[..<separator.lowerBound]
        let filename = name[separator.upperBound...]
        return !filename.isEmpty && identifier.allSatisfy { $0.isNumber } && Int(identifier) != nil
    }

    private static func isSafeFilename(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && name != "."
            && name != ".."
            && name.lengthOfBytes(using: .utf8) <= 255
            && !name.contains("/")
            && !name.contains("\\")
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

@MainActor
struct NOVAReceivedDocumentsCard: View {
    let shouldSyncOnReentry: Bool

    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var licenseManager: LicenseManager
    @StateObject private var store = NOVARemoteDocumentSyncStore()
    @State private var hiddenDocumentIDs = Set<Int>()
    @State private var showHiddenDocuments = false
    @State private var pollingEnabled = false

    private var hiddenCount: Int {
        store.files.filter { hiddenDocumentIDs.contains($0.id) }.count
    }

    private var displayedFiles: [NOVAStoredDocument] {
        showHiddenDocuments ? store.files : store.files.filter { !hiddenDocumentIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appLanguage.text("nova.files.title"))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.paper)
                    Text(appLanguage.text("nova.files.subtitle"))
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.paper.opacity(0.55))
                }
                Spacer(minLength: 4)
                Button(action: syncNow) {
                    Label(appLanguage.text(store.isSyncing ? "nova.files.syncing" : "nova.files.sync"), systemImage: "arrow.clockwise")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isSyncing || !licenseManager.isActive)
            }

            if let lastSyncedAt = store.lastSyncedAt {
                Text(appLanguage.text("nova.files.last_sync", lastSyncedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.paper.opacity(0.52))
            }

            if hiddenCount > 0 {
                Button {
                    showHiddenDocuments.toggle()
                } label: {
                    Label(
                        "\(appLanguage.text(showHiddenDocuments ? "nova.files.hide_hidden" : "nova.files.show_hidden")) (\(hiddenCount))",
                        systemImage: showHiddenDocuments ? "eye.slash" : "eye"
                    )
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            if !licenseManager.isActive || store.requiresActivation {
                Label(appLanguage.text("nova.files.auth_required"), systemImage: "key.fill")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryAccent)
            } else if store.hasError {
                Label(appLanguage.text("nova.files.sync_failed"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryAccent)
            } else if store.files.isEmpty && !store.isSyncing {
                Text(appLanguage.text("nova.files.none"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.paper.opacity(0.72))
                Text(appLanguage.text("nova.files.none_detail"))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.paper.opacity(0.52))
            } else if !store.files.isEmpty && displayedFiles.isEmpty {
                Text(appLanguage.text("nova.files.all_hidden"))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.paper.opacity(0.55))
            }

            ForEach(displayedFiles) { file in
                documentRow(file)
                if file.id != displayedFiles.last?.id {
                    Divider().overlay(AppTheme.paper.opacity(0.1))
                }
            }

            Text(appLanguage.text("nova.files.passive_notice"))
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.paper.opacity(0.5))
                .padding(.top, 2)
            Text(appLanguage.text("nova.files.maintenance_note"))
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.paper.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.referenceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.secondaryAccent.opacity(0.25), lineWidth: 1))
        .onChange(of: shouldSyncOnReentry) { shouldSync in
            if shouldSync { syncNow() }
        }
        .onChange(of: licenseManager.clientSessionRevision) { _ in
            guard shouldSyncOnReentry, licenseManager.isActive else { return }
            syncNow()
        }
        .onChange(of: licenseManager.isActive) { isActive in
            if isActive && shouldSyncOnReentry {
                syncNow()
            } else if !isActive {
                store.clearManagedFiles()
                hiddenDocumentIDs.removeAll()
                showHiddenDocuments = false
                pollingEnabled = false
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, shouldSyncOnReentry, licenseManager.isActive else { return }
            syncNow()
        }
        .onChange(of: store.files) { files in
            hiddenDocumentIDs.formIntersection(Set(files.map(\.id)))
        }
        .task(id: shouldSyncOnReentry && pollingEnabled) {
            guard shouldSyncOnReentry && pollingEnabled else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard shouldSyncOnReentry, licenseManager.isActive else { continue }
                await store.sync(sessionToken: licenseManager.clientSessionToken())
            }
        }
    }

    private func documentRow(_ file: NOVAStoredDocument) -> some View {
        let isVisible = !hiddenDocumentIDs.contains(file.id)
        return VStack(alignment: .leading, spacing: 8) {
            if file.isRecentlyUploaded {
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 18, height: 3)
                    Text(appLanguage.text("nova.files.recent"))
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.filename)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.paper)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.paper.opacity(0.52))
                }
                Spacer(minLength: 4)
                Toggle(isOn: visibilityBinding(for: file.id)) {
                    Text(appLanguage.text("nova.files.toggle_hint"))
                }
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityLabel(Text(appLanguage.text("nova.files.toggle_hint")))
            }

            Text(appLanguage.text(isVisible ? "nova.files.visible" : "nova.files.hidden"))
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(isVisible ? AppTheme.accent : AppTheme.paper.opacity(0.5))
        }
        .padding(10)
        .background(AppTheme.ink.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.paper.opacity(isVisible ? 0.1 : 0.04), lineWidth: 1))
        .opacity(isVisible ? 1 : 0.58)
    }

    private func visibilityBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { !hiddenDocumentIDs.contains(id) },
            set: { isVisible in
                if isVisible {
                    hiddenDocumentIDs.remove(id)
                } else {
                    hiddenDocumentIDs.insert(id)
                }
            }
        )
    }

    private func syncNow() {
        guard licenseManager.isActive else { return }
        pollingEnabled = true
        Task { await store.sync(sessionToken: licenseManager.clientSessionToken()) }
    }
}
