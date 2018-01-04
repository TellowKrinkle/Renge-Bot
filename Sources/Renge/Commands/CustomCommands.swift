//
//  CustomCommands.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/08/12.
//
//  This file is for commands that are meant to be used with the custom command system
//

import Foundation
import SwiftDiscord

struct QuestionCommand : RengeCommandWithArguments {
	var name: String { return "AskQuestion" }
	var category: String { return "Custom Commands" }
	var shortDescription: String { return "Asks the user a question" }
	var usage: String? { return "[timeout <seconds>] <question>" }
	var longDescription: String? { return """
		Prints the given question, waits for the user to answer it, and prints the answer.
		Only really useful for custom commands
		"""}
	var permissionClass: PermissionClass { return .user }
	var numImmediateOptions: Int { return 0 }
	var options: [String : (name: String, numArgs: Int)] { return ["timeout": ("timeout", 1)] }

	func execute(bot: Renge, immediateArgs: [Substring], args: [String : [Substring]], rest: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		let timeoutTime = (args["timeout"]?[0]).flatMap(Double.init) ?? 30
		QuestionResponder.registerResponder(
			bot: bot,
			timeoutTime: timeoutTime,
			question: DiscordMessage(content: String(rest)),
			user: messageObject.author.id,
			channel: messageObject.channelId,
			shouldDeleteQuestion: true,
			shouldDeleteResponse: true,
			validator: { _, _ in true },
			callback: { message in
				output(DiscordMessage(content: message))
				return nil
			}
		)
	}

}

struct OutputRedirectCommand : RengeCommandWithArguments {
	var name: String { return "RedirectOutput" }
	var category: String { return "Custom Commands" }
	var shortDescription: String { return "Redirects the output of a command" }
	var usage: String? { return "<channel> <command>" }
	var longDescription: String? { return """
		Runs the given command but prints its main output (but not any intermediary questions) to the given channel instead of the channel it was run in
		The user running the command must have permission to post in the given channel, and the channel must be in the same guild as the channel the command was triggered from
		""" }
	var permissionClass: PermissionClass { return .user }
	var numImmediateOptions: Int { return 1 }
	var options: [String : (name: String, numArgs: Int)] { return [:] }

	func execute(bot: Renge, immediateArgs: [Substring], args: [String : [Substring]], rest: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		guard let outputChannel = bot.channelIDFromString(immediateArgs[0], guild: nil).optionalValue else {
			errorLogger(DiscordMessage(content: "❌  |  Failed to get channel ID from `\(immediateArgs[0])`"))
			return
		}
		if user != bot.botOwner {
			guard let outChannel = bot.client.findChannel(fromId: outputChannel) as? DiscordGuildTextChannel, let inChannel = bot.client.findChannel(fromId: messageObject.channelId) as? DiscordGuildTextChannel, outChannel.guildId == inChannel.guildId else {
				errorLogger(DiscordMessage(content: "❌  |  Please use this command from a channel in the same guild as <#\(outputChannel)>"))
				return
			}


			// Make sure the user has permission to post in the new channel
			guard bot.hasPermission(user: user, inChannel: outputChannel, permission: .sendMessages) else {
				errorLogger(DiscordMessage(content: "❌  |  You need the **Send Messages** permission in <#\(outputChannel)> to use this command."))
				return
			}
		}
		
		switch bot.getCommand(unprefixedMessage: rest, channel: channel) {
		case .failure(let failedCommand):
			errorLogger(DiscordMessage(content: "❌  |  `\(failedCommand ?? "")` is not a valid command."))
			return
		case .success(let (command, commandArgs)):
			let newOutput: (DiscordMessage) -> Void = { [weak bot] message in
				bot?.client.sendMessage(message, to: outputChannel)
			}
			bot.run(command: command, message: messageObject, commandlessString: commandArgs, user: user, channel: channel, errorLogger: errorLogger, mainOutput: newOutput)
		}
	}
}

struct MakeEmbedCommand : RengeCommandWithLongArguments {
	var name: String { return "MakeEmbed" }
	var category: String { return "Custom Commands" }
	var shortDescription: String { return "Makes an embed with the given parameters" }
	var usage: String? { return "[<option>]..." }
	var longDescription: String? { return """
		Available options (You can use spaces in these):
		--title <title text>: Sets the embed title
		--url <url>: Sets the embed URL (makes the title a link)
		--description <description text>: Sets the text under the title
		--author <user>: Sets the embed author
		--imageurl <url>: Adds the given image to the embed
		--thumbnailurl <url>: Adds the given image as the thumbnail
		--color (#<6-digit HTML color> | <Integer color representation>): Sets the color of the embed
		--footer <footer text>: Adds a footer with the given text
		--footericonurl <url>: Adds the given image as the footer icon
		--field --name <field name> --value <field text> [--inline]: Adds a field to the embed.  This can be used multiple times.
		"""}
	var permissionClass: PermissionClass { return .user }
	static let options: Set<String> = ["--title", "--description", "--author", "--url", "--imageurl", "--thumbnailurl", "--color", "--footer", "--footericonurl", "--field"]
	var options: Set<String> { return MakeEmbedCommand.options }
	/// Just here to steal its parseString method
	private struct FieldParser : RengeCommandWithLongArguments {
		var name: String { return "FieldParser" }
		var category: String { return "Custom Commands" }
		var shortDescription: String { return "This command should not be usable" }
		var permissionClass: PermissionClass { return .user }
		var options: Set<String> { return ["--name", "--value", "--inline"] }

		func execute(bot: Renge, arguments: [String : Substring], messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) { }
	}

	func uniqueArguments(name: String, first: Substring, second: Substring) -> Substring {
		guard name == "--field" else { return first }
		return Substring("\(first) --field \(second)") // Not efficient, but does what we want
	}

	func execute(bot: Renge, arguments: [String : Substring], messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		let author: DiscordEmbed.Author? = arguments["--author"].flatMap { (name) -> DiscordEmbed.Author? in
			guard let userID = bot.userIDFromString(name, channel: messageObject.channelId).optionalValue else { return nil }
			guard let channel = bot.client.findChannel(fromId: messageObject.channelId) else { return nil }
			let _user: DiscordUser?
			switch channel {
			case let channel as DiscordGuildTextChannel:
				_user = bot.client.guilds[channel.guildId]?.members[userID]?.user
			case let channel as DiscordGroupDMChannel:
				_user = channel.recipients.first(where: { $0.id == userID })
			case let channel as DiscordDMChannel:
				_user = channel.recipient.id == userID ? channel.recipient : nil
			default:
				_user = nil
			}
			guard let user = _user else { return nil }
			let avatarURL = URL(string: "https://cdn.discordapp.com/avatars/\(user.id)/\(user.avatar).png")
			return DiscordEmbed.Author(name: user.username, iconUrl: avatarURL, url: nil)
		}
		let url = arguments["--url"].flatMap { str -> URL? in
			let url = URL(string: String(str))
			if url == nil { print("Failed to get url for \(str)") }
			return url
		}
		let title = arguments["--title"].map(String.init)
		let description = arguments["--description"].map(String.init)
		let image = arguments["--imageurl"].flatMap { urlStr -> DiscordEmbed.Image? in
			guard let url = URL(string: String(urlStr)) else { return nil }
			return DiscordEmbed.Image(url: url)
		}
		let thumbnail = arguments["--thumbnailurl"].flatMap { (urlStr) -> DiscordEmbed.Thumbnail? in
			guard let url = URL(string: String(urlStr)) else { return nil }
			return DiscordEmbed.Thumbnail(url: url)
		}
		let color = arguments["--color"].flatMap { (str) -> Int? in
			if let int = Int(str) { return int }
			if let int = Int(str, radix: 16) { return int }
			if str.hasPrefix("#") {
				if let int = Int(str[str.index(after: str.startIndex)...], radix: 16) { return int }
			}
			return nil
		}
		var footer: DiscordEmbed.Footer? = nil
		let footerText = arguments["--footer"].map(String.init)
		let footerURL = arguments["--footericonurl"].flatMap { URL(string: String($0)) }
		if footerText != nil || footerURL != nil {
			footer = DiscordEmbed.Footer(text: footerText, iconUrl: footerURL)
		}
		let fields = arguments["--field"].map { str -> [DiscordEmbed.Field] in
			let separated = str.components(separatedBy: " --field ")
			return separated.flatMap { string -> DiscordEmbed.Field? in
				let parsed = FieldParser().parseCommand(command: Substring(string))
				guard let title = parsed["--name"] else { return nil }
				guard let content = parsed["--value"] else { return nil }
				let inline = parsed["--inline"] != nil
				return DiscordEmbed.Field.init(name: String(title), value: String(content), inline: inline)
			}
		}
		let embed = DiscordEmbed(title: title, description: description, author: author, url: url, image: image, thumbnail: thumbnail, color: color, footer: footer, fields: fields ?? [])
		output(DiscordMessage(content: "", embed: embed))
	}
}

struct CustomCommand : RengeCommandWithLongArguments, Codable {
	let name: String
	var category: String { return "Custom" }
	var shortDescription: String { return "A custom command" }
	var usage: String? { return options.sorted().map({ "\($0) <arg>" }).joined(separator: " ") }
	var longDescription: String? { return "Raw command: ```\n\(raw)\n```\nDefault arguments: \(defaultArgs)" }
	var permissionClass: PermissionClass { return .user }
	let options: Set<String>
	let defaultArgs: [String: String]
	let raw: String

	func execute(bot: Renge, arguments: [String : Substring], messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {

	}
}
