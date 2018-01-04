import Foundation
import SwiftDiscord

public func Testing() {}

/// Namespace for utility methods
enum Util {
	static func makeListingMessage(items: [String], delimeter: String, prefix: String = "", postfix: String = "") -> DiscordMessage {
		var groups: [(count: Int, items: [String])] = []
		for item in items {
			if let current = groups.last, current.count + item.count < 1900 {
				groups[groups.count - 1].count += item.count + delimeter.count
				groups[groups.count - 1].items.append(item)
			}
			else {
				groups.append((item.count + prefix.count + postfix.count, [item]))
			}
		}
		if groups.count == 0 {
			return DiscordMessage(content: "None")
		}
		else if groups.count == 1 {
			return DiscordMessage(content: "\(prefix)\(groups[0].items.joined(separator: delimeter))\(postfix)")
		}
		else {
			let fields = groups.map { DiscordEmbed.Field(name: "\u{200B}", value: "\(prefix)\($1.joined(separator: delimeter))\(postfix)", inline: false) }
			return DiscordMessage(content: "", embed: DiscordEmbed(title: "", description: "", fields: fields))
		}
	}

	static func makeFields(items: [String], title: String, delimeter: String, prefix: String = "", postfix: String = "") -> [DiscordEmbed.Field] {
		var groups: [(count: Int, items: [String])] = []
		for item in items {
			if let current = groups.last, current.count + item.count < 1900 {
				groups[groups.count - 1].count += item.count + delimeter.count
				groups[groups.count - 1].items.append(item)
			}
			else {
				groups.append((item.count + prefix.count + postfix.count, [item]))
			}
		}
		if groups.count == 0 {
			return [DiscordEmbed.Field(name: title, value: "None", inline: false)]
		}
		else if groups.count == 1 {
			return [DiscordEmbed.Field(name: title, value: "\(prefix)\(groups[0].items.joined(separator: delimeter))\(postfix)", inline: false)]
		}
		else {
			let fields = groups.enumerated().map { DiscordEmbed.Field(name: $0 == 0 ? title : "\u{200B}", value: "\(prefix)\($1.items.joined(separator: delimeter))\(postfix)", inline: false) }
			return fields
		}
	}

	static func removeYTPercentEnc<T: StringProtocol>(_ str: T) -> String where T.Index == String.Index {
		return str.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
	}
	
	static func yesNoValidator(message: DiscordMessage, bot: Renge) -> Bool? {
		if message.content.lowercased() == "yes" { return true }
		if message.content.lowercased() == "no" { return false }
		if let unprefixed = bot.removePrefix(from: message) {
			if unprefixed.lowercased() == "yes" { return true }
			if unprefixed.lowercased() == "no" { return false }
		}
		return nil
	}

	static func hmsToSeconds(hmsTime: String) -> Double? {
		var scanner = StringScanner(hmsTime)
		var total: Double? = nil
		while true {
			guard let num = scanner.read(untilInSet: ["h", "m", "s"], clearDelimeter: false) else { break }
			guard let time = Double(num) else { continue }
			guard let type = scanner.read(characterCount: 1) else { continue }
			switch type {
			case "h": total = (total ?? 0) + time * 60 * 60
			case "m": total = (total ?? 0) + time * 60
			case "s": total = (total ?? 0) + time
			default: break
			}
		}
		return total
	}
	
	static func parseHTMLQueryItems(queryString: Substring, wantedPieces: Set<Substring> = []) -> [(Substring, Substring)] {
		var scanner = StringScanner(queryString)
		var outArray: [(Substring, Substring)] = []
		while true {
			guard let part1 = scanner.read(toNext: "=") else { break }
			guard let part2 = scanner.read(toNext: "&") else { break }
			if wantedPieces.isEmpty || wantedPieces.contains(part1) { outArray.append((part1, part2)) }
		}
		return outArray
	}
	
	static func runTextProcess(arguments: [String], process: Process = Process(), stderr: Bool = false, completion: @escaping () -> (), lineCallback: @escaping (Data) -> ()) {
		var completion: (() -> ())? = completion
		process.launchPath = "/usr/bin/env"
		process.arguments = arguments
		let pipe = Pipe()
		if stderr {
			process.standardError = pipe
		}
		else {
			process.standardOutput = pipe
		}
		var data = Data()
		pipe.fileHandleForReading.readabilityHandler = { handle in
			let newData = handle.availableData
			if newData.isEmpty {
				completion?()
				completion = nil
				return
			}
			var workingSet = newData[...]
			if let offset = workingSet.index(of: 0x0A) {
				data.append(workingSet[..<offset])
				lineCallback(data)
				data = Data()
				workingSet = workingSet[workingSet.index(after: offset)...]
				while let offset = workingSet.index(of: 0x0A) {
					lineCallback(workingSet[..<offset])
					workingSet = workingSet[workingSet.index(after: offset)...]
				}
				data.append(workingSet)
			}
		}
		process.launch()
	}
}

extension Int {
	/// An initializer that won't crash if it fails
	init?(checking num: Double) {
		if let exact = Int(exactly: floor(num)) {
			self = exact
		}
		return nil
	}
}

/// Because tuples aren't hashable
struct ChannelAndUser: Hashable {
	let channel: ChannelID
	let user: UserID

	var hashValue: Int {
		return channel.hashValue &+ user.hashValue
	}

	static func ==(lhs: ChannelAndUser, rhs: ChannelAndUser) -> Bool {
		return lhs.channel == rhs.channel && lhs.user == rhs.user
	}
}

struct RengeLogger {
	let level: DiscordLogLevel

	/// Multi-level logger that gives different messages based on the level
	func multi(debug: @autoclosure () -> String, verbose: @autoclosure () -> String, log: @autoclosure () -> String, type: String) {
		switch level {
		case    .none: break
		case    .info: abstractLog("LOG", message: log(), type: type)
		case .verbose: abstractLog("VERBOSE", message: verbose(), type: type)
		case   .debug: abstractLog("DEBUG", message: debug(), type: type)
		}
	}

	/// Normal log messages.
	func log(_ message: @autoclosure () -> String, type: String) {
		guard level == .info || level == .verbose || level == .debug else { return }

		abstractLog("LOG", message: message(), type: type)
	}

	/// More info on log messages.
	func verbose(_ message: @autoclosure () -> String, type: String) {
		guard level == .verbose || level == .debug else { return }

		abstractLog("VERBOSE", message: message(), type: type)
	}

	/// Debug messages.
	func debug(_ message: @autoclosure () -> String, type: String) {
		guard level == .debug else { return }

		abstractLog("DEBUG", message: message(), type: type)
	}

	/// Error Messages.
	func error(_ message: @autoclosure () -> String, type: String) {
		abstractLog("ERROR", message: message(), type: type)
	}

	private func abstractLog(_ logType: String, message: String, type: String) {
		NSLog("[\(type)|\(logType)] \(message)")
	}
}

/// Like a Dispatch WorkItem, but releases its closure on cancellation
class WorkItem {
	private var work: (() -> Void)?

	/// Whether or not the item is cancelled
	var isCanceled: Bool {
		return work == nil
	}

	/// Performs the scheduled work if it hasn't been cancelled
	func perform() {
		work?()
	}

	/**
	Cancels the work item
	- warning: This is not threadsafe, so call it from the same thread that the WorkItem is scheduled to run on
	*/
	func cancel() {
		work = nil
	}

	/// Initializer
	init(block: @escaping () -> Void) {
		work = block
	}
}

extension BidirectionalCollection {
	func lastIndex(where check: (Element) -> Bool) -> Index? {
		var current = index(before: endIndex)
		while true {
			if check(self[current]) {
				return current
			}
			if current == startIndex {
				return nil
			}
			current = index(before: current)
		}
	}
}

struct StringScanner<T: StringProtocol> where T.SubSequence: StringProtocol {
	let str: T
	var pos: T.Index
	init(_ string: T) {
		self.str = string
		self.pos = self.str.startIndex
	}

	func peek(toNext delimeter: Character) -> T.SubSequence? {
		guard pos != str.endIndex else { return nil }
		let end = str[pos...].index(of: delimeter) ?? str.endIndex
		if end != pos {
			return str[pos..<end]
		}
		return ""
	}

	mutating func read(toNext delimeter: Character, clearDelimeter: Bool = true) -> T.SubSequence? {
		guard pos != str.endIndex else { return nil }
		let end = str[pos...].index(of: delimeter) ?? str.endIndex
		if end != pos {
			defer {
				if clearDelimeter && end != str.endIndex {
					pos = str.index(after: end)
				}
				else {
					pos = end
				}
			}
			return str[pos..<end]
		}
		if clearDelimeter {
			pos = str.index(after: pos)
		}
		return ""
	}

	func peek(while condition: (Character) -> Bool) -> T.SubSequence? {
		guard pos != str.endIndex else { return nil }
		let end = str[pos...].index(where: { !condition($0) }) ?? str.endIndex
		return str[pos..<end]
	}

	mutating func read(while condition: (Character) -> Bool) -> T.SubSequence? {
		guard pos != str.endIndex else { return nil }
		let end = str[pos...].index(where: { !condition($0) }) ?? str.endIndex
		defer { pos = end }
		return str[pos..<end]
	}

	private static func setContainsChar(set: CharacterSet, char: Character) -> Bool {
		for scalar in char.unicodeScalars {
			if set.contains(scalar) {
				return true
			}
		}
		return false
	}

	func peek(untilInSet set: CharacterSet) -> T.SubSequence? {
		return peek { !StringScanner.setContainsChar(set: set, char: $0) }
	}

	mutating func read(untilInSet set: CharacterSet, clearDelimeter: Bool = true) -> T.SubSequence? {
		let string = read { !StringScanner.setContainsChar(set: set, char: $0) }
		if clearDelimeter {
			_ = read(whileInSet: set)
		}
		return string
	}

	func peek(whileInSet set: CharacterSet) -> T.SubSequence? {
		return peek { StringScanner.setContainsChar(set: set, char: $0) }
	}

	mutating func read(whileInSet set: CharacterSet) -> T.SubSequence? {
		return read { StringScanner.setContainsChar(set: set, char: $0) }
	}

	mutating func read(characterCount count: T.IndexDistance, shouldAdvancePos: Bool = true) -> T.SubSequence? {
		guard str.count >= count else { return nil }
		let newPos: T.Index = str.index(pos, offsetBy: count)
		defer { if shouldAdvancePos { pos = newPos } }
		return str[pos..<newPos]
	}

	mutating func remove(prefix: String, matchingCase: Bool = false) -> Bool {
		guard str[pos...].count >= prefix.count else { return false }
		let end = str.index(pos, offsetBy: T.IndexDistance(prefix.count))
		let strprefix = str[pos..<end]
		if matchingCase {
			guard prefix == strprefix else { return false }
		}
		else {
			guard prefix.caseInsensitiveCompare(String(strprefix)) == .orderedSame else { return false }
		}
		pos = end
		return true
	}

	var rest: T.SubSequence {
		return str[pos..<str.endIndex]
	}
}
//
//extension StringScanner where T == Substring {
//	func peek(untilInSet set: CharacterSet) -> Substring? {
//		guard pos != str.endIndex else { return nil }
//		let end = str[pos...].unicodeScalars.index(where: { set.contains($0) }) ?? str[pos...].unicodeScalars.endIndex
//		Substring.Index
//	}
//}

