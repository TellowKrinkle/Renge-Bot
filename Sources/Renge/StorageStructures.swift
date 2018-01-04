import Foundation
import SwiftDiscord

extension Snowflake: Codable {
	public static let encodeAsUInt64 = CodingUserInfoKey(rawValue: "snowflakeAsUInt64")!
	public init(from decoder: Decoder) throws {
		do {
			let intForm = try UInt64(from: decoder)
			self = Snowflake(intForm)
		}
		catch _ {
			let stringForm = try String(from: decoder)
			guard let snowflake = Snowflake(stringForm) else {
				throw DecodingError.typeMismatch(Snowflake.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Failed to convert decoded string into a snowflake"))
			}
			self = snowflake
		}
	}
	public func encode(to encoder: Encoder) throws {
		if let snowflakeAsUInt64 = encoder.userInfo[Snowflake.encodeAsUInt64] as? Bool, snowflakeAsUInt64 {
			try self.rawValue.encode(to: encoder)
		}
		else {
			try self.description.encode(to: encoder)
		}
	}
	
}

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
