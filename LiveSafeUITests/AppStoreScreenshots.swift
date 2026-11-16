import CoreLocation
import XCTest

/// Stages and captures the App Store screenshots.
///
/// Driven by `Assets/App Store/capture.sh`, which grants location access and says
/// where to write through `SCREENSHOT_DIR` and which language to use through
/// `SCREENSHOT_LANGUAGE`. Without them the tests skip, so they stay out of the way
/// of an ordinary test run.
final class AppStoreScreenshots: XCTestCase {
    /// Where the sheet sits for a shot.
    private enum Sheet {
        /// Collapsed to the search field, leaving the map.
        case compact
        /// Halfway up, as the app opens.
        case medium
        /// A screen pushed from the sheet, which raises it.
        case screen(Screen)
    }

    private enum Screen {
        case compass, offlineData, resources

        /// The row's title, which is translated.
        func label(_ language: String) -> String {
            switch self {
            case .compass: language == "ja" ? "近くの避難場所" : "Nearest Evacuation Sites"
            case .offlineData: language == "ja" ? "オフラインデータ" : "Offline Data"
            case .resources: language == "ja" ? "役立つ情報" : "Useful Resources"
            }
        }
    }

    private struct Shot {
        let name: String
        let place: CLLocationCoordinate2D
        var layers: [String] = []
        var shelters: [String] = []
        let sheet: Sheet
        var isDark = false
    }

    /// 江戸川区, between the Arakawa and Edogawa rivers, where a flood would run deep.
    private static let edogawa = CLLocationCoordinate2D(latitude: 35.6905, longitude: 139.8680)
    /// 鎌倉, on the coast.
    private static let kamakura = CLLocationCoordinate2D(latitude: 35.3110, longitude: 139.5470)
    /// 広島市安佐南区, at the foot of hills lined with warning zones.
    private static let asaminami = CLLocationCoordinate2D(latitude: 34.4890, longitude: 132.4660)

    private static let shots = [
        Shot(name: "01-flood", place: edogawa, layers: ["01_flood_l2_shinsuishin_data"],
             shelters: ["evacuationSite"], sheet: .compact),
        Shot(name: "02-layers", place: kamakura,
             layers: ["01_flood_l2_shinsuishin_data", "04_tsunami_newlegend_data"], sheet: .medium),
        Shot(name: "03-compass", place: edogawa, sheet: .screen(.compass)),
        Shot(name: "04-offline", place: edogawa, sheet: .screen(.offlineData)),
        Shot(name: "05-resources", place: edogawa, sheet: .screen(.resources)),
        Shot(name: "06-dark", place: asaminami,
             layers: ["05_dosekiryukeikaikuiki", "05_kyukeishakeikaikuiki"],
             shelters: ["evacuationSite"], sheet: .compact, isDark: true),
    ]

    private var directory: URL!
    private var language = "en"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("run through Assets/App Store/capture.sh")
        }
        directory = URL(fileURLWithPath: path)
        language = environment["SCREENSHOT_LANGUAGE"] ?? "en"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func testScreens() throws {
        defer { XCUIDevice.shared.appearance = .light }
        for shot in Self.shots {
            try capture(shot)
        }
    }

    private func capture(_ shot: Shot) throws {
        // Set every time: reading the current appearance back is not reliable.
        XCUIDevice.shared.appearance = shot.isDark ? .dark : .light
        // The switch reaches apps a moment after it is made.
        Thread.sleep(forTimeInterval: 3)
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: shot.place.latitude, longitude: shot.place.longitude))
        launch(layers: shot.layers, shelters: shot.shelters)
        locate()

        switch shot.sheet {
        case .compact:
            collapseSheet()
        case .medium:
            break
        case .screen(let screen):
            open(screen)
        }
        // Let the map tiles and pins load and the sheet finish moving.
        Thread.sleep(forTimeInterval: 10)
        let file = directory.appendingPathComponent("\(shot.name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
    }

    // MARK: - Steps

    private func launch(layers: [String], shelters: [String]) {
        app?.terminate()
        app = XCUIApplication()
        let locale = language == "ja" ? "ja_JP" : "en_US"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        // The layers the app restores from its defaults at launch.
        app.launchArguments += ["-EnabledHazardLayers", Self.plistArray(layers)]
        app.launchArguments += ["-EnabledShelterKinds", Self.plistArray(shelters)]
        app.launch()
    }

    /// Moves the map to the simulated location.
    private func locate() {
        let button = app.buttons[language == "ja" ? "現在地" : "Current Location"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "missing the location button")
        // The sheet animates in over the first moments, and a tap then is lost.
        Thread.sleep(forTimeInterval: 2)
        button.tap()
        Thread.sleep(forTimeInterval: 3)
    }

    private var searchField: XCUIElement { app.textFields.firstMatch }

    /// Drags the sheet down by its search field until only the field is left.
    private func collapseSheet() {
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "missing the search field")
        let bottom = app.frame.height * 0.8
        // A drag while the sheet is still settling is sometimes lost, so it is tried again.
        for _ in 0..<4 where searchField.frame.minY < bottom {
            let start = searchField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            start.press(forDuration: 0.1, thenDragTo: end)
            Thread.sleep(forTimeInterval: 1.5)
        }
        XCTAssertGreaterThanOrEqual(searchField.frame.minY, bottom, "the sheet never collapsed")
    }

    /// Opens a screen from the list in the sheet, then waits for it to be worth showing.
    private func open(_ screen: Screen) {
        let row = app.buttons[screen.label(language)].firstMatch
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "missing the sheet's list")
        for _ in 0..<6 where !(row.exists && row.isHittable) {
            list.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "\(screen) is not in the list")
        row.tap()

        switch screen {
        case .compass:
            let live = app.staticTexts[language == "ja" ? "最新データ" : "Live Data"]
            XCTAssertTrue(live.waitForExistence(timeout: 60), "the nearest sites never loaded")
        case .offlineData:
            let download = app.buttons[language == "ja" ? "今すぐダウンロード" : "Download Now"]
            if download.waitForExistence(timeout: 10) {
                download.tap()
            }
            let upToDate = app.staticTexts[language == "ja" ? "最新の状態です" : "Up to Date"]
            XCTAssertTrue(upToDate.waitForExistence(timeout: 300), "the evacuation site lists never downloaded")
            expandSheet()
        case .resources:
            Thread.sleep(forTimeInterval: 1)
            expandSheet()
        }
    }

    /// Drags the sheet up by its navigation bar to fill the screen.
    private func expandSheet() {
        let bar = app.navigationBars.firstMatch
        guard bar.waitForExistence(timeout: 5) else { return }
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// An old-style property list array, as `NSArgumentDomain` reads one.
    private static func plistArray(_ values: [String]) -> String {
        "(" + values.map { "\"\($0)\"" }.joined(separator: ", ") + ")"
    }
}
