//
//  Commands.swift
//  Renge-Bot
//

import Foundation
import SwiftDiscord

/// A command permission class (who can use it)
enum PermissionClass: String {
	/// Can only be used by the owner of the bot
	/// Can be used in both guilds and DMs
	case botOwner = "Bot Owner"

	/// Can (by default) only be used by server owners and admins
	/// Can be only used in guilds
	case admin = "Admin"

	/// Can (by default) be used by anyone
	/// Can only be used in guilds
	case guildMember = "Guilds Only"

	/// Can (by default) be used by anyone
	/// Can be used in both guilds and DMs
	case user = "Anyone"
}

/// Possible ways to respond to a message
enum CommandResponseMethod {
	/// The user has permission, execute the command
	case accept

	/// The user doesn't have permission, reply with a permission denied
	case deny

	/// The user doesn't have permission, ignore the message entirely
	case ignore
}

/// Renge's command protocol.  This allows a struct to be used as a bot command
protocol RengeCommand {

	/// The name of the command.  This will be used to decide whether this is the command associated with a message.  It may also be used in help messages
	var name: String { get }

	/// The category of the command.  This will be used by the help command to group commands
	var category: String { get }

	/// A short (single-line) description for the command.
	var shortDescription: String { get }

	/// A usage string for the command.  The command name will automatically be prepended to this usage string.
	var usage: String? { get }

	/// A long (multi-line) description for the command
	var longDescription: String? { get }

	var permissionClass: PermissionClass { get }

	/**
	This will be called to execute a command

	- parameter bot: The main bot, in case you need to use it (to send a message, for example)
	- parameter arguments: A string containing the arguments passed to your bot (the whole message except the bot prefix and command name)
	- parameter messageObject: The messageObject that triggered the invocation
	- parameter errorLogger: A function that you should call with a message if you have an error to log it to the calling user.  This should not be called more than once (return if you call it)
	*/
	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void)
}

extension RengeCommand {
	var usage: String? { return nil }
	var longDescription: String? { return nil }
	func helpMessage(prefix: String) -> String {
		let usagePiece: String
		let longDescriptionPiece: String
		if let usage = usage {
			usagePiece = "\nUsage: `\(prefix) \(name) \(usage)`"
		}
		else {
			usagePiece = ""
		}
		if let longDescription = longDescription {
			longDescriptionPiece = "\n\(longDescription)"
		}
		else {
			longDescriptionPiece = ""
		}
		return "\(shortDescription)\nPermission Level: \(permissionClass.rawValue)\(usagePiece)\(longDescriptionPiece)"
	}
}

/// A protocol for commands that want to parse arguments into lists
/// On command execution, this command will parse the command into lists of arguments, and then call the custom execute on that.
protocol RengeCommandWithArguments : RengeCommand {
	/// The number of unnamed required options directly after the command name.  The command will fail to execute if there aren't at least this many options
	var numImmediateOptions: Int { get }
	/// The list of available options and aliases, the first string is the option or alias name, the tuple name argument is what the outputted name should be, and the numArgs is how many of the following arguments should be passed.
	/// This allows aliases to be included without having to check both later, for example, if you have ["a": ("a", 1), "b": ("a", 1)], the program will respond to both "a" and "b" but will put them both into the output as "a" so you don't have to deal with both separately later.
	var options: [String: (name: String, numArgs: Int)] { get }

	/// An error message to be used if there aren't enough arguments to fill the desired `numImmediateOptions`.  You can leave it as the default "" if you have no immediate options.
	var notEnoughArgumentsError: String { get }

	/**
	A function that will be called in argument parsing if someone uses an argument multiple times
	- parameter name: The argument name
	- parameter first: The result of the first use of the argument
	- parameter second: The result of the second use of the argument
	- returns: The result that will be stored
	*/
	func uniqueArguments(name: String, first: [Substring], second: [Substring]) -> [Substring]

	/**
	This will be called to execute the command (as long as you don't override the default implementation of the RengeCommand execute function)

	- parameter bot: The main bot, in case you need to use it (to send a message, for example)
	- parameter immediateArgs: The list of arguments passed immediately after the function name.  This will be `numImmediateOptions` in length
	- parameter args: The dictionary of options and their arguments that was parsed.  Each entry will be `name: [arguments]` where name is the name parameter from the options dictionary and the arguments array is the list of arguments that was passed, which will be `numArgs` in length.
	- paramter rest: The rest of the message that wasn't parsed into `immediateArgs` or `args`
	- parameter messageObject: The messageObject that triggered the invocation
	- parameter errorLogger: A function that you should call with a message if you have an error to log it to the calling user.  This should not be called more than once (return if you call it)
	*/
	func execute(bot: Renge, immediateArgs: [Substring], args: [String: [Substring]], rest: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void)
}

extension RengeCommandWithArguments {
	var notEnoughArgumentsError: String { return "" }

	// Default: Return the first use
	func uniqueArguments(name: String, first: [Substring], second: [Substring]) -> [Substring] {
		return first
	}

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		guard let commandInfo = parseCommand(command: arguments) else {
			errorLogger(DiscordMessage(content: notEnoughArgumentsError))
			return
		}
		execute(bot: bot, immediateArgs: commandInfo.immediate, args: commandInfo.args, rest: commandInfo.rest, messageObject: messageObject, user: user, channel: channel, errorLogger: errorLogger, output: output)
	}

	func parseCommand(command: Substring) -> (immediate: [Substring], args: [String: [Substring]], rest: Substring)? {
		var scanner = StringScanner(command)
		let delimeter = CharacterSet.whitespacesAndNewlines
		let argDelimeter = delimeter.union([":", "="])
		let immediate = (0..<self.numImmediateOptions).flatMap({ _ in scanner.read(untilInSet: delimeter) })
		guard immediate.count == self.numImmediateOptions else { return nil }

		var args: [String: [Substring]] = [:]
		while true {
			let rest = scanner.rest
			guard let nextItem = scanner.read(untilInSet: argDelimeter) else {
				return (args: args, immediate: immediate, rest: rest)
			}
			if nextItem == "--" {
				return (args: args, immediate: immediate, rest: scanner.rest)
			}
			guard let (argumentName, argumentCount) = self.options[nextItem.lowercased()] else {
				return (args: args, immediate: immediate, rest: rest)
			}
			let argList = (0..<argumentCount).flatMap({ _ in scanner.read(untilInSet: delimeter) })
			guard argList.count == argumentCount else {
				return (args: args, immediate: immediate, rest: rest)
			}
			if let old = args[argumentName] {
				args[argumentName] = uniqueArguments(name: argumentName, first: old, second: argList)
			}
			else {
				args[argumentName] = argList
			}
		}
	}
}

/// A protocol for commands made entirely of arguments that may contain spaces.
/// On command execution, this command will parse the command into a dictionary of arguments and call the custom execute on that.
/// It's recommended to choose argument names that won't come up in the text since if that happens, it will mess things up.
protocol RengeCommandWithLongArguments : RengeCommand {
	var options: Set<String> { get }

	/**
	A function that will be called in argument parsing if someone uses an argument multiple times
	- parameter name: The argument name
	- parameter first: The result of the first use of the argument
	- parameter second: The result of the second use of the argument
	- returns: The result that will be stored
	*/
	func uniqueArguments(name: String, first: Substring, second: Substring) -> Substring

	/**
	This will be called to execute the command (as long as you don't override the default implementation of the RengeCommand execute function)

	- parameter bot: The main bot, in case you need to use it (to send a message, for example)
	- parameter arguments: The list of arguments.  Anything that was between the original command name and the first argument will be under the lowercased name of the command.
	- parameter messageObject: The messageObject that triggered the invocation
	- parameter errorLogger: A function that you should call with a message if you have an error to log it to the calling user.  This should not be called more than once (return if you call it)
	*/
	func execute(bot: Renge, arguments: [String: Substring], messageObject: DiscordMessage, user: UserID, channel: ChannelID,  errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void)
}

extension RengeCommandWithLongArguments {
	func uniqueArguments(name: String, first: Substring, second: Substring) -> Substring {
		return first
	}

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		let parsed = parseCommand(command: arguments)
		execute(bot: bot, arguments: parsed, messageObject: messageObject, user: user, channel: channel, errorLogger: errorLogger, output: output)
	}

	func parseCommand(command: Substring) -> [String: Substring] {
		let delimeter = CharacterSet.whitespacesAndNewlines
		var arguments: [String: Substring] = [:]
		var start = command.startIndex
		var end = start
		var scanner = StringScanner(command)
		var argname = name.lowercased()
		while let nextArg = scanner.read(untilInSet: delimeter, clearDelimeter: false) {
			let nextArgString = nextArg.lowercased()
			if options.contains(nextArgString) {
				if let old = arguments[argname] {
					arguments[argname] = uniqueArguments(name: argname, first: old, second: command[start..<end])
				}
				else {
					arguments[argname] = command[start..<end]
				}
				_ = scanner.read(whileInSet: delimeter)
				start = scanner.pos
				end = scanner.pos
				argname = nextArgString
			}
			else {
				end = scanner.pos
				_ = scanner.read(whileInSet: delimeter)
			}
		}
		if let old = arguments[argname] {
			arguments[argname] = uniqueArguments(name: argname, first: old, second: command[start..<end])
		}
		else {
			arguments[argname] = command[start..<end]
		}
		return arguments
	}
}

// MARK: Command-parsing helpers
extension Renge {
	enum Result<Success, Failure> {
		case success(Success)
		case failure(Failure)
		var optionalValue: Success? {
			switch self {
			case .success(let success): return success
			case .failure: return nil
			}
		}
	}

	func validSnowflake(_ string: String) -> Snowflake? {
		// Filters out most names that start with a number while only filtering out the first month of snowflakes
		// Since Discord wasn't launched until March of the year, you'd have to have a user made before its release
		if let snowflake = Snowflake(string), snowflake.rawValue > (2_592_000_000 << 22) {
			return snowflake
		}
		return nil
	}

	/**
	Parse a user id from a string
	- parameter string: The string to get the user id from
	- parameter channel: The channel the message was sent in (to get a user id by filtering usernames, not currently implemented)
	- returns: A user id if one was able to be parsed from the string, a Result.failure with a list of conflicting usernames if the issue was too many conflicting usernames, or Result.failure(nil) if there was no user found.
	*/
	func userIDFromString(_ string: Substring, channel: ChannelID?) -> Result<UserID, [String]?> {
		var scanner = StringScanner(string)

		if let snowflake = scanner.peek(whileInSet: .decimalDigits).map(String.init).flatMap(validSnowflake) {
			return .success(snowflake)
		}

		if scanner.remove(prefix: "<@", matchingCase: true) {
			_ = scanner.remove(prefix: "!", matchingCase: true)
			if let numbers = scanner.read(whileInSet: .decimalDigits) {
				if scanner.remove(prefix: ">", matchingCase: true) {
					if let snowflake = Snowflake(String(numbers)) {
						return .success(snowflake)
					}
				}
			}
		}
		// TODO: Try to resolve username+discrim
		return .failure(nil)
	}

	/**
	Parse a user id from a string
	- parameter string: The string to get the user id from
	- parameter guild: The guild the message was sent in (to get a channel id by filtering channel names, not currently implemented)
	- returns: A channel id if one was able to be parsed from the string, a Result.failure with a list of conflicting channel names if the issue was too many conflicting channel names, or Result.failure(nil) if there was no channel found.
	*/
	func channelIDFromString(_ string: Substring, guild: GuildID?) -> Result<ChannelID, [String]?> {
		var scanner = StringScanner(string)

		if let snowflake = scanner.peek(whileInSet: .decimalDigits).map(String.init).flatMap(validSnowflake) {
			return .success(snowflake)
		}

		if scanner.remove(prefix: "<#", matchingCase: true) {
			if let numbers = scanner.read(whileInSet: .decimalDigits) {
				if scanner.remove(prefix: ">", matchingCase: true) {
					if let snowflake = Snowflake(String(numbers)) {
						return .success(snowflake)
					}
				}
			}
		}
		// TODO: Try to resolve username+discrim
		return .failure(nil)
	}

	func hasPermission(user userID: UserID, inChannel channelID: ChannelID, permission: DiscordPermission) -> Bool {
		let dmChannelPermissions: DiscordPermission = [.addReactions, .readMessages, .readMessageHistory, .sendTTSMessages, .embedLinks, .attachFiles, .useExternalEmojis, .connect, .speak, .useVAD] // The available permissions for a DM channel
		guard let channel = client.findChannel(fromId: channelID) else { return false }
		switch channel {
		case let channel as DiscordGuildChannel:
			guard let guild = client.guilds[channel.guildId] else { return false }
			return guild.members[userID].map { channel.permissions(for: $0).contains(permission) } ?? false
		case let channel as DiscordGroupDMChannel:
			return dmChannelPermissions.contains(permission) && channel.recipients.lazy.map({ $0.id }).contains(userID)
		case let channel as DiscordDMChannel:
			return dmChannelPermissions.contains(permission) && (userID == channel.recipient.id || userID == client.user?.id)
		default:
			return false
		}
	}
}

// MARK: Small commands that don't need their own files

struct SayCommand : RengeCommandWithArguments {
	var name: String { return "Say" }
	var category: String { return "Random" }
	var shortDescription: String { return "Says the given text" }
	var usage: String? { return "[-d] <text>" }
	var longDescription: String? { return """
		If used with `-d`, the bot will also delete the message that triggered the command
		""" }
	var permissionClass: PermissionClass { return .user }
	var numImmediateOptions: Int { return 0 }
	var options: [String : (name: String, numArgs: Int)] { return ["-d": (name: "d", numArgs: 0)] }

	func execute(bot: Renge, immediateArgs: [Substring], args: [String : [Substring]], rest: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		if args["d"] != nil {
			bot.client.deleteMessage(messageObject.id, on: messageObject.channelId)
		}
		output(DiscordMessage(content: String(rest)))
	}
}

struct HelpCommand : RengeCommand {
	var name: String { return "Help" }
	var category: String { return "Info" }
	var shortDescription: String { return "Prints help messages" }
	var usage: String? { return "[<other command>]" }
	var permissionClass: PermissionClass { return .user }
	static let sortedCategories = ["Info", "Random", "Custom Commands"]
	static let ignoredCategories = ["Bot Owner", "Debug"]

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		if let command = bot.getCommand(unprefixedMessage: arguments, channel: messageObject.channelId).optionalValue {
			let prefix = bot.prefixedUsed(in: messageObject) ?? bot.prefixes[0]
			output(DiscordMessage(content: "", embed: DiscordEmbed(title: "Help for \(command.0.name)", description: command.0.helpMessage(prefix: prefix))))
			return
		}
		let botCommands = bot.commands.lazy.map({ $0.value })
		let categorized = Dictionary(grouping: botCommands, by: { $0.category }).array
		let filteredCategories = categorized.filter({ !HelpCommand.ignoredCategories.contains($0.key) })
		let sortedCategories = filteredCategories.sorted { (left, right) -> Bool in
			let leftIndex = HelpCommand.sortedCategories.index(of: left.key)
			let rightIndex = HelpCommand.sortedCategories.index(of: right.key)
			switch (leftIndex, rightIndex) {
			case let (.some(leftIndex), .some(rightIndex)):
				return leftIndex <= rightIndex
			case (.some, nil):
				return true
			case (nil, .some):
				return false
			default:
				return left.key <= right.key
			}
		}
		let fields = sortedCategories.map { category -> DiscordEmbed.Field in
			let title = "**\(category.key)**"
			let list = category.value.map({ "**\($0.name):** \($0.shortDescription)" }).joined(separator: "\n")
			return DiscordEmbed.Field(name: title, value: list, inline: false)
		}
		let message = DiscordEmbed(title: "Command List", description: nil, fields: fields)
		output(DiscordMessage(content: "", embed: message))
	}
}

struct AliasedCommand : RengeCommand, Codable {
	var category: String { return "Aliases" }
	var shortDescription: String { return "An aliased command" }
	let name: String
	let target: String
	
	// Anyone can use an alias, the permission will be reevaluated after dealiasing
	var permissionClass: PermissionClass { return .user }

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		//TODO: Implement this
	}

	init(name: String, target: String) {
		self.name = name
		self.target = target
	}
}
