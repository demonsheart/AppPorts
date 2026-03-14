import XCTest
@testable import AppPorts

final class AppScannerTests: XCTestCase {
    private let fileManager = FileManager.default

    func testDisplayedSizeForWholeAppSymlinkUsesLocalPortalFootprint() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let externalAppURL = workspace.externalRootURL.appendingPathComponent("Cherry Studio.app")
        let localAppURL = workspace.localAppsURL.appendingPathComponent("Cherry Studio.app")
        try createAppBundle(at: externalAppURL, payloadSize: 4096)
        try fileManager.createSymbolicLink(at: localAppURL, withDestinationURL: externalAppURL)

        let scanner = AppScanner()
        let linkedLocalItem = AppItem(name: "Cherry Studio.app", path: localAppURL, status: "已链接")

        let displayedSize = await scanner.calculateDisplayedSize(for: linkedLocalItem, isLocalEntry: true)
        let logicalSize = await scanner.calculateDirectorySize(at: localAppURL)

        XCTAssertGreaterThan(logicalSize, 0)
        XCTAssertLessThan(displayedSize, logicalSize)
    }

    func testDisplayedSizeForDeepWrapperUsesWrapperFootprint() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let externalAppURL = workspace.externalRootURL.appendingPathComponent("Notion.app")
        let localAppURL = workspace.localAppsURL.appendingPathComponent("Notion.app")
        try createAppBundle(at: externalAppURL, payloadSize: 4096)

        try fileManager.createDirectory(at: localAppURL, withIntermediateDirectories: false)
        try fileManager.createSymbolicLink(
            at: localAppURL.appendingPathComponent("Contents"),
            withDestinationURL: externalAppURL.appendingPathComponent("Contents")
        )

        let scanner = AppScanner()
        let linkedLocalItem = AppItem(name: "Notion.app", path: localAppURL, status: "已链接")

        let displayedSize = await scanner.calculateDisplayedSize(for: linkedLocalItem, isLocalEntry: true)
        let logicalSize = await scanner.calculateDirectorySize(at: localAppURL)

        XCTAssertGreaterThan(logicalSize, 0)
        XCTAssertLessThan(displayedSize, logicalSize)
    }

    func testDisplayedSizeForExternalEntryKeepsLogicalContentSize() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let externalAppURL = workspace.externalRootURL.appendingPathComponent("Cherry Studio.app")
        try createAppBundle(at: externalAppURL, payloadSize: 4096)

        let scanner = AppScanner()
        let externalItem = AppItem(name: "Cherry Studio.app", path: externalAppURL, status: "已链接")

        let displayedSize = await scanner.calculateDisplayedSize(for: externalItem, isLocalEntry: false)
        let logicalSize = await scanner.calculateDirectorySize(at: externalAppURL)

        XCTAssertEqual(displayedSize, logicalSize)
    }

    func testScanExternalAppsIncludesLinkedSuiteFolderNestedUnderSelectedRoot() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let nestedSuitesURL = workspace.externalRootURL.appendingPathComponent("Suites")
        let externalFolderURL = nestedSuitesURL.appendingPathComponent("Microsoft Office")
        let localFolderURL = workspace.localAppsURL.appendingPathComponent("Microsoft Office")

        try fileManager.createDirectory(at: nestedSuitesURL, withIntermediateDirectories: true)
        try createAppBundle(at: externalFolderURL.appendingPathComponent("Word.app"), payloadSize: 1024)
        try createAppBundle(at: externalFolderURL.appendingPathComponent("Excel.app"), payloadSize: 1024)
        try fileManager.createSymbolicLink(at: localFolderURL, withDestinationURL: externalFolderURL)

        let scanner = AppScanner()
        let externalItems = await scanner.scanExternalApps(at: workspace.externalRootURL, localAppsDir: workspace.localAppsURL)

        let linkedFolder = try XCTUnwrap(externalItems.first { $0.path.standardizedFileURL == externalFolderURL.standardizedFileURL })
        XCTAssertEqual(linkedFolder.status, "已链接")
        XCTAssertTrue(linkedFolder.isFolder)
        XCTAssertEqual(linkedFolder.appCount, 2)
    }

    func testScanLocalAppsDetectsLinkedSuiteFolderSymlink() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let externalFolderURL = workspace.externalRootURL.appendingPathComponent("Microsoft Office")
        let localFolderURL = workspace.localAppsURL.appendingPathComponent("Microsoft Office")

        try createAppBundle(at: externalFolderURL.appendingPathComponent("Word.app"), payloadSize: 1024)
        try createAppBundle(at: externalFolderURL.appendingPathComponent("Excel.app"), payloadSize: 1024)
        try fileManager.createSymbolicLink(at: localFolderURL, withDestinationURL: externalFolderURL)

        let scanner = AppScanner()
        let localItems = await scanner.scanLocalApps(at: workspace.localAppsURL, runningAppURLs: [])

        let linkedFolder = try XCTUnwrap(localItems.first { $0.path.standardizedFileURL == localFolderURL.standardizedFileURL })
        XCTAssertEqual(linkedFolder.status, "已链接")
        XCTAssertTrue(linkedFolder.isFolder)
        XCTAssertEqual(linkedFolder.appCount, 2)
    }

    private func makeWorkspace() throws -> (rootURL: URL, localAppsURL: URL, externalRootURL: URL) {
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("AppScannerTests-\(UUID().uuidString)")
        let localAppsURL = rootURL.appendingPathComponent("Applications")
        let externalRootURL = rootURL.appendingPathComponent("External")

        try fileManager.createDirectory(at: localAppsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalRootURL, withIntermediateDirectories: true)

        return (rootURL, localAppsURL, externalRootURL)
    }

    private func cleanupWorkspace(_ rootURL: URL) {
        try? fileManager.removeItem(at: rootURL)
    }

    private func createAppBundle(at appURL: URL, payloadSize: Int) throws {
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let executableURL = macOSURL.appendingPathComponent(appURL.deletingPathExtension().lastPathComponent)
        try Data(repeating: 0x41, count: payloadSize).write(to: executableURL)

        let payloadURL = resourcesURL.appendingPathComponent("payload.bin")
        try Data(repeating: 0x42, count: payloadSize).write(to: payloadURL)
    }
}
