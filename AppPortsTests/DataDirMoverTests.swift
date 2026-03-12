import XCTest
@testable import AppPorts

final class DataDirMoverTests: XCTestCase {
    private let fileManager = FileManager.default
    private var originalLogEnabledValue: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalLogEnabledValue = UserDefaults.standard.object(forKey: "LogEnabled")
        UserDefaults.standard.set(false, forKey: "LogEnabled")
    }

    override func tearDownWithError() throws {
        if let originalLogEnabledValue {
            UserDefaults.standard.set(originalLogEnabledValue, forKey: "LogEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "LogEnabled")
        }

        try super.tearDownWithError()
    }

    func testMigrateAndRestoreRoundTripForApplicationSupportDirectory() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let localDataURL = workspace.homeURL
            .appendingPathComponent("Library/Application Support/com.example.focus")
        let externalBaseURL = workspace.externalRootURL
            .appendingPathComponent("Library/Application Support")
        let externalDataURL = externalBaseURL.appendingPathComponent(localDataURL.lastPathComponent)

        try createDirectoryWithPayload(at: localDataURL, payload: "focus-state")

        let item = DataDirItem(
            name: "Focus",
            path: localDataURL,
            type: .applicationSupport,
            priority: .critical,
            description: "Test payload",
            isMigratable: true
        )

        let mover = DataDirMover(homeDir: workspace.homeURL)
        try await mover.migrate(item: item, to: externalBaseURL, progressHandler: nil)

        try assertSymlink(localDataURL, pointsTo: externalDataURL)
        XCTAssertTrue(fileManager.fileExists(atPath: markerURL(for: externalDataURL).path))
        XCTAssertEqual(try String(contentsOf: externalDataURL.appendingPathComponent("payload.txt")), "focus-state")

        try await mover.restore(
            item: DataDirItem(
                name: item.name,
                path: localDataURL,
                type: item.type,
                priority: item.priority,
                description: item.description,
                status: "已链接",
                isMigratable: true
            ),
            progressHandler: nil
        )

        try assertRealDirectory(localDataURL)
        XCTAssertEqual(try String(contentsOf: localDataURL.appendingPathComponent("payload.txt")), "focus-state")
        XCTAssertFalse(fileManager.fileExists(atPath: externalDataURL.path))
    }

    func testMigrateRollsBackWhenSymlinkCreationFails() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let localDataURL = workspace.homeURL
            .appendingPathComponent("Library/Caches/com.example.rollback")
        let externalBaseURL = workspace.externalRootURL
            .appendingPathComponent("Library/Caches")
        let externalDataURL = externalBaseURL.appendingPathComponent(localDataURL.lastPathComponent)

        try createDirectoryWithPayload(at: localDataURL, payload: "rollback-safe")

        let item = DataDirItem(
            name: "Rollback",
            path: localDataURL,
            type: .caches,
            priority: .optional,
            description: "Test payload",
            isMigratable: true
        )

        let mover = DataDirMover(homeDir: workspace.homeURL, failSymlinkCreation: true)

        do {
            try await mover.migrate(item: item, to: externalBaseURL, progressHandler: nil)
            XCTFail("Expected migrate to fail when symlink creation is forced to fail")
        } catch let error as DataDirError {
            guard case .symlinkFailed = error else {
                return XCTFail("Expected symlinkFailed, got \(error)")
            }
        }

        try assertRealDirectory(localDataURL)
        XCTAssertEqual(try String(contentsOf: localDataURL.appendingPathComponent("payload.txt")), "rollback-safe")
        XCTAssertFalse(fileManager.fileExists(atPath: externalDataURL.path))
    }

    func testMigrateRemovesPartialExternalDirectoryWhenCopyFails() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let localDataURL = workspace.homeURL
            .appendingPathComponent("Library/Containers/com.example.permission")
        let externalBaseURL = workspace.externalRootURL
            .appendingPathComponent("Library/Containers")
        let externalDataURL = externalBaseURL.appendingPathComponent(localDataURL.lastPathComponent)
        let unreadableFileURL = localDataURL.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")

        try fileManager.createDirectory(at: localDataURL, withIntermediateDirectories: true)
        try "ok".write(
            to: localDataURL.appendingPathComponent("payload.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "blocked".write(
            to: unreadableFileURL,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableFileURL.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableFileURL.path) }

        let item = DataDirItem(
            name: "PermissionDenied",
            path: localDataURL,
            type: .containers,
            priority: .critical,
            description: "Permission failure fixture",
            isMigratable: true
        )

        let mover = DataDirMover(homeDir: workspace.homeURL)

        do {
            try await mover.migrate(item: item, to: externalBaseURL, progressHandler: nil)
            XCTFail("Expected migrate to fail when source copy encounters an unreadable file")
        } catch let error as DataDirError {
            guard case .copyFailed = error else {
                return XCTFail("Expected copyFailed, got \(error)")
            }
        }

        try assertRealDirectory(localDataURL)
        XCTAssertTrue(fileManager.fileExists(atPath: localDataURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: externalDataURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: externalBaseURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: workspace.externalRootURL.path))
    }

    func testNormalizeManagedLinkMovesDataToNormalizedDestination() async throws {
        let workspace = try makeWorkspace()
        defer { cleanupWorkspace(workspace.rootURL) }

        let localDataURL = workspace.homeURL
            .appendingPathComponent("Library/Application Support/com.example.normalize")
        let currentExternalURL = workspace.rootURL
            .appendingPathComponent("ManualStore/com.example.normalize")
        let normalizedExternalURL = workspace.externalRootURL
            .appendingPathComponent("Library/Application Support/com.example.normalize")

        try createDirectoryWithPayload(at: currentExternalURL, payload: "normalized")

        let mover = DataDirMover(homeDir: workspace.homeURL)
        try await mover.createLink(localPath: localDataURL, externalPath: currentExternalURL)

        try await mover.normalizeManagedLink(
            localPath: localDataURL,
            currentExternalPath: currentExternalURL,
            normalizedExternalPath: normalizedExternalURL
        )

        try assertSymlink(localDataURL, pointsTo: normalizedExternalURL)
        XCTAssertFalse(fileManager.fileExists(atPath: currentExternalURL.path))
        XCTAssertEqual(try String(contentsOf: normalizedExternalURL.appendingPathComponent("payload.txt")), "normalized")
        XCTAssertTrue(fileManager.fileExists(atPath: markerURL(for: normalizedExternalURL).path))
    }

    private func makeWorkspace() throws -> (rootURL: URL, homeURL: URL, externalRootURL: URL) {
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("DataDirMoverTests-\(UUID().uuidString)")
        let homeURL = rootURL.appendingPathComponent("Home")
        let externalRootURL = rootURL.appendingPathComponent("External")

        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalRootURL, withIntermediateDirectories: true)

        return (rootURL, homeURL, externalRootURL)
    }

    private func cleanupWorkspace(_ rootURL: URL) {
        try? fileManager.removeItem(at: rootURL)
    }

    private func createDirectoryWithPayload(at directoryURL: URL, payload: String) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try payload.write(
            to: directoryURL.appendingPathComponent("payload.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func assertSymlink(
        _ localURL: URL,
        pointsTo destinationURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let destination = try fileManager.destinationOfSymbolicLink(atPath: localURL.path)
        let resolvedDestination = URL(
            fileURLWithPath: destination,
            relativeTo: localURL.deletingLastPathComponent()
        ).standardizedFileURL

        XCTAssertEqual(
            resolvedDestination,
            destinationURL.standardizedFileURL,
            file: file,
            line: line
        )
    }

    private func assertRealDirectory(
        _ directoryURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        XCTAssertEqual(values.isDirectory, true, file: file, line: line)
        XCTAssertThrowsError(
            try fileManager.destinationOfSymbolicLink(atPath: directoryURL.path),
            file: file,
            line: line
        )
    }

    private func markerURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(".appports-link-metadata.plist")
    }
}
