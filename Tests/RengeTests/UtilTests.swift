//
//  UtilTests.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/09/14.
//

import XCTest
@testable import Renge

class UtilTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}
	
	func testExample() {
		// This is an example of a functional test case.
		// Use XCTAssert and related functions to verify your tests produce the correct results.
	}
	
	func testHMSToSeconds() {
		XCTAssertEqual(Util.hmsToSeconds(hmsTime: "10h5m2s"), 36302)
		XCTAssertEqual(Util.hmsToSeconds(hmsTime: "3h"), 10800)
		XCTAssertEqual(Util.hmsToSeconds(hmsTime: "15m"), 900)
		XCTAssertEqual(Util.hmsToSeconds(hmsTime: "35m8s"), 2108)
		XCTAssertEqual(Util.hmsToSeconds(hmsTime: "16s"), 16)
	}
	
	func testStringScanner() {
		var test1 = StringScanner("This is\n a test　YAY8meow")
		XCTAssertEqual(test1.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true), "This")
		XCTAssertEqual(test1.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true), "is")
		XCTAssertEqual(test1.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true), "a")
		XCTAssertEqual(test1.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true), "test")
		XCTAssertEqual(test1.read(untilInSet: CharacterSet.whitespacesAndNewlines.union(["8"]), clearDelimeter: true), "YAY")
		XCTAssertEqual(test1.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true), "meow")
		XCTAssertEqual(test1.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true), nil)
		var test2 = StringScanner("Yay.yay.a")
		XCTAssertEqual(test2.read(toNext: "."), "Yay")
		XCTAssertEqual(test2.read(toNext: ".", clearDelimeter: false), "yay")
		XCTAssertEqual(test2.read(toNext: "."), "")
		XCTAssertEqual(test2.read(toNext: "."), "a")
		XCTAssertEqual(test2.rest, "")
		var test3 = StringScanner("AbcdABcD")
		XCTAssertEqual(test3.remove(prefix: "abcd", matchingCase: true), false)
		XCTAssertEqual(test3.remove(prefix: "Abcd", matchingCase: true), true)
		XCTAssertEqual(test3.remove(prefix: "abcd", matchingCase: false), true)
		XCTAssertEqual(test3.rest, "")
	}

}
