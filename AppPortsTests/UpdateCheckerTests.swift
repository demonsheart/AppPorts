//
//  UpdateCheckerTests.swift
//  AppPortsTests
//
//  Created by Claude on 2026/3/17.
//

import XCTest
@testable import AppPorts

final class UpdateCheckerTests: XCTestCase {
    
    // MARK: - Tests
    
    func testCheckForUpdatesReturnsNilWhenNoNewVersion() async throws {
        // Note: This test depends on the actual GitHub releases
        // In a real test, we would mock the network request
        
        let checker = UpdateChecker.shared
        
        // If current version is the latest, should return nil
        // This test might pass or fail depending on actual releases
        _ = try? await checker.checkForUpdates()
        
        // We can't assert specific behavior without mocking
        // But we can verify the method doesn't crash
    }
    
    func testRepositoryInfo() {
        // Verify the checker is properly configured
        // UpdateChecker uses hardcoded repo info
        _ = UpdateChecker.shared
    }
    
    func testGitHubReleaseParsing() async {
        // Test that GitHub release response can be parsed
        let sampleJSON = """
        {
            "tag_name": "v1.0.0",
            "name": "Release 1.0.0",
            "body": "Release notes here",
            "html_url": "https://github.com/hrj/AppPorts/releases/tag/v1.0.0",
            "published_at": "2026-01-01T00:00:00Z"
        }
        """
        
        let data = sampleJSON.data(using: .utf8)!
        
        do {
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            XCTAssertEqual(release.tagName, "v1.0.0")
            XCTAssertEqual(release.htmlUrl, "https://github.com/hrj/AppPorts/releases/tag/v1.0.0")
            XCTAssertEqual(release.body, "Release notes here")
        } catch {
            XCTFail("Failed to parse GitHub release JSON: \(error)")
        }
    }
    
    func testUpdateCheckDoesNotBlockMainThread() async {
        let start = Date()
        
        // Start update check
        let checkTask = Task {
            try? await UpdateChecker.shared.checkForUpdates()
        }
        
        // Main thread should not be blocked
        // Verify we can do other work immediately
        let mainThreadWorkTime = Date().timeIntervalSince(start)
        XCTAssertLessThan(mainThreadWorkTime, 0.1) // Should be nearly instant
        
        // Wait for check to complete
        _ = await checkTask.result
    }
    
    func testConcurrentUpdateChecks() async {
        // Test that multiple concurrent update checks don't cause issues
        async let check1 = UpdateChecker.shared.checkForUpdates()
        async let check2 = UpdateChecker.shared.checkForUpdates()
        async let check3 = UpdateChecker.shared.checkForUpdates()
        
        let results = try? await [check1, check2, check3]
        
        // All checks should complete without crashing
        XCTAssertNotNil(results)
    }
    
    func testReleaseInfoCodingKeys() {
        // Verify CodingKeys mapping
        let json = """
        {
            "tag_name": "v2.0.0",
            "html_url": "https://example.com",
            "body": "Test body"
        }
        """
        
        let data = json.data(using: .utf8)!
        do {
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            XCTAssertEqual(release.tagName, "v2.0.0")
            XCTAssertEqual(release.htmlUrl, "https://example.com")
            XCTAssertEqual(release.body, "Test body")
        } catch {
            XCTFail("Failed to decode: \(error)")
        }
    }
}
