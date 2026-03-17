//
//  ContentView.swift
//  AppPorts
//
//  Created by shimoko.com on 2025/11/18.
//

import SwiftUI
import AppKit

// NOTE: AppItem and AppMoverError are in AppModels.swift
// NOTE: AppLogger is in Services/AppLogger.swift

// MARK: - UI 组件 (已提取到 Views/Components/)
// ProgressOverlay -> Views/Components/ProgressOverlay.swift
// StatusBadge -> Views/Components/StatusBadge.swift
// AppIconView -> Views/Components/AppIconView.swift
// AppRowView -> Views/Components/AppRowView.swift



// MARK: - 主视图
struct ContentView: View {

    @StateObject private var viewModel = AppListViewModel()
    
    // Tab 状态（保留在视图中，因为与 UI 直接相关）
    enum MainTab { case apps, dataDirs }
    @State private var mainTab: MainTab = .apps

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Toolbar
            HStack(spacing: 16) {
                // Tab 切换器
                HStack(spacing: 2) {
                    TabButton(title: "📦 " + "应用".localized, isSelected: mainTab == .apps) {
                        withAnimation { mainTab = .apps }
                    }
                    TabButton(title: "🗄️ " + "数据目录".localized, isSelected: mainTab == .dataDirs) {
                        withAnimation { mainTab = .dataDirs }
                    }
                }
                .padding(3)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                if mainTab == .apps {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索应用 (本地 / 外部)...".localized, text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                    // Sort Button
                    Menu {
                        Picker("排序方式".localized, selection: $viewModel.sortOption) {
                            Text("按名称".localized).tag(AppListViewModel.SortOption.name)
                            Text("按大小".localized).tag(AppListViewModel.SortOption.size)
                        }
                    } label: {
                        Label("排序".localized, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("排序方式")
                }

                Spacer()

                // App Store Settings Button（始终显示）
                Button(action: { viewModel.showAppStoreSettings = true }) {
                    Label("设置".localized, systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("App Store 应用迁移设置".localized)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // MARK: - 主内容区（Tab 切换）
            if mainTab == .dataDirs {
                DataDirsView(
                    externalDriveURL: viewModel.externalDriveURL,
                    localApps: viewModel.localApps,
                    onSelectExternalDrive: viewModel.openPanelForExternalDrive
                )
            } else {

            HSplitView {
                // --- 左侧：本地应用 ---
                VStack(spacing: 0) {
                    // Header Area (Restored to original simple style)
                    HeaderView(title: "Mac 本地应用".localized, subtitle: "/Applications", icon: "macmini") {
                        viewModel.scanLocalApps()
                    }
                    
                    ZStack {
                        Color(nsColor: .controlBackgroundColor).ignoresSafeArea()
                        
                        if viewModel.filteredLocalApps.isEmpty {
                            if viewModel.searchText.isEmpty {
                                EmptyStateView(icon: "magnifyingglass", text: "正在扫描...".localized)
                            } else {
                                EmptyStateView(icon: "doc.text.magnifyingglass", text: "未找到匹配应用".localized)
                            }
                        } else {
                            List(viewModel.filteredLocalApps, selection: $viewModel.selectedLocalApps) { app in
                                AppRowView(
                                    app: app,
                                    isSelected: viewModel.selectedLocalApps.contains(app.id),
                                    showDeleteLinkButton: true,
                                    showMoveBackButton: false,
                                    onDeleteLink: viewModel.performDeleteLink,
                                    onMoveBack: viewModel.performMoveBack
                                )
                                .tag(app.id)
                                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)) // Add spacing around rows
                                .listRowSeparator(.hidden) // Keep hidden separators
                            }
                            .listStyle(.plain)
                        }
                    }
                    
                    let buttonStatus = viewModel.getMoveButtonTitle()
                    
                    ActionFooter(
                        title: buttonStatus.text,
                        icon: "arrow.right",
                        isEnabled: viewModel.canMoveOut,
                        action: viewModel.performMoveOut
                    )
                }
                .frame(minWidth: 320, maxWidth: .infinity)
                
                // --- 右侧：外部应用 ---
                VStack(spacing: 0) {
                    HeaderView(
                        title: "外部应用库".localized,
                        subtitle: viewModel.externalDriveURL?.path ?? "未选择".localized,
                        icon: "externaldrive.fill",
                        actionButtonText: "选择文件夹".localized,
                        onAction: viewModel.openPanelForExternalDrive,
                        onRefresh: { viewModel.scanExternalApps() }
                    )
                
                ZStack {
                    Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                    
                    if viewModel.externalDriveURL == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "externaldrive.badge.plus")
                                .font(.system(size: 40))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                            
                            // 【修复点 2】直接使用字面量，SwiftUI 会自动翻译
                            Text("请选择外部存储路径".localized)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Button("选择文件夹".localized) { viewModel.openPanelForExternalDrive() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                    } else if viewModel.filteredExternalApps.isEmpty {
                        EmptyStateView(icon: "folder", text: "空文件夹".localized)
                    } else {
                        List(viewModel.filteredExternalApps, selection: $viewModel.selectedExternalApps) { app in
                            AppRowView(
                                app: app,
                                isSelected: viewModel.selectedExternalApps.contains(app.id),
                                showDeleteLinkButton: false,
                                showMoveBackButton: false,
                                onDeleteLink: viewModel.performDeleteLink,
                                onMoveBack: viewModel.performMoveBack
                            )
                            .tag(app.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                    }
                }
                
                // 双按钮底部栏
                HStack(spacing: 8) {
                    // 链接回本地按钮
                    Button(action: viewModel.performLinkIn) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text(viewModel.getLinkButtonTitle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!viewModel.canLinkIn)
                    
                    // 迁移回本地按钮
                    Button(action: viewModel.performBatchMoveBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.up.left")
                            Text(viewModel.getMoveBackButtonTitle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.selectedExternalApps.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(minWidth: 320, maxWidth: .infinity)
            } // end HSplitView for mainTab == .apps
            } // end else for mainTab == .apps
        }
        .frame(minWidth: 900, minHeight: 600) // Increased window size
        .onAppear {
            viewModel.restoreExternalDrivePath()
            
            AppLogger.shared.log("主界面已出现，开始初始化扫描与监控")
            viewModel.scanLocalApps()
            
            // Start local monitoring
            viewModel.startMonitoringLocal()
            
            // Check for updates
            Task {
                do {
                    if let release = try await UpdateChecker.shared.checkForUpdates() {
                        AppLogger.shared.logContext(
                            "检测到新版本",
                            details: [
                                ("tag", release.tagName),
                                ("url", release.htmlUrl)
                            ]
                        )
                        await MainActor.run {
                            viewModel.alertTitle = "发现新版本".localized
                            viewModel.alertMessage = String(format: "发现新版本 %@。\n%@".localized, release.tagName, release.body)
                            viewModel.updateURL = URL(string: release.htmlUrl)
                            viewModel.showUpdateAlert = true
                        }
                    }
                } catch {
                    AppLogger.shared.logError("检查更新失败", error: error)
                }
            }
        }
        .onChange(of: viewModel.externalDriveURL) { oldValue, newValue in
            AppLogger.shared.logContext(
                "外部路径变更",
                details: [
                    ("old_path", oldValue?.path),
                    ("new_path", newValue?.path)
                ]
            )
            if let url = newValue {
                viewModel.startMonitoringExternal(url: url)
            } else {
                viewModel.stopMonitoringExternal()
            }
            viewModel.scanExternalApps()
        }
        
        .alert(LocalizedStringKey(viewModel.alertTitle.localized), isPresented: $viewModel.showAlert) {
            Button("好的".localized, role: .cancel) { }
        } message: {
            Text(LocalizedStringKey(viewModel.alertMessage.localized))
        }
        .alert("发现新版本".localized, isPresented: $viewModel.showUpdateAlert) {
            Button("前往下载".localized, role: .none) {
                if let url = viewModel.updateURL { NSWorkspace.shared.open(url) }
            }
            Button("以后再说".localized, role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage.localized)
        }
        // App Store 应用迁移确认弹窗
        .alert("App Store 应用".localized, isPresented: $viewModel.showAppStoreConfirm) {
            Button("继续迁移".localized, role: .none) {
                if let dest = viewModel.externalDriveURL {
                    viewModel.executeBatchMove(apps: viewModel.pendingAppStoreApps, destination: dest)
                }
                viewModel.pendingAppStoreApps = []
            }
            Button("取消".localized, role: .cancel) {
                viewModel.pendingAppStoreApps = []
            }
        } message: {
            let count = Int64(viewModel.pendingAppStoreApps.filter { viewModel.isAppStoreApp(at: $0.displayURL) }.count)
            let totalCount = Int64(viewModel.pendingAppStoreApps.count)
            if count == totalCount {
                Text(String(format: "选中的 %lld 个应用均来自 App Store，迁移时会使用 Finder 删除，您会听到垃圾桶的声音。\n\n这是正常的，应用会被安全地移动到外部存储。".localized, totalCount))
            } else {
                Text(String(format: "选中的 %lld 个应用包含 %lld 个 App Store 应用，迁移时会使用 Finder 删除，您会听到垃圾桶的声音。\n\n这是正常的，应用会被安全地移动到外部存储。".localized, totalCount, count))
            }
        }
        // App Store 设置页面
        .sheet(isPresented: $viewModel.showAppStoreSettings) {
            AppStoreSettingsView()
        }
        // 进度覆盖层
        .overlay {
            if viewModel.showProgress {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressOverlay(
                        current: viewModel.progressCurrent,
                        total: viewModel.progressTotal,
                        appName: viewModel.progressAppName,
                        copiedBytes: viewModel.progressBytes,
                        totalBytes: viewModel.progressTotalBytes
                    )
                }
            }
        }
    }
    
    // MARK: - 辅助组件
    
    struct HeaderView: View {
        let title: String
        let subtitle: String // subtitle 可能是路径，也可能是 "未选择"
        let icon: String
        var actionButtonText: String? = nil
        var onAction: (() -> Void)? = nil
        let onRefresh: () -> Void
        
        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                        .frame(width: 32)
                        
                    VStack(alignment: .leading, spacing: 4) {
                        // 将传入的 title 字符串转换为 Key，触发翻译
                        Text(title.localized)
                            .font(.headline)
                        
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(subtitle)
                    }
                    Spacer()
                    
                    if let btnText = actionButtonText, let action = onAction {

                        Button(btnText.localized, action: action)
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                    }
                    
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 8)
                    .help("刷新列表".localized)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
            }
            .background(.ultraThinMaterial) // Glassmorphism
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
    
    struct ActionFooter: View {
        let title: String
        let icon: String
        let isEnabled: Bool
        let action: () -> Void
        
        var body: some View {
            VStack(spacing: 0) {
                Divider()
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: -1)
                
                HStack {
                    Spacer()
                    Button(action: action) {
                        HStack(spacing: 8) {
                            Text(title.localized)
                                .fontWeight(.semibold)
                            Image(systemName: icon)
                        }
                        .frame(maxWidth: .infinity) // Fill width
                        .frame(height: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEnabled)
                    .controlSize(.large)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .background(.bar) // Standard bar material
        }
    }
    
    struct EmptyStateView: View {
        let icon: String
        let text: String
        
        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.3))

                Text(text.localized)
                .foregroundColor(.secondary.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Tab 切换按钮（顶部工具栏用）
    struct TabButton: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title.localized)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
