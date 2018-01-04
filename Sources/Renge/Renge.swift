import Foundation
import SwiftDiscord
import Dispatch

class Renge : DiscordClientDelegate {
	static var logger = RengeLogger(level: .debug)
	
	static var fullCommandList: [RengeCommand] {
		return [
			ShutdownCommand(), OverrideCommand(), // Bot Owner Commands
			PrintLoadedMembers(), ChannelList(), YoutubeVolumeInfo(), // Debug Commands
			SayCommand(), HelpCommand(), // Random Commands
			QuestionCommand(), OutputRedirectCommand(), MakeEmbedCommand(), // Custom Commands and helpers
			RengeCardPlan()
		]
	}
	/// A queue to do async (blocking) file writes on to avoid blocking too much
	let fileIOQueue: DispatchQueue
	let defaultPrefixes: [String]
	
	var client: DiscordClient!
	var mainQueue: DispatchQueue = DispatchQueue(label: "renge.mainQueue", qos: .userInitiated)
	var running: Bool = false
	let botName: String
	let botOwner: UserID
	
	let sharedURLSession = URLSession(configuration: .default)
	var prefixes: [String] = [] // Will get filled with a bot mention after login

	var commands: [String: RengeCommand]
	private var guilds: [GuildID: RengeGuild] = [:]
	private var channels: [ChannelID: RengeChannel] = [:]

	private(set) var channelResponders: [ChannelID: (MessageResponder, timeoutTask: WorkItem?)] = [:]
	private(set) var userChannelResponders: [ChannelAndUser: (MessageResponder, timeoutTask: WorkItem?)] = [:]

	let saveDir: URL
	var guildSaveDir: URL { return saveDir.appendingPathComponent("Guilds") }
	var channelSaveDir: URL { return saveDir.appendingPathComponent("Channels") }


	init(info: BotInfo, queue: DispatchQueue? = nil, swiftDiscordLogLevel: DiscordLogLevel = .info, fileIOQueue: DispatchQueue? = nil) {
		self.botName = info.botName
		defaultPrefixes = [info.botName.lowercased()]
		self.fileIOQueue = fileIOQueue ?? DispatchQueue(label: "\(info.botName).fileIOQueue")
		commands = [String: RengeCommand](uniqueKeysWithValues: Renge.fullCommandList.map({ return ($0.name.lowercased(), $0) }))
		botOwner = info.owner
		saveDir = info.saveDirectory
		mainQueue = queue ?? mainQueue
		client = DiscordClient(token: DiscordToken(stringLiteral: "Bot \(info.token)"), delegate: self, configuration: [.log(swiftDiscordLogLevel), .handleQueue(mainQueue), .fillLargeGuilds, .fillUsers])
	}

	func client(_ client: DiscordClient, didConnect connected: Bool) {
		if connected {
			Renge.logger.log("Connected!", type: "Renge")
		}
		else {
			Renge.logger.log("Not Connected!", type: "Renge")
		}
	}

	func client(_ client: DiscordClient, didReceiveReady readyData: [String : Any]) {
		if let user = client.user {
			Renge.logger.log("Logged in as \(user.username)", type: "Renge")
			prefixes += ["<@\(user.id)>", "<@!\(user.id)>"]
		} else {
			Renge.logger.error("Logged in, but I don't know who I am", type: "Renge")
			prefixes += [botName.lowercased()]
		}
	}

	func client(_ client: DiscordClient, didCreateMessage message: DiscordMessage) {
		Renge.logger.debug("Received message \(message.id) by \(message.author.id) in \(message.channelId).  Content: \(message.content)", type: "Renge")
		guard message.author.bot != true else { return }
		let handleMethod = runResponders(for: message)
		guard handleMethod == .propagate else {
			Renge.logger.debug("Handler requested ignore for \(message.id), ignoring...", type: "Renge")
			return
		}
		guard let unprefixed = removePrefix(from: message) else {
			Renge.logger.debug("Ignoring unprefixed message \(message.id)", type: "Renge")
			return
		}
		guard let (command, args) = getCommand(unprefixedMessage: unprefixed, channel: message.channelId).optionalValue else {
			Renge.logger.debug("Failed to find command for \(message.id), message was \(message.content)", type: "Renge")
			return
		}
		Renge.logger.debug("Dispatching \(command.name) for \(message.id)", type: "Renge")
		run(command: command, message: message, commandlessString: args)
	}

	func client(_ client: DiscordClient, didDisconnectWithReason reason: String) {
		//TODO: Actually handle this
		running = false
	}

	func connect() {
		running = true
		client.connect()
	}
}

//MARK: - Helpers
extension Renge {
	/**
	Gets an item (identified by a Snowflake ID) from either a cache (dictionary), save file on disk, or finally by using a default value.
	It also will cache the item for future lookups
	- parameter id: The id of the item to get
	- parameter dict: The dictionary cache.  This is inout so that the method can add things to the cache if they weren't previously there
	- parameter saveFile: The URL of the file's save on disk.
	- parameter default: A default value to be supplied if the item isn't cached or saved on disk
	- returns: The now-cached value
	*/
	func getFromSaveOrDefault<T: Decodable>(id: Snowflake, dict: inout [Snowflake: T], saveFile: @autoclosure () -> URL, default defaultVal: @autoclosure () -> T ) -> T {
		if let cached = dict[id] {
			return cached
		}
		let uncached: T
		let saveFile = saveFile()
		if FileManager.default.fileExists(atPath: saveFile.path) {
			let decoder = JSONDecoder()
			do {
				uncached = try decoder.decode(T.self, from: Data(contentsOf: saveFile))
			}
			catch let error {
				Renge.logger.error("Failed to load save \(saveFile): \(error.localizedDescription)", type: "Renge")
				uncached = defaultVal()
			}
		}
		else {
			uncached = defaultVal()
		}
		dict[id] = uncached
		return defaultVal()
	}

	/**
	Saves an item to disk using an asynchronous disk write
	- parameter item: An item that can be saved to disk
	- parameter saveFile: the URL to save to
	*/
	func save<T: Encodable>(_ item: T, to saveFile: URL) {
		let encoder = JSONEncoder()
		// Enable this if you switch to a binary format to save memory.  In JSON, the memory savings are minimal
		// encoder.userInfo[Snowflake.encodeAsUInt64] = true
		do {
			let data = try encoder.encode(item)
			fileIOQueue.async {
				do {
					try data.write(to: saveFile, options: .atomic)
				}
				catch let error {
					print("Failed to update save file \(saveFile): \(error.localizedDescription)")
				}
			}
		}
		catch let error {
			print("Failed to encode \(item) for saving: \(error.localizedDescription).  This shouldn't ever happen.")
		}
	}
}


//MARK: - Guilds
extension Renge {
	/**
	Returns the URL of the location the save file for a particular guild
	- parameter guild: The ID of the guild to get the save file for
	- returns: A file URL to where the guild's save file should be
	*/
	func saveFileURL(forGuild guild: GuildID) -> URL {
		return guildSaveDir.appendingPathComponent("Guild\(guild).json")
	}

	/**
	Looks up guild information using a guild id
	- parameter id: The ID of the guild you want information for
	- returns: The channel information for the specified ID
	*/
	func guild(forID id: GuildID) -> RengeGuild {
		return getFromSaveOrDefault(id: id, dict: &guilds, saveFile: saveFileURL(forGuild: id), default: RengeGuild(id: id, prefixes: defaultPrefixes))
	}

	/**
	Looks up guild that a channel is a part of
	- parameter id: The ID of the channel you want the guild for
	- returns: The guild information for the channel or nil if the channel was a DM/group channel
	*/
	func guild(forChannel channel: ChannelID) -> RengeGuild? {
		return ((client.findChannel(fromId: channel) as? DiscordGuildChannel)?.guildId).map({ guild(forID: $0) })
	}

	/**
	Updates the guild information storage with new information
	- parameter guild: The channel with the new information
	- parameter shouldSave: Whether or not the information that changed is included in the save file.  If it is, the save file needs updating, but if it isn't, then the save file doesn't need to be changed.
	*/
	func update(guild: RengeGuild, updatedPersistentData shouldSave: Bool) {
		guilds[guild.id] = guild
		guard shouldSave else { return }
		save(guild, to: saveFileURL(forGuild: guild.id))
	}

	/**
	Adds the specified prefix to the specified guild
	- parameter prefix: The prefix to add
	- parameter id: The ID of the guild to add the prefix to
	- returns: Whether or not the attempt was successful (fails if the guild already had that prefix)
	*/
	func add(prefix: String, to id: GuildID) -> Bool {
		var guild = self.guild(forID: id)
		if !guild.prefixes.contains(prefix.lowercased()) {
			guild.prefixes.append(prefix.lowercased())
			update(guild: guild, updatedPersistentData: true)
			return true
		}
		return false
	}

	/**
	Removes the specified prefix from the specified guild
	- parameter prefix: The prefix to remove
	- parameter id: The ID of the guild to remove the prefix from
	- returns: Whether or not the attempt was successful (fails if the guild didn't have that prefix)
	*/
	func remove(prefix: String, from id: GuildID) -> Bool {
		var guild = self.guild(forID: id)
		if let index = guild.prefixes.index(of: prefix) {
			guild.prefixes.remove(at: index)
			update(guild: guild, updatedPersistentData: true)
			return true
		}
		return false
	}

	/**
	Updates an alias in the specified guild
	- parameter alias: The name of the alias
	- parameter target: The target command/string or nil to clear the alias
	- parameter id: The id of the guild to update
	*/
	func set(alias: String, toCommand target: String?, in id: GuildID) {
		let alias = alias.lowercased()
		var guild = self.guild(forID: id)
		guard guild.aliases[alias]?.target != target else { return }
		if let target = target {
			guild.aliases[alias] = AliasedCommand(name: alias, target: target)
		}
		else {
			guild.aliases[alias] = nil
		}
		update(guild: guild, updatedPersistentData: true)
	}
}


//MARK: - Channels
extension Renge {
	/**
	Returns the URL of the location the save file for a particular channel
	- parameter channel: The ID of the channel to get the save file for
	- returns: A file URL to where the channel's save file should be
	*/
	func saveFileURL(forChannel channel: ChannelID) -> URL {
		return channelSaveDir.appendingPathComponent("Channel\(channel).json")
	}

	/**
	Looks up channel information using a channel id
	- parameter id: The ID of the channel you want information for
	- returns: The channel information for the specified ID
	*/
	func channel(for id: ChannelID) -> RengeChannel {
		return getFromSaveOrDefault(id: id, dict: &channels, saveFile: saveFileURL(forChannel: id), default: RengeChannel(id: id))
	}

	/**
	Updates the channel information storage with new information
	- parameter channel: The channel with the new information
	- parameter shouldSave: Whether or not the information that changed is included in the save file.  If it is, the save file needs updating, but if it isn't, then the save file doesn't need to be changed.
	*/
	func update(channel: RengeChannel, updatedPersistentData shouldSave: Bool) {
		channels[channel.id] = channel
		guard shouldSave else { return }
		save(channel, to: saveFileURL(forChannel: channel.id))
	}
}


//MARK: - Command handling
extension Renge {
	/**
	Gets the list of prefixes for a message
	- parameter message: The message to get prefixes for
	- returns: The list of prefixes for this message
	*/
	func prefixes(for channel: ChannelID) -> [String] {
		let guildPrefixes = guild(forChannel: channel)?.prefixes ?? defaultPrefixes
		return guildPrefixes + prefixes
	}

	/**
	Attempts to remove the bot prefix from a message
	- parameter message: The message to attempt to remove the prefix from
	- returns: The unprefixed message if a valid bot prefix was found, nil if the message wasn't prefixed
	*/
	func removePrefix(from message: DiscordMessage) -> Substring? {
		var scanner = StringScanner(message.content)
		for prefix in prefixes(for: message.channelId) {
			guard scanner.remove(prefix: prefix, matchingCase: false) else { continue }
			_ = scanner.read(whileInSet: .whitespacesAndNewlines)
			return scanner.rest
		}
		return nil
	}

	/**
	Gets the prefix that was used in a message
	- parameter message: The message to attempt to get the prefix from
	- returns: The prefix that was used in the message
	*/
	func prefixedUsed(in message: DiscordMessage) -> String? {
		var scanner = StringScanner(message.content)
		for prefix in prefixes(for: message.channelId) {
			guard scanner.remove(prefix: prefix, matchingCase: false) else { continue }
			return prefix
		}
		return nil
	}

	/**
	Attempts to extract a command name from a message
	- parameter unprefixedMessage: A StringScanner on the message with the prefix removed
	- parameter channel: The original channel ID of where the message was sent (used to get the source guild for guild aliases and such)
	- returns: A tuple of the command and a substring of the message with the command removed, or nil if no command was matched
	*/
	func getCommand<T>(unprefixedMessage: T, channel: ChannelID) -> Result<(RengeCommand, commandlessString: T.SubSequence), T.SubSequence?> where T: StringProtocol, T.SubSequence: StringProtocol {
		var scanner = StringScanner(unprefixedMessage)
		guard let rawCommandName = scanner.read(untilInSet: .whitespacesAndNewlines, clearDelimeter: true) else { return .failure(nil) }
		let commandName = rawCommandName.lowercased()
		print(commandName)
		print(unprefixedMessage)
		if let command = commands[commandName] {
			return .success((command, scanner.rest))
		}
		if let aliasedCommand = guild(forChannel: channel)?.aliases[commandName] {
			return .success((aliasedCommand, scanner.rest))
		}
		return .failure(rawCommandName)
	}

	/**
	Gets the appropriate response method
	*/
	func getResponseMethod(command: RengeCommand, user: UserID, channel: ChannelID) -> CommandResponseMethod {
		//TODO: Implement per-guild permissions
		switch command.permissionClass {
		case .botOwner:
			return user == botOwner ? .accept : .ignore
		case .admin:
			// TODO: Load all member data so admin checks actually work (right admins that aren't loaded will be denied)
			Renge.logger.debug("Guild ID: \(String(describing: (client.findChannel(fromId: channel) as? DiscordGuildTextChannel)?.guildId))", type: "RengePermissions")
			guard let guildID = ((client.findChannel(fromId: channel) as? DiscordGuildTextChannel)?.guildId), let guild = client.guilds[guildID] else { return .ignore }
			if guild.ownerId == user { return .accept }
			guard let member = guild.members[user] else { return .deny }
			if member.roles?.first(where: { $0.permissions.contains(.administrator) }) != nil {
				return .accept
			}
			return .deny
		case .guildMember:
			return client.findChannel(fromId: channel) is DiscordGuildTextChannel ? .accept : .ignore
		case .user:
			return .accept
		}
	}

	/**
	Executes a command
	- parameter command: The command to run
	- parameter message: The message that caused this command to be started
	- parameter commandlessString: The string that caused this command to be started, without the bot prefix or command name
	- parameter errorLogger: A custom function to log any errors that come up.  Use nil to default to a post in the message's channel
	- parameter shouldCheckPermission: Whether or not the bot should run permission checks.  Setting this to false will always run the command, even if the user who sent the message wouldn't otherwise have permission to do so.  This is very dangerous.
	*/
	func run(command: RengeCommand, message: DiscordMessage, commandlessString: Substring, user: UserID? = nil, channel: ChannelID? = nil, errorLogger: ((DiscordMessage) -> Void)? = nil, mainOutput: ((DiscordMessage) -> Void)? = nil) {
		let user = user ?? message.author.id
		let channel = channel ?? message.channelId
		let errorLogger = errorLogger ?? { [weak self] error in self?.client.sendMessage(error, to: channel) }
		let mainOutput = mainOutput ?? { [weak self] output in self?.client.sendMessage(output, to: channel) }
		let responseMethod = getResponseMethod(command: command, user: user, channel: channel)
		Renge.logger.verbose("Permission check returned \(responseMethod) in execution of \(command.name) for \(message.id)", type: "Renge")
		switch responseMethod {
		case .accept:
			command.execute(bot: self, arguments: commandlessString, messageObject: message, user: user, channel: channel, errorLogger: errorLogger, output: mainOutput)
		case .deny:
			errorLogger(DiscordMessage(content: "❌  |  **\(message.author.username)**, you don't have permission to use the **\(command.name)** command"))
		case .ignore:
			break
		}
	}
}


//MARK: - Command Responders

extension Renge {

	private func registerResponder<T>(_ messageResponder: MessageResponder, forKey key: T, shouldReplace: Bool, replacementReason: RemovalReason, dictionaryPath: ReferenceWritableKeyPath<Renge, [T: (MessageResponder, timeoutTask: WorkItem?)]>) -> Bool {
		guard shouldReplace || self[keyPath: dictionaryPath][key] == nil else { return false }
		let timeout = messageResponder.timeoutTime.map { time -> WorkItem in
			let timeout = WorkItem { [weak self] in
				_ = self // Works around a bug in the swift 4 compiler that puts up a warning saying we never used `self`.  If that bug is fixed, this line can be removed
				let responder = self?[keyPath: dictionaryPath].removeValue(forKey: key)
				responder?.0.willBeRemoved(reason: .timeout)
			}
			mainQueue.asyncAfter(deadline: DispatchTime(secondsFromNow: time), execute: { timeout.perform() })
			return timeout
		}
		if let old = self[keyPath: dictionaryPath].updateValue((messageResponder, timeout), forKey: key) {
			old.timeoutTask?.cancel()
			old.0.willBeRemoved(reason: replacementReason)
		}
		return true
	}

	@discardableResult
	func registerResponder(_ messageResponder: MessageResponder, forChannel channel: ChannelID, shouldReplace: Bool = true) -> Bool {
		return registerResponder(messageResponder, forKey: channel, shouldReplace: shouldReplace, replacementReason: .otherRemove, dictionaryPath: \Renge.channelResponders)
	}

	@discardableResult
	func registerResponder(_ messageResponder: MessageResponder, forUser user: UserID, inChannel channel: ChannelID, shouldReplace: Bool = true) -> Bool {
		let key = ChannelAndUser(channel: channel, user: user)
		return registerResponder(messageResponder, forKey: key, shouldReplace: shouldReplace, replacementReason: .otherRemove, dictionaryPath: \Renge.userChannelResponders)
	}

	private func removeResponder<T>(key: T, reason: RemovalReason, dictionaryPath: ReferenceWritableKeyPath<Renge, [T: (MessageResponder, timeoutTask: WorkItem?)]>) {
		if let responder = self[keyPath: dictionaryPath].removeValue(forKey: key) {
			responder.timeoutTask?.cancel()
			responder.0.willBeRemoved(reason: reason)
		}
	}

	func removeResponder(forChannel channel: ChannelID) {
		removeResponder(key: channel, reason: .otherRemove, dictionaryPath: \Renge.channelResponders)
	}

	func removeResponder(forUser user: UserID, inChannel channel: ChannelID) {
		let key = ChannelAndUser(channel: channel, user: user)
		removeResponder(key: key, reason: .otherRemove, dictionaryPath: \Renge.userChannelResponders)
	}

	private func runResponder<T>(key: T, on message: DiscordMessage, dictionaryPath: ReferenceWritableKeyPath<Renge, [T: (MessageResponder, timeoutTask: WorkItem?)]>) -> EventHandleMethod {
		guard let responder = self[keyPath: dictionaryPath][key]?.0 else { return .propagate }
		let (eventHandleMethod, responderHandleMethod) = responder.respond(to: message, bot: self)
		switch responderHandleMethod {
		case .keep: break
		case .remove:
			removeResponder(key: key, reason: .manualRemove, dictionaryPath: dictionaryPath)
		case .replace(with: let replacement):
			_ = registerResponder(replacement, forKey: key, shouldReplace: true, replacementReason: .manualReplace, dictionaryPath: dictionaryPath)
		}
		return eventHandleMethod
	}

	func runResponders(for message: DiscordMessage) -> EventHandleMethod {
		let key = ChannelAndUser(channel: message.channelId, user: message.author.id)
		let firstHandleMethod = runResponder(key: key, on: message, dictionaryPath: \Renge.userChannelResponders)
		guard firstHandleMethod == .propagate else { return firstHandleMethod }
		return runResponder(key: message.channelId, on: message, dictionaryPath: \Renge.channelResponders)
	}
}
