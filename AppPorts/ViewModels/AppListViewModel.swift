//
//  AppListViewModel.swift
//  AppPorts
//
//  Created by Claude on 2026/3/17.
//

import SwiftUI
import Combine

// MARK: - 应用列表视图模型

/// 管理应用列表状态和业务逻辑的视图模型
///
/// 负责处理：
/// - 本地和外部应用列表的状态管理
/// - 搜索和排序逻辑
/// - 应用选择状态
/// - 扫描和刷新操作
///
/// ## 使用示例
/// ```swift
/// struct ContentView: View {
///     @StateObject private var viewModel = AppListViewModel()
///
///     var body: some View {
///         List(viewModel.filteredLocalApps) { app in
///             AppRowView(app: app)
///         }
///         .onAppear { viewModel.scanLocalApps() }
///     }
/// }
/// ```
@MainActor
class AppListViewModel: ObservableObject {
    
    // MARK: - 发布属性
    
    /// 本地应用列表
    @Published var localApps: [AppItem] = []
    
    /// 外部应用列表
    @Published var externalApps: [AppItem] = []
    
    /// 搜索文本
    @Published var searchText: String = ""
    
    /// 排序选项
    @Published var sortOption: SortOption = .name
    
    /// 选中的本地应用 ID
    @Published var selectedLocalApps: Set<UUID> = []
    
    /// 选中的外部应用 ID
    @Published var selectedExternalApps: Set<UUID> = []
    
    /// 外部驱动器 URL
    @Published var externalDriveURL: URL? {
        didSet {
            if let url = externalDriveURL {
                UserDefaults.standard.set(url.path, forKey: "ExternalDrivePath")
            } else {
                UserDefaults.standard.removeObject(forKey: "ExternalDrivePath")
            }
        }
    }
    
    // MARK: - 进度状态
    
    @Published var showProgress = false
    @Published var progressCurrent = 0
    @Published var progressTotal = 0
    @Published var progressAppName = ""
    @Published var isMigrating = false
    @Published var progressBytes: Int64 = 0
    @Published var progressTotalBytes: Int64 = 0
    
    // MARK: - 警报状态
    
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showUpdateAlert = false
    @Published var updateURL: URL?
    @Published var showAppStoreConfirm = false
    @Published var pendingAppStoreApps: [AppItem] = []
    @Published var showAppStoreSettings = false
    
    // MARK: - 监控器
    
    var localMonitor: FolderMonitor?
    var externalMonitor: FolderMonitor?
    
    // MARK: - 常量
    
    let localAppsURL = URL(fileURLWithPath: "/Applications")
    let fileManager = FileManager.default
    
    // MARK: - 排序选项
    
    enum SortOption {
        case name, size
    }
    
    // MARK: - 计算属性
    
    var filteredLocalApps: [AppItem] {
        let apps = localApps
        let filtered = searchText.isEmpty ? apps : apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) || 
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return sortApps(filtered)
    }
    
    var filteredExternalApps: [AppItem] {
        let apps = externalApps
        let filtered = searchText.isEmpty ? apps : apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) || 
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return sortApps(filtered)
    }
    
    var canMoveOut: Bool {
        guard externalDriveURL != nil else { return false }
        let validApps = selectedLocalApps.compactMap { id in
            localApps.first { $0.id == id }
        }.filter { !$0.isSystemApp && !$0.isRunning && $0.status != "已链接" }
        return !validApps.isEmpty
    }
    
    var canLinkIn: Bool {
        let validApps = selectedExternalApps.compactMap { id in
            externalApps.first { $0.id == id }
        }.filter { $0.status == "未链接" || $0.status == "外部" }
        return !validApps.isEmpty
    }
    
    // MARK: - 初始化
    
    init() {
        restoreExternalDrivePath()
    }
    
    // MARK: - 公共方法
    
    func restoreExternalDrivePath() {
        if let savedPath = UserDefaults.standard.string(forKey: "ExternalDrivePath") {
            let url = URL(fileURLWithPath: savedPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: savedPath, isDirectory: &isDir), isDir.boolValue {
                self.externalDriveURL = url
                AppLogger.shared.logContext(
                    "恢复已保存的外部路径",
                    details: [("path", savedPath), ("is_directory", isDir.boolValue ? "true" : "false")]
                )
                AppLogger.shared.logExternalDriveInfo(at: url)
            } else {
                AppLogger.shared.logContext(
                    "已保存的外部路径无效，忽略",
                    details: [("path", savedPath)],
                    level: "WARN"
                )
            }
        }
    }
    
    func sortApps(_ apps: [AppItem]) -> [AppItem] {
        switch sortOption {
        case .name:
            return apps
        case .size:
            return apps.sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.displayName < $1.displayName
                }
                return $0.sizeBytes > $1.sizeBytes
            }
        }
    }
    
    func getMoveButtonTitle() -> (text: String, isError: Bool) {
        let validApps = selectedLocalApps.compactMap { id in
            localApps.first { $0.id == id }
        }.filter { !$0.isSystemApp && !$0.isRunning && $0.status != "已链接" }
        
        if selectedLocalApps.isEmpty {
            return ("迁移到外部", false)
        }
        
        if validApps.isEmpty {
            let selectedAppsData = selectedLocalApps.compactMap { id in localApps.first { $0.id == id } }
            if selectedAppsData.contains(where: { $0.isSystemApp }) { return ("含系统应用", true) }
            if selectedAppsData.contains(where: { $0.isRunning }) { return ("含运行中应用", true) }
            if selectedAppsData.contains(where: { $0.status == "已链接" }) { return ("已链接", false) }
            return ("迁移到外部", false)
        }
        
        if validApps.count == 1 {
            return ("迁移到外部", false)
        }
        
        return (String(format: "迁移 %lld 个应用".localized, Int64(validApps.count)), false)
    }
    
    func getLinkButtonTitle() -> String {
        let validApps = selectedExternalApps.compactMap { id in
            externalApps.first { $0.id == id }
        }.filter { $0.status == "未链接" || $0.status == "外部" }
        
        if selectedExternalApps.isEmpty || validApps.isEmpty {
            return "链接回本地".localized
        }
        
        if validApps.count == 1 {
            return "链接回本地".localized
        }
        
        return String(format: "链接 %lld 个应用".localized, Int64(validApps.count))
    }
    
    func getRunningAppURLs() -> Set<URL> {
        let runningApps = NSWorkspace.shared.runningApplications
        let urls = runningApps.compactMap { $0.bundleURL }
        return Set(urls)
    }
    
    func scanLocalApps() {
        let scanID = AppLogger.shared.makeOperationID(prefix: "scan-local-apps")
        AppLogger.shared.logContext(
            "开始扫描本地应用",
            details: [("scan_id", scanID), ("directory", localAppsURL.path)]
        )
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let runningAppURLs = await MainActor.run { self.getRunningAppURLs() }
            let scanDir = self.localAppsURL
            
            let scanner = AppScanner()
            let newApps = await scanner.scanLocalApps(at: scanDir, runningAppURLs: runningAppURLs)
            
            await MainActor.run {
                self.localApps = newApps
            }
            
            AppLogger.shared.logContext(
                "本地应用扫描完成",
                details: [
                    ("scan_id", scanID),
                    ("count", String(newApps.count))
                ]
            )
            
            // 计算应用大小
            await self.calculateSizesProgressive(for: newApps, isLocal: true, scanner: scanner)
        }
    }
    
    func scanExternalApps() {
        guard let externalURL = externalDriveURL else {
            externalApps = []
            return
        }
        
        let scanID = AppLogger.shared.makeOperationID(prefix: "scan-external-apps")
        AppLogger.shared.logContext(
            "开始扫描外部应用",
            details: [("scan_id", scanID), ("directory", externalURL.path)]
        )
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let scanner = AppScanner()
            let localDir = self.localAppsURL
            let newApps = await scanner.scanExternalApps(at: externalURL, localAppsDir: localDir)
            
            await MainActor.run {
                self.externalApps = newApps
            }
            
            AppLogger.shared.logContext(
                "外部应用扫描完成",
                details: [
                    ("scan_id", scanID),
                    ("count", String(newApps.count))
                ]
            )
            
            // 计算应用大小
            await self.calculateSizesProgressive(for: newApps, isLocal: false, scanner: scanner)
        }
    }
    
    func isAppStoreApp(at url: URL) -> Bool {
        // 检测 _MASReceipt（Mac App Store 收据）
        let receiptPath = url.appendingPathComponent("Contents/_MASReceipt")
        if fileManager.fileExists(atPath: receiptPath.path) {
            return true
        }
        
        // 检测 iOS 应用
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        if let plistData = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
            
            // UIDeviceFamily: 1=iPhone, 2=iPad
            if let deviceFamily = plist["UIDeviceFamily"] as? [Int] {
                let hasIPhoneOrIPad = deviceFamily.contains(1) || deviceFamily.contains(2)
                let isMacCatalyst = deviceFamily.contains(6)
                if hasIPhoneOrIPad && !isMacCatalyst {
                    return true
                }
            }
            
            // LSRequiresIPhoneOS 仅 iOS 应用有
            if plist["LSRequiresIPhoneOS"] as? Bool == true {
                return true
            }
            
            // DTPlatformName 检测
            if let platform = plist["DTPlatformName"] as? String,
               platform == "iphoneos" || platform == "iphonesimulator" {
                return true
            }
        }
        
        // WrappedBundle 也是 iOS 应用
        let wrappedBundleURL = url.appendingPathComponent("WrappedBundle")
        if fileManager.fileExists(atPath: wrappedBundleURL.path) {
            return true
        }
        
        return false
    }
    
    // MARK: - 异步大小计算
    
    func calculateSizesProgressive(for apps: [AppItem], isLocal: Bool, scanner: AppScanner) async {
        for app in apps {
            let sizeBytes = await scanner.calculateDisplayedSize(for: app, isLocalEntry: isLocal)
            
            let sizeString = LocalizedByteCountFormatter.string(fromByteCount: sizeBytes)
            
            if isLocal {
                if let index = localApps.firstIndex(where: { $0.id == app.id }) {
                    localApps[index].size = sizeString
                    localApps[index].sizeBytes = sizeBytes
                }
            } else {
                if let index = externalApps.firstIndex(where: { $0.id == app.id }) {
                    externalApps[index].size = sizeString
                    externalApps[index].sizeBytes = sizeBytes
                }
            }
        }
    }
    
    // MARK: - UI 辅助方法
    
    func openPanelForExternalDrive() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "选择文件夹".localized
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        AppLogger.shared.log("打开外部路径选择面板")
        if openPanel.runModal() == .OK, let url = openPanel.urls.first {
            self.externalDriveURL = url
            AppLogger.shared.logContext("用户选择外部路径", details: [("path", url.path)])
            AppLogger.shared.logExternalDriveInfo(at: url)
        } else {
            AppLogger.shared.log("用户取消选择外部路径", level: "TRACE")
        }
    }
    
    func showError(title: String, message: String) {
        AppLogger.shared.logContext(
            "向用户展示错误",
            details: [("title", title), ("message", message)],
            level: "ERROR"
        )
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
    
    func isAppRunning(url: URL) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        return runningApps.contains { app in
            return app.bundleURL == url
        }
    }
    
    func getMoveBackButtonTitle() -> String {
        if selectedExternalApps.isEmpty {
            return "迁移回本地".localized
        }
        
        if selectedExternalApps.count == 1 {
            return "迁移回本地".localized
        }
        
        return String(format: "迁移 %lld 个应用".localized, Int64(selectedExternalApps.count))
    }
    
    // MARK: - 迁移服务调用
    
    func moveAndLink(appToMove: AppItem, destinationURL: URL, progressHandler: FileCopier.ProgressHandler?) async throws {
        let service = AppMigrationService()
        try await service.moveAndLink(
            appToMove: appToMove,
            destinationURL: destinationURL,
            isRunning: isAppRunning(url: appToMove.displayURL),
            deleteSourceFallback: AppMigrationService.removeItemViaFinder(at:),
            progressHandler: progressHandler
        )
    }
    
    func linkApp(appToLink: AppItem, destinationURL: URL) throws {
        try AppMigrationService().linkApp(appToLink: appToLink, destinationURL: destinationURL)
    }
    
    func deleteLink(app: AppItem) throws {
        try AppMigrationService().deleteLink(app: app)
    }
    
    func moveBack(app: AppItem, localDestinationURL: URL, progressHandler: FileCopier.ProgressHandler?) async throws {
        try await AppMigrationService().moveBack(
            app: app,
            localDestinationURL: localDestinationURL,
            progressHandler: progressHandler
        )
    }
    
    // MARK: - 执行操作
    
    func performMoveOut() {
        guard let dest = externalDriveURL else { return }
        
        // 读取用户设置
        let allowAppStoreMigration = UserDefaults.standard.bool(forKey: "allowAppStoreMigration")
        let allowIOSAppMigration = UserDefaults.standard.bool(forKey: "allowIOSAppMigration")
        
        // 获取所有选中且可迁移的应用
        let validApps = selectedLocalApps.compactMap { id in
            localApps.first { $0.id == id }
        }.filter { app in
            // 基本过滤条件
            guard !app.isSystemApp && !app.isRunning && app.status != "已链接" else { return false }
            
            // 如果启用了迁移 iOS 应用，iOS 应用可以迁移
            if app.isIOSApp {
                return allowIOSAppMigration
            }
            
            // 如果启用了迁移 App Store 应用，App Store 应用可以迁移
            if app.isAppStoreApp {
                return allowAppStoreMigration
            }
            
            // 普通应用始终可以迁移
            return true
        }
        
        // 检查是否有应用被跳过
        let skippedApps = selectedLocalApps.compactMap { id in
            localApps.first { $0.id == id }
        }.filter { app in
            guard !app.isSystemApp && app.status != "已链接" else { return false }
            
            if app.isIOSApp && !allowIOSAppMigration {
                return true
            }
            if app.isAppStoreApp && !allowAppStoreMigration {
                return true
            }
            return false
        }
        
        let selectedApps = selectedLocalApps.compactMap { id in
            localApps.first { $0.id == id }
        }
        let skippedDetails = selectedApps.compactMap { app -> String? in
            guard let reason = Self.migrationSkipReason(
                for: app,
                allowAppStoreMigration: allowAppStoreMigration,
                allowIOSAppMigration: allowIOSAppMigration
            ) else {
                return nil
            }
            return "\(app.displayName)=\(reason)"
        }
        AppLogger.shared.logContext(
            "用户请求迁移应用",
            details: [
                ("selected_count", String(selectedApps.count)),
                ("selected_apps", Self.joinedAppNames(selectedApps)),
                ("valid_count", String(validApps.count)),
                ("valid_apps", Self.joinedAppNames(validApps)),
                ("skipped_count", String(skippedApps.count)),
                ("skipped_details", skippedDetails.isEmpty ? "(none)" : skippedDetails.joined(separator: "; ")),
                ("destination", dest.path),
                ("allow_app_store", allowAppStoreMigration ? "true" : "false"),
                ("allow_ios", allowIOSAppMigration ? "true" : "false")
            ]
        )
        
        if !skippedApps.isEmpty && validApps.isEmpty {
            // 生成提示信息
            var message = ""
            let hasIOSApps = skippedApps.contains { $0.isIOSApp }
            let hasAppStoreApps = skippedApps.contains { $0.isAppStoreApp && !$0.isIOSApp }
            
            if hasIOSApps && hasAppStoreApps {
                message = "选中的应用包含 App Store 应用和非原生应用。\n\n如需迁移，请在设置中启用相应选项。"
            } else if hasIOSApps {
                message = "非原生 (iPhone/iPad) 应用不支持迁移。\n\n如需迁移，请在设置中启用「允许迁移非原生应用」选项。"
            } else {
                message = "App Store 应用不支持迁移，因为迁移后将无法通过 App Store 更新。\n\n如需强制迁移，请在设置中启用相应选项。"
            }
            
            showError(title: "无法迁移", message: message)
            return
        }
        
        guard !validApps.isEmpty else { return }
        
        // 直接迁移符合条件的应用
        executeBatchMove(apps: validApps, destination: dest)
    }
    
    /// 批量迁移应用
    func executeBatchMove(apps: [AppItem], destination: URL) {
        guard !apps.isEmpty else { return }
        let batchID = AppLogger.shared.makeOperationID(prefix: "batch-move-out")
        AppLogger.shared.logContext(
            "开始批量迁移应用",
            details: [
                ("batch_id", batchID),
                ("count", String(apps.count)),
                ("apps", Self.joinedAppNames(apps)),
                ("destination", destination.path)
            ]
        )
        
        isMigrating = true
        progressTotal = apps.count
        progressCurrent = 0
        showProgress = true
        
        var errors: [String] = []
        
        Task {
            for app in apps {
                progressAppName = app.name
                progressCurrent += 1
                progressBytes = 0
                progressTotalBytes = 0
                
                let destURL = destination.appendingPathComponent(app.name)
                AppLogger.shared.logContext(
                    "批量迁移单项开始",
                    details: [("batch_id", batchID), ("app_name", app.displayName), ("destination", destURL.path)],
                    level: "TRACE"
                )
                
                do {
                    try await moveAndLink(appToMove: app, destinationURL: destURL) { [weak self] progress in
                        Task { @MainActor in
                            self?.progressBytes = progress.copiedBytes
                            self?.progressTotalBytes = progress.totalBytes
                        }
                    }
                    AppLogger.shared.logContext(
                        "批量迁移单项成功",
                        details: [("batch_id", batchID), ("app_name", app.displayName)]
                    )
                } catch {
                    errors.append("\(app.name): \(error.localizedDescription)")
                    AppLogger.shared.logError(
                        "批量迁移单项失败",
                        error: error,
                        context: [("batch_id", batchID), ("app_name", app.displayName), ("destination", destURL.path)],
                        relatedURLs: [("source", app.path), ("destination", destURL)]
                    )
                }
            }
            
            showProgress = false
            isMigrating = false
            selectedLocalApps.removeAll()
            scanLocalApps()
            scanExternalApps()
            
            if !errors.isEmpty {
                showError(title: "部分迁移失败", message: errors.joined(separator: "\n"))
            }
            
            AppLogger.shared.logContext(
                "批量迁移应用结束",
                details: [
                    ("batch_id", batchID),
                    ("success_count", String(apps.count - errors.count)),
                    ("failure_count", String(errors.count))
                ]
            )
        }
    }
    
    func performLinkIn() {
        // 获取所有选中且可链接的应用
        let validApps = selectedExternalApps.compactMap { id in
            externalApps.first { $0.id == id }
        }.filter { $0.status == "未链接" || $0.status == "外部" || $0.status == "部分链接" }
        
        guard !validApps.isEmpty else { return }
        
        isMigrating = true
        showProgress = true
        
        var errors: [String] = []
        
        let appsToLink = validApps.map { (app: $0, sourcePath: $0.path) }
        let batchID = AppLogger.shared.makeOperationID(prefix: "batch-link-in")
        AppLogger.shared.logContext(
            "开始批量链接应用",
            details: [
                ("batch_id", batchID),
                ("selected_count", String(validApps.count)),
                ("selected_items", Self.joinedAppNames(validApps)),
                ("expanded_app_count", String(appsToLink.count)),
                ("expanded_sources", appsToLink.map { $0.sourcePath.lastPathComponent }.joined(separator: ", "))
            ]
        )
        
        progressTotal = appsToLink.count
        progressCurrent = 0
        
        Task {
            for item in appsToLink {
                let appName = item.sourcePath.lastPathComponent
                progressAppName = appName
                progressCurrent += 1
                
                let destination = localAppsURL.appendingPathComponent(appName)
                let tempAppItem = AppItem(
                    name: appName,
                    path: item.sourcePath,
                    bundleURL: item.app.bundleURL,
                    status: "未链接",
                    isFolder: item.app.isFolder,
                    containerKind: item.app.containerKind,
                    appCount: item.app.appCount
                )
                AppLogger.shared.logContext(
                    "批量链接单项开始",
                    details: [("batch_id", batchID), ("app_name", appName), ("destination", destination.path)],
                    level: "TRACE"
                )
                
                do {
                    try linkApp(appToLink: tempAppItem, destinationURL: destination)
                    AppLogger.shared.logContext(
                        "批量链接单项成功",
                        details: [("batch_id", batchID), ("app_name", appName)]
                    )
                } catch {
                    errors.append("\(appName): \(error.localizedDescription)")
                    AppLogger.shared.logError(
                        "批量链接单项失败",
                        error: error,
                        context: [("batch_id", batchID), ("app_name", appName), ("folder_item", item.app.displayName)],
                        relatedURLs: [("source", item.sourcePath), ("destination", destination)]
                    )
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            showProgress = false
            isMigrating = false
            selectedExternalApps.removeAll()
            scanLocalApps()
            scanExternalApps()
            
            if !errors.isEmpty {
                showError(title: "部分链接失败", message: errors.joined(separator: "\n"))
            }
            
            AppLogger.shared.logContext(
                "批量链接应用结束",
                details: [
                    ("batch_id", batchID),
                    ("success_count", String(appsToLink.count - errors.count)),
                    ("failure_count", String(errors.count))
                ]
            )
        }
    }
    
    func performDeleteLink(app: AppItem) {
        AppLogger.shared.logContext(
            "用户请求删除本地入口",
            details: [("app_name", app.displayName), ("path", app.path.path), ("status", app.status)]
        )
        do {
            try deleteLink(app: app)
            scanLocalApps()
            scanExternalApps()
        } catch {
            AppLogger.shared.logError(
                "删除本地入口失败",
                error: error,
                context: [("app_name", app.displayName)],
                relatedURLs: [("path", app.path)]
            )
            showError(title: "错误", message: error.localizedDescription)
        }
    }
    
    func performMoveBack(app: AppItem) {
        let operationID = AppLogger.shared.makeOperationID(prefix: "single-move-back")
        AppLogger.shared.logContext(
            "用户请求还原单个应用",
            details: [
                ("operation_id", operationID),
                ("app_name", app.displayName),
                ("source", app.path.path),
                ("destination", localAppsURL.appendingPathComponent(app.name).path)
            ]
        )
        isMigrating = true
        progressTotal = 1
        progressCurrent = 1
        progressAppName = app.displayName
        progressBytes = 0
        progressTotalBytes = 0
        showProgress = true
        
        Task {
            let destination = localAppsURL.appendingPathComponent(app.name)
            do {
                try await moveBack(app: app, localDestinationURL: destination) { [weak self] progress in
                    Task { @MainActor in
                        self?.progressBytes = progress.copiedBytes
                        self?.progressTotalBytes = progress.totalBytes
                    }
                }
                AppLogger.shared.logContext(
                    "单个应用还原成功",
                    details: [("operation_id", operationID), ("app_name", app.displayName)]
                )
            } catch {
                AppLogger.shared.logError(
                    "单个应用还原失败",
                    error: error,
                    context: [("operation_id", operationID), ("app_name", app.displayName)],
                    relatedURLs: [("source", app.path), ("destination", destination)]
                )
                showError(title: "错误", message: error.localizedDescription)
            }
            
            showProgress = false
            isMigrating = false
            scanLocalApps()
            scanExternalApps()
        }
    }
    
    /// 批量迁移回本地
    func performBatchMoveBack() {
        // 获取所有选中的外部应用
        let validApps = selectedExternalApps.compactMap { id in
            externalApps.first { $0.id == id }
        }
        
        guard !validApps.isEmpty else { return }
        let batchID = AppLogger.shared.makeOperationID(prefix: "batch-move-back")
        AppLogger.shared.logContext(
            "开始批量还原应用",
            details: [
                ("batch_id", batchID),
                ("count", String(validApps.count)),
                ("apps", Self.joinedAppNames(validApps))
            ]
        )
        
        isMigrating = true
        progressTotal = validApps.count
        progressCurrent = 0
        showProgress = true
        
        var errors: [String] = []
        
        Task {
            for app in validApps {
                progressAppName = app.displayName
                progressCurrent += 1
                progressBytes = 0
                progressTotalBytes = 0
                
                let destination = localAppsURL.appendingPathComponent(app.name)
                AppLogger.shared.logContext(
                    "批量还原单项开始",
                    details: [("batch_id", batchID), ("app_name", app.displayName), ("destination", destination.path)],
                    level: "TRACE"
                )
                
                do {
                    try await moveBack(app: app, localDestinationURL: destination) { [weak self] progress in
                        Task { @MainActor in
                            self?.progressBytes = progress.copiedBytes
                            self?.progressTotalBytes = progress.totalBytes
                        }
                    }
                    AppLogger.shared.logContext(
                        "批量还原单项成功",
                        details: [("batch_id", batchID), ("app_name", app.displayName)]
                    )
                } catch {
                    errors.append("\(app.displayName): \(error.localizedDescription)")
                    AppLogger.shared.logError(
                        "批量还原单项失败",
                        error: error,
                        context: [("batch_id", batchID), ("app_name", app.displayName)],
                        relatedURLs: [("source", app.path), ("destination", destination)]
                    )
                }
            }
            
            showProgress = false
            isMigrating = false
            selectedExternalApps.removeAll()
            scanLocalApps()
            scanExternalApps()
            
            if !errors.isEmpty {
                showError(title: "部分迁移失败", message: errors.joined(separator: "\n"))
            }
            
            AppLogger.shared.logContext(
                "批量还原应用结束",
                details: [
                    ("batch_id", batchID),
                    ("success_count", String(validApps.count - errors.count)),
                    ("failure_count", String(errors.count))
                ]
            )
        }
    }
    
    // MARK: - 监控器
    
    func startMonitoringLocal() {
        // Stop existing if any
        localMonitor?.stopMonitoring()
        AppLogger.shared.logContext("启动本地目录监控", details: [("path", localAppsURL.path)])
        
        let monitor = FolderMonitor(url: localAppsURL)
        monitor.startMonitoring { [weak self] in
            AppLogger.shared.logContext("检测到本地目录变化", details: [("path", "/Applications")], level: "TRACE")
            Task { @MainActor in
                self?.scanLocalApps()
            }
        }
        self.localMonitor = monitor
    }
    
    func startMonitoringExternal(url: URL) {
        externalMonitor?.stopMonitoring()
        AppLogger.shared.logContext("启动外部目录监控", details: [("path", url.path)])
        
        let monitor = FolderMonitor(url: url)
        monitor.startMonitoring { [weak self] in
            AppLogger.shared.logContext("检测到外部目录变化", details: [("path", url.path)], level: "TRACE")
            Task { @MainActor in
                self?.scanExternalApps()
            }
        }
        self.externalMonitor = monitor
    }
    
    func stopMonitoringExternal() {
        externalMonitor?.stopMonitoring()
        externalMonitor = nil
        AppLogger.shared.log("停止外部目录监控")
    }
    
    // MARK: - 静态辅助方法
    
    static func joinedAppNames(_ apps: [AppItem]) -> String {
        guard !apps.isEmpty else { return "(none)" }
        return apps.map(\.displayName).joined(separator: ", ")
    }
    
    static func summarizeStatuses(for apps: [AppItem]) -> String {
        guard !apps.isEmpty else { return "(none)" }
        let counts = Dictionary(grouping: apps, by: \.status).map { key, value in
            "\(key)=\(value.count)"
        }
        return counts.sorted().joined(separator: ", ")
    }
    
    static func migrationSkipReason(
        for app: AppItem,
        allowAppStoreMigration: Bool,
        allowIOSAppMigration: Bool
    ) -> String? {
        if app.isSystemApp { return "system_app" }
        if app.isRunning { return "running" }
        if app.status == "已链接" { return "already_linked" }
        if app.isIOSApp && !allowIOSAppMigration { return "ios_migration_disabled" }
        if app.isAppStoreApp && !allowAppStoreMigration { return "app_store_migration_disabled" }
        return nil
    }
}
