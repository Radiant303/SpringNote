import Cocoa
import FlutterMacOS
import XCTest
@testable import spring_note

final class RunnerTests: XCTestCase {

  func testDesktopWidgetStateDefaultsToLightMode() {
    let state = DesktopWidgetState()

    XCTAssertFalse(state.darkMode)
  }

  func testDesktopWidgetStateReadsAndRetainsDarkMode() {
    var state = DesktopWidgetState()

    state.update(with: ["darkMode": true])

    XCTAssertTrue(state.darkMode)

    state.update(with: ["progress": 0.42])

    XCTAssertTrue(state.darkMode)
    XCTAssertEqual(state.progress, 0.42, accuracy: 0.001)

    state.update(with: ["darkMode": false])

    XCTAssertFalse(state.darkMode)
  }

  func testDesktopWidgetColorsPaletteMatchesLightAndDarkThemes() {
    let light = DesktopWidgetColors.palette(darkMode: false)
    let dark = DesktopWidgetColors.palette(darkMode: true)

    assertColor(light.surface, red: 1, green: 1, blue: 1)
    assertColor(light.text, red: 0.09, green: 0.09, blue: 0.09)
    assertColor(light.textSubtle, red: 0.4, green: 0.4, blue: 0.4)
    assertColor(light.accent, red: 0.06, green: 0.73, blue: 0.51)
    assertColor(dark.surface, red: 27 / 255, green: 27 / 255, blue: 27 / 255)
    assertColor(dark.text, red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    assertColor(dark.textSubtle, red: 154 / 255, green: 154 / 255, blue: 154 / 255)
    assertColor(dark.accent, red: 0.06, green: 0.73, blue: 0.51)
  }

  func testDesktopWidgetViewInvalidatesDisplayWhenThemeStateChanges() {
    let controller = DesktopWidgetWindowController()
    let view = DesktopWidgetView(
      controller: controller,
      frame: NSRect(x: 0, y: 0, width: 64, height: 64)
    )
    var nextState = view.state
    nextState.darkMode = true

    view.needsDisplay = false
    view.state = nextState

    XCTAssertTrue(view.needsDisplay)

    view.needsDisplay = false
    view.expanded.toggle()

    XCTAssertTrue(view.needsDisplay)
  }

  private func assertColor(
    _ color: NSColor,
    red expectedRed: CGFloat,
    green expectedGreen: CGFloat,
    blue expectedBlue: CGFloat,
    alpha expectedAlpha: CGFloat = 1,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let rgbColor = color.usingColorSpace(.genericRGB) else {
      XCTFail("Expected color to convert to generic RGB", file: file, line: line)
      return
    }

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    XCTAssertEqual(red, expectedRed, accuracy: 0.005, file: file, line: line)
    XCTAssertEqual(green, expectedGreen, accuracy: 0.005, file: file, line: line)
    XCTAssertEqual(blue, expectedBlue, accuracy: 0.005, file: file, line: line)
    XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.005, file: file, line: line)
  }

}
