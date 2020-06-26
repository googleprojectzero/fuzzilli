import XCTest

import FuzzilliTests

var tests = [XCTestCaseEntry]()
tests += FuzzilliTests.__allTests()

XCTMain(tests)
