import SwiftUI
import UIKit
import Security

@main
struct ThreeOneOSSixApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var migrationTaskCenter = MigrationTaskCenter()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var vipLaunchResolved = false
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @State private var configImportError: String?
    @AppStorage("vip.demo.authenticated") private var vipAuthenticated = false
    @AppStorage("vip.demo.savedLicenseKey") private var vipSavedLicenseKey = ""
    @AppStorage("vip.demo.maintenance") private var vipMaintenance = false
    @AppStorage("vip.license.expires_at") private var vipLicenseExpiresAt = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        // Seed the UI language before the first view body runs. `@AppStorage`
        // reads UserDefaults on every access, so a write here is visible to
        // the first render. A stored value always wins — see seedIfNeeded.
        LanguageResolver.seedIfNeeded()
        // VIP authentication is reset from the root view's first appearance.
        // A separate launch gate prevents SwiftUI from briefly rendering the
        // authenticated ContentView while @AppStorage is being initialized.
        setupLogCapture()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let cpu = DeviceCPU.cpuFamily.map { String(format: "0x%X", $0) } ?? "unknown"
        log("app: Vexora Pro \(appVersion) (\(appBuild)) launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName) cpu=\(cpu)")
        SandboxAccess.prepare()
        TempSpaceRegistry.purgeExpired()
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func importConfigPackage(at url: URL) {
        do {
            _ = try MigrationConfigBackupService.importPackage(at: url)
            migrationTaskCenter.refreshStoredSets()
            configImportError = nil
            log("migration: config package imported — \(url.lastPathComponent)")
        } catch {
            log("migration: config package import failed — \(error)")
            configImportError = language.errorText(error)
        }
    }

    /// GestaltX #133: a share extension may drop packages into the App Group
    /// inbox without delivering an onOpenURL callback. Read whichever App
    /// Group the side-loaded build was actually signed with.
    private func importSharedConfigPackages() {
        guard let group = SandboxAccess.appGroup,
              let inbox = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appendingPathComponent("SharedConfigInbox", isDirectory: true) else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls where url.pathExtension.lowercased()
            == MigrationConfigBackupService.packageExtension {
            importConfigPackage(at: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    /// Foreground-switch variant: 30-minute throttle lives in the checker
    /// (persisted), so repeated quick app switches cost nothing.
    private func checkForUpdateThrottled() {
        Task {
            guard let offer = await AppUpdateChecker.throttledForegroundCheck() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !vipLaunchResolved {
                    ZStack {
                        Color(red: 0.035, green: 0.055, blue: 0.13).ignoresSafeArea()
                        ProgressView()
                            .tint(.white)
                    }
                } else if vipAuthenticated {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(patchDraftCoordinator)
                    .environmentObject(fileOperationCoordinator)
                    .environmentObject(patchStore)
                    .environmentObject(repositoryStore)
                    .environmentObject(migrationTaskCenter)
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .opacity(showOnboarding ? 0 : 1)
                    .allowsHitTesting(!showOnboarding)

                if showOnboarding {
                    OnboardingView {
                        OnboardingStore.markCompleted()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            showOnboarding = false
                        }
                        appState.detectSupport()
                    }
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98))
                    )
                    .zIndex(1)
                }
                } else {
                    VIPLoginPreviewView(
                        isAuthenticated: $vipAuthenticated,
                        savedLicenseKey: $vipSavedLicenseKey,
                        isMaintenanceEnabled: $vipMaintenance,
                        licenseExpiresAt: $vipLicenseExpiresAt
                    )
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding && vipAuthenticated)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(
                language.text("config.import_error.title"),
                isPresented: .init(
                    get: { configImportError != nil },
                    set: { if !$0 { configImportError = nil } }
                )
            ) {
                Button(language.text("common.ok"), role: .cancel) {
                    configImportError = nil
                }
            } message: {
                Text(configImportError ?? "")
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version) + "\n" + language.text("update.current", AppInfo.appVersion)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("common.cancel"))) {}
                )
            }
            .onAppear {
                if !vipLaunchResolved {
                    // Force the VIP screen to be the first app screen on every
                    // cold launch. VIPLoginPreviewView then checks the saved
                    // demo key and advances automatically when it matches.
                    vipAuthenticated = false
                    vipLaunchResolved = true
                }
                if !showOnboarding && vipAuthenticated {
                    appState.detectSupport()
                }
                migrationTaskCenter.refreshPendingResumes()
                importSharedConfigPackages()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding, vipAuthenticated else { return }
                appState.detectSupport()
                // Vexora Pro distribution: upstream release checks are disabled.
                // Maintenance and license verification remain independent.
            }
            .onOpenURL { url in
                // Config backup packages (.3106cfg) route to the migration
                // importer; everything else stays on the patch-package path.
                if url.isFileURL,
                   url.pathExtension.lowercased() == MigrationConfigBackupService.packageExtension {
                    importConfigPackage(at: url)
                    return
                }
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?

    /// Same storage key as the `@AppStorage` in `ThreeOneOSSixApp`. AppState
    /// is a plain class, so it cannot read the struct's property directly —
    /// it resolves the language from the shared defaults instead.
    private var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? "")
            ?? .english
    }
    @Published var kernelExploitRunning = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        if !supported {
            // The explanation lives in RejectionReason so onboarding can show
            // the identical copy without a second hand-maintained copy drifting
            // the moment a version boundary moves.
            if let reason = RejectionReason.make(
                major: v.major,
                minor: v.minor,
                patch: v.patch,
                build: AppInfo.osBuild,
                osVersion: "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))",
                isA10: DeviceCPU.isA10
            ) {
                unsupportedMessage = language.text(reason.key, reason.arguments)
            }
        }
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        // Deliberately no auto-run. The kernel chain reboots the device when it
        // goes wrong, and a process that quietly executes an exploit at launch
        // gives the user no chance to consent or to read what happened. The
        // Unlock screen is the only entry point now; `kernelExploitRunning`,
        // `exploitStatus` and the banner state drive it.
    }

    /// True when the app should offer the Unlock screen: a kernel backend that
    /// has not succeeded yet. Deliberately excludes a settled failure — retrying
    /// automatically after a failure would recreate the silent loop this change
    /// removed. The user re-opens Unlock explicitly to try again.
    var needsUnlock: Bool {
        ExploitSupportPolicy.requiresExplicitUnlock(
            isKernelBackend: SandboxAccess.backend == .kernel,
            hasAccess: exploitStatus.isSuccess
        )
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: SandboxAccess.backend.displayName)
                    log("app: existing \(SandboxAccess.backend.displayName) access is still active")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        let backend = SandboxAccess.backend
        log("app: running \(backend.displayName) access setup on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: backend.displayName)
                    if backend == .kernel {
                        log("app: kernel access active")
                    } else {
                        log("app: \(backend.displayName) access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: backend.displayName, code: -1)
                    if backend == .worseQuery && !SandboxAccess.hasAppGroup {
                        log("app: worse_query needs an App Group; re-sign with a tool that provides one")
                    } else {
                        log("app: \(backend.displayName) setup failed — relaunch the app before retrying")
                    }
                }
            }
        }
    }
}


/// Production VIP gate. License verification is performed by the HTTPS API
/// used by the Telegram license bot; no demo key or client-side API secret is used.
private enum VIPAPIConfiguration {
    // Replace this with the public HTTPS URL of the deployed FastAPI service.
    static let baseURL = "https://api.panelreseller.shop"
}

private struct VIPVerifyResponse: Decodable {
    let ok: Bool
    let reason: String?
    let expires_at: Int?
    let remaining_seconds: Int?
    let telegram_link: String?
}

private enum VIPDeviceIdentity {
    static func stableID() -> String {
        let service = Bundle.main.bundleIdentifier ?? "com.qingtang.3106"
        let account = "vip-license-device-id"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        let value = UUID().uuidString
        var insert = query
        insert.removeValue(forKey: kSecReturnData as String)
        insert.removeValue(forKey: kSecMatchLimit as String)
        insert[kSecValueData as String] = value.data(using: .utf8)
        SecItemAdd(insert as CFDictionary, nil)
        return value
    }
}

private enum VIPLicenseService {
    static func verify(key: String) async throws -> VIPVerifyResponse {
        guard !VIPAPIConfiguration.baseURL.contains("CHANGE-ME"),
              let url = URL(string: VIPAPIConfiguration.baseURL + "/v1/verify") else {
            throw NSError(domain: "VIPLicense", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The license server URL has not been configured yet."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = [
            "license_key": key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "device_id": VIPDeviceIdentity.stableID()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "VIPLicense", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "License server error. Please try again later."
            ])
        }
        return try JSONDecoder().decode(VIPVerifyResponse.self, from: data)
    }
}

private struct VIPLoginPreviewView: View {
    @Binding var isAuthenticated: Bool
    @Binding var savedLicenseKey: String
    @Binding var isMaintenanceEnabled: Bool
    @Binding var licenseExpiresAt: Int
    @State private var licenseKey = ""
    @State private var errorMessage: String?
    @State private var isCheckingSavedKey = true
    @State private var isRequesting = false
    @State private var didCheckSavedKey = false
    @State private var joinURL = URL(string: "https://t.me/VexoraPro_Updates")!

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.012, green: 0.012, blue: 0.035),
                         Color(red: 0.055, green: 0.025, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.black.opacity(0.72))
                        .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.purple.opacity(0.8), lineWidth: 1.5))
                        .shadow(color: .purple.opacity(0.45), radius: 22)
                        .frame(width: 92, height: 92)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.48, blue: 1.0))
                }
                Text("Vexora Pro")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.78, green: 0.48, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                Text("SECURE LICENSE VERIFICATION")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.65))

                if isMaintenanceEnabled {
                    VStack(spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 34))
                        Text("APP UNDER MAINTENANCE")
                            .font(.headline.bold())
                        Text("We are performing maintenance. Please try again later.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                        Button("Check Again") { Task { await checkSavedOrEnteredKey() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LICENSE KEY")
                            .font(.caption.bold())
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.8))
                        TextField("Enter your license key", text: $licenseKey)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(.black)
                            .disabled(isRequesting || isCheckingSavedKey)

                        Button(action: { Task { await activate() } }) {
                            HStack {
                                if isRequesting || isCheckingSavedKey { ProgressView().tint(.white) }
                                Text("ACTIVATE LICENSE")
                                    .font(.headline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(LinearGradient(colors: [Color(red: 0.72, green: 0.22, blue: 1.0), Color(red: 0.36, green: 0.08, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(.white)
                        }
                        .disabled(isRequesting || isCheckingSavedKey)
                        .opacity((isRequesting || isCheckingSavedKey) ? 0.55 : 1)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(18)
                    .background(LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.19), Color(red: 0.045, green: 0.04, blue: 0.085)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.purple.opacity(0.42), lineWidth: 1))

                    Link(destination: joinURL) {
                        Label("Join Telegram Channel", systemImage: "paperplane.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(15)
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.purple.opacity(0.65), lineWidth: 1))
                    }

                    if isCheckingSavedKey {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Checking saved license…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()
                Text("VEXORA PRO")
                    .font(.caption2)
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 30)
        }
        .onAppear {
            guard !didCheckSavedKey else { return }
            didCheckSavedKey = true
            isMaintenanceEnabled = false
            Task { await checkSavedOrEnteredKey() }
        }
    }

    @MainActor
    private func checkSavedOrEnteredKey() async {
        let stored = savedLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty else {
            isCheckingSavedKey = false
            return
        }
        await verify(stored, isSavedKey: true)
    }

    @MainActor
    private func activate() async {
        let entered = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else {
            errorMessage = "Please enter your license key."
            return
        }
        await verify(entered, isSavedKey: false)
    }

    @MainActor
    private func verify(_ key: String, isSavedKey: Bool) async {
        isRequesting = true
        errorMessage = nil
        isMaintenanceEnabled = false
        defer {
            isRequesting = false
            isCheckingSavedKey = false
        }
        do {
            let result = try await VIPLicenseService.verify(key: key)
            if result.ok {
                savedLicenseKey = key.uppercased()
                licenseExpiresAt = result.expires_at ?? 0
                isAuthenticated = true
            } else if result.reason == "maintenance" {
                isMaintenanceEnabled = true
                errorMessage = nil
            } else {
                if isSavedKey { savedLicenseKey = "" }
                errorMessage = Self.message(for: result.reason)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func message(for reason: String?) -> String {
        switch reason {
        case "invalid_key": return "Invalid license key. Please check and try again."
        case "expired": return "This license key has expired."
        case "banned": return "This license key has been disabled."
        case "device_mismatch": return "This key is already activated on another device."
        default: return "License verification failed. Please try again."
        }
    }
}
