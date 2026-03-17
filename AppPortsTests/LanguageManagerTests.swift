//
//  LanguageManagerTests.swift
//  AppPortsTests
//
//  Created by Claude on 2026/3/17.
//

import XCTest
@testable import AppPorts

final class LanguageManagerTests: XCTestCase {
    private var originalLanguage: String?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        originalLanguage = UserDefaults.standard.string(forKey: "selectedLanguage")
    }
    
    override func tearDownWithError() throws {
        if let originalLanguage {
            UserDefaults.standard.set(originalLanguage, forKey: "selectedLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedLanguage")
        }
        try super.tearDownWithError()
    }
    
    // MARK: - Tests
    
    func testDefaultLanguageIsSystem() {
        // Clear saved preference
        UserDefaults.standard.removeObject(forKey: "selectedLanguage")
        
        // LanguageManager.shared will use the default "system" value
        XCTAssertEqual(LanguageManager.shared.language, "system")
    }
    
    func testSetLanguagePersists() {
        // Set to English
        LanguageManager.shared.language = "en"
        XCTAssertEqual(LanguageManager.shared.language, "en")
        
        // Verify persistence
        let savedCode = UserDefaults.standard.string(forKey: "selectedLanguage")
        XCTAssertEqual(savedCode, "en")
        
        // Set to Chinese
        LanguageManager.shared.language = "zh-Hans"
        XCTAssertEqual(LanguageManager.shared.language, "zh-Hans")
        
        // Verify persistence
        let savedCode2 = UserDefaults.standard.string(forKey: "selectedLanguage")
        XCTAssertEqual(savedCode2, "zh-Hans")
    }
    
    func testAvailableLanguagesIncludesCommonLanguages() {
        let languages = AppLanguageCatalog.languages
        
        // Should include English
        XCTAssertNotNil(languages.first { $0.code == "en" })
        
        // Should include Simplified Chinese
        XCTAssertNotNil(languages.first { $0.code == "zh-Hans" })
        
        // Should include Japanese
        XCTAssertNotNil(languages.first { $0.code == "ja" })
        
        // Should include system option
        XCTAssertNotNil(languages.first { $0.code == "system" })
    }
    
    func testLanguageDisplayNames() {
        let languages = AppLanguageCatalog.languages
        
        // English should have display name
        let english = languages.first { $0.code == "en" }
        XCTAssertNotNil(english?.displayName)
        XCTAssertFalse(english!.displayName.isEmpty)
        
        // Chinese should have display name
        let chinese = languages.first { $0.code == "zh-Hans" }
        XCTAssertNotNil(chinese?.displayName)
        XCTAssertFalse(chinese!.displayName.isEmpty)
    }
    
    func testLanguageManagerPublishesChanges() {
        var receivedCodes: [String] = []
        
        let expectation = expectation(description: "Language change published")
        
        let cancellable = LanguageManager.shared.$language.sink { language in
            receivedCodes.append(language)
            if receivedCodes.count == 3 {
                expectation.fulfill()
            }
        }
        
        // Initial value
        XCTAssertEqual(receivedCodes.first, LanguageManager.shared.language)
        
        // Change to English
        LanguageManager.shared.language = "en"
        
        // Change to Chinese
        LanguageManager.shared.language = "zh-Hans"
        
        wait(for: [expectation], timeout: 1.0)
        
        // Should have received: initial, en, zh-Hans
        XCTAssertTrue(receivedCodes.contains("en"))
        XCTAssertTrue(receivedCodes.contains("zh-Hans"))
        
        cancellable.cancel()
    }
    
    func testSystemLanguageReturnsSystemLocale() {
        LanguageManager.shared.language = "system"
        
        // When using system, the locale should match system locale
        let locale = LanguageManager.shared.locale
        let systemLocale = Locale.current
        
        // The locale identifier should match
        XCTAssertEqual(locale.identifier, systemLocale.identifier)
    }
    
    func testSpecificLanguageReturnsCorrectLocale() {
        LanguageManager.shared.language = "en"
        
        let locale = LanguageManager.shared.locale
        XCTAssertEqual(locale.language.languageCode?.identifier, "en")
    }
    
    func testLocalizedStringExtension() {
        // Test that the localized extension works
        LanguageManager.shared.language = "system"
        
        // Basic test - just verify it doesn't crash and returns something
        let localized = "Hello".localized
        XCTAssertFalse(localized.isEmpty)
    }
}
