import Foundation
import SwiftDiscord

struct RengeGuild: Codable {
	let id: GuildID
	var prefixes: [String]
	var aliases: [String: AliasedCommand] = [:]
	init(id: GuildID, prefixes: [String]) {
		self.id = id
		self.prefixes = prefixes
	}
}

struct RengeChannel: Codable {
	let id: ChannelID
	init(id: ChannelID) {
		self.id = id
	}
}
