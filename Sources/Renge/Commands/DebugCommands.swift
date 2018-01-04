//
//  DebugCommands.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/08/08.
//

import Foundation
import SwiftDiscord

struct PrintLoadedMembers : RengeCommand {
	var name: String { return "PrintLoadedMembers" }
	var category: String { return "Debug" }
	var shortDescription: String { return "Prints the members of this guild currently loaded by the bot" }

	var permissionClass: PermissionClass { return .admin }

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		guard let guild = (bot.client.findChannel(fromId: channel) as? DiscordGuildTextChannel)?.guild else { return }
		let members = guild.members.lazy.map({ $1.user }).map({ "\($0.username)#\($0.discriminator)" })
		let response = Util.makeListingMessage(items: Array(members), delimeter: "\n", prefix: "```", postfix: "```")
		output(response)
	}
}

struct YoutubeVolumeInfo : RengeCommand {
	var name: String { return "YTVolInfo" }
	var category: String { return "Debug" }
	var shortDescription: String { return "Gets volume information about a youtube video.  For figuring out what Youtube's valume and normalized_volume tags are" }
	
	var permissionClass: PermissionClass { return .user }
	
	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		var arguments = arguments
		if arguments.first == "<" && arguments.last == ">" {
			arguments = arguments[arguments.index(after: arguments.startIndex)..<arguments.index(before: arguments.endIndex)]
		}
		guard let url = URL(string: String(arguments)) else {
			errorLogger("That isn't a valid URL")
			return
		}
		guard YoutubeProvider.recognizes(url: url) else {
			errorLogger("That isn't a recognized YouTube URL")
			return
		}
		YoutubeProvider.makeProvider(url: url, urlSession: bot.sharedURLSession) { (provider) in
			guard let provider = provider as? YoutubeProvider else {
				errorLogger("Failed to get video info")
				return
			}
			guard let audioURL = provider.audioURL else {
				errorLogger("Failed to get audio URL from video")
				return
			}
			
			var meanVolume: String?
			var maxVolume: String?
			var histogram0db: String?

			Util.runTextProcess(
				arguments: ["ffmpeg", "-nostdin", "-y", "-i", audioURL.absoluteString, "-filter:a", "volumedetect", "-vn", "-sn", "-dn", "-f", "null", "/dev/null"],
				stderr: true,
				completion: {
					let description = """
					YouTube Loudness: \(provider.ytvolume)
					YouTube Relative Loudness: \(provider.ytRelativeLoudness)
					FFmpeg Mean Volume: \(meanVolume ?? "Unknown") dB
					FFmpeg Max Volume: \(maxVolume ?? "Unknown") dB
					FFmpeg Histogram 0dB: \(histogram0db ?? "Unknown")
					"""
					let message = DiscordMessage(content: "", embed: DiscordEmbed(title: provider.name, description: description, url: YoutubeProvider.getBrowserURL(info: provider.audioInfo)))
					output(message)
				},
				lineCallback: { (line) in
					guard let line = String(data: line, encoding: .utf8) else { return }
					Renge.logger.debug("FFmpeg: \(line)", type: "RengeYoutubeVolume")
					if let meanRange = line.range(of: "mean_volume: ") {
						let shortLine = line[meanRange.upperBound...]
						meanVolume = String(shortLine[..<(shortLine.index(of: " ") ?? shortLine.endIndex)])
					}
					else if let maxRange = line.range(of: "max_volume: ") {
						let shortLine = line[maxRange.upperBound...]
						maxVolume = String(shortLine[..<(shortLine.index(of: " ") ?? shortLine.endIndex)])
					}
					else if let histRange = line.range(of: "histogram_0db: ") {
						let shortLine = line[histRange.upperBound...]
						histogram0db = String(shortLine[..<(shortLine.index(of: " ") ?? shortLine.endIndex)])
					}
				}
			)
		}
	}
}

struct ChannelList : RengeCommand {
	var name: String { return "ChannelInfo" }
	var category: String { return "Info" }
	var shortDescription: String { return "Prints information for channels" }
	var usage: String? { return "[<channel>]" }
	var longDescription: String? { return """
		If no channel is given, prints a list of all the channels you can see on the server
		If a channel is given, prints information about that channel
		"""}
	var permissionClass: PermissionClass { return .guildMember }

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		if let targetID = bot.channelIDFromString(arguments, guild: nil).optionalValue {
			guard let target = bot.client.findChannel(fromId: targetID) as? DiscordGuildChannel else {
				errorLogger("I couldn't find that channel")
				return
			}
			let name = "Channel Info for \(target.name)"
			let description = """
				<#\(target.id)>
				**ID:** \(target.id)
				"""
			let fields: [DiscordEmbed.Field] = [
				DiscordEmbed.Field(name: "Type", value: target is DiscordTextChannel ? "Text" : "Voice", inline: true),
				DiscordEmbed.Field(name: "Date Created", value: target.id.timestamp.description, inline: true)
			]
			output(DiscordMessage(content: "", embed: DiscordEmbed(title: name, description: description, fields: fields)))
			return
		}
		guard let guild = (bot.client.findChannel(fromId: channel) as? DiscordGuildTextChannel)?.guild else { return }
		let channels = guild.channels.values.filter({ bot.hasPermission(user: user, inChannel: $0.id, permission: .sendMessages) }).sorted { (left, right) -> Bool in
			if left is DiscordGuildTextChannel && right is DiscordGuildVoiceChannel { return true }
			if left is DiscordGuildVoiceChannel && right is DiscordGuildTextChannel { return false }
			return left.position <= right.position
		}
		let channelList = "**\(guild.name)'s Channels:**\n" + channels.map({ "`\($0.id):` <#\($0.id)>, Name: \($0.name)" }).joined(separator: "\n")
		output(DiscordMessage(content: channelList))
	}
}
