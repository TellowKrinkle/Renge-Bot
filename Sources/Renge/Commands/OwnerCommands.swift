//
//  OwnerCommands.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/08/12.
//

import Foundation
import SwiftDiscord

struct OverrideCommand : RengeCommandWithArguments {
	var name: String { return "Override" }
	var category: String { return "Bot Owner" }
	var shortDescription: String { return "Runs a command as someone else to bypass permission checks" }
	var usage: String? { return "[as <user>] [in <channel>] command" }
	var permissionClass: PermissionClass { return .botOwner }
	var numImmediateOptions: Int { return 0 }
	var options: [String : (name: String, numArgs: Int)] { return ["as": (name: "as", numArgs: 1), "in": (name: "in", numArgs: 1)] }

	func execute(bot: Renge, immediateArgs: [Substring], args: [String: [Substring]], rest: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		let user = (args["as"]?[0]).flatMap({ bot.userIDFromString($0, channel: channel).optionalValue }) ?? user
		let guildID = (bot.client.findChannel(fromId: channel) as? DiscordGuildChannel)?.guildId
		let channel = (args["in"]?[0]).flatMap({ bot.channelIDFromString($0, guild: guildID).optionalValue }) ?? channel
		guard let (command, args) = bot.getCommand(unprefixedMessage: rest, channel: channel).optionalValue else { return }
		bot.run(command: command, message: messageObject, commandlessString: args, user: user, channel: channel, errorLogger: errorLogger, mainOutput: output)
	}

}

struct ShutdownCommand : RengeCommand {
	var name: String { return "Shutdown" }
	var category: String { return "Bot Owner" }
	var shortDescription: String { return "Shuts down the bot" }
	var permissionClass: PermissionClass { return .botOwner }

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		let responseChannel = messageObject.channelId
		QuestionResponder.registerResponder(
			bot: bot,
			timeoutTime: 30,
			question: "Are you sure you want me to shut down?",
			user: messageObject.author.id,
			channel: responseChannel,
			validator: { Util.yesNoValidator(message: $0, bot: $1) != nil },
			callback: { [weak bot] question, response in
				guard let bot = bot else { return }
				let group = DispatchGroup()
				let ok = Util.yesNoValidator(message: response, bot: bot) ?? false
				let messageEdit = ok ? "Shutting down..." : "Not shutting down."
				group.enter()
				bot.client.editMessage(question.id, on: responseChannel, content: messageEdit) { _ in group.leave() }
				group.enter()
				bot.client.deleteMessage(response.id, on: responseChannel) { _ in group.leave() }
				if ok {
					group.notify(queue: .global()) {
						bot.client.disconnect()
						CFRunLoopStop(CFRunLoopGetMain())
					}
				}
			}
		)
	}
}
