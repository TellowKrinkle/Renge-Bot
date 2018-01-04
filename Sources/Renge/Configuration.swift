import Foundation
import SwiftDiscord

let defaultBotName = "Renge"
let defaultSaveSubdirs = ["Guilds", "Channels"]

struct BotInfo {
	let botName: String
	let owner: UserID
	let token: String
	let saveDirectory: URL
}

enum ConfigurationLoadError: Error {
	case filesystemError(String)
	case fileFormatError(String)
	var localizedDescription: String {
		switch self {
		case let .filesystemError(desc):
			return desc
		case let .fileFormatError(desc):
			return desc
		}
	}
}

/**
Check to see if a file exists and whether it is a directory or not
Helpful due to the fact that the FileManager function signature differs between macOS and Linux
- parameter url: The url to check
- returns: A tuple with `Bool`s for whether or not the file exists, and whether or not it's a directory
*/
private func checkFile(at url: URL) -> (exists: Bool, isDirectory: Bool) {
	#if os(Linux)
		var isDirectory: Bool = false
		let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
		return (exists, isDirectory)
	#else
		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
		return (exists, isDirectory.boolValue)
	#endif
}

/**
Create a directory at the specified location if one doesn't already exist there
- parameter url: The url to create the directory at
- parameter createIntermediates: Whether or not intermediate directories should be created
- parameter directoryDescription: A short description of the directory for use in error messages
- throws: A `ConfigurationLoadError` if it fails to create the directory or if a non-file directory already exists at the target location
*/
private func createDirIfNotExist(at url: URL, withIntermediateDirectories createIntermediates: Bool, directoryDescription: String) throws {
	let (exists, isDirectory) = checkFile(at: url)
	if !exists {
		do {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
		}
		catch let error {
			throw ConfigurationLoadError.filesystemError("Failed to create \(directoryDescription) at \(url): \(error.localizedDescription)")
		}
	}
	else {
		guard isDirectory else {
			throw ConfigurationLoadError.filesystemError("A non-directory file exists at \(directoryDescription) \(url)")
		}
	}
}

private func getConfigurationDirectory(botName: String) throws -> URL {
	#if os(Linux)
		let myApplicationSupportDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/TKRDiscord")
	#else
		guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
			throw ConfigurationLoadError.filesystemError("Couldn't get Application Support directory")
		}
		let myApplicationSupportDirectory = applicationSupport.appendingPathComponent("TKRDiscord", isDirectory: true)
	#endif
	try createDirIfNotExist(at: myApplicationSupportDirectory, withIntermediateDirectories: false, directoryDescription: "my Application Support directory")
	return myApplicationSupportDirectory
}

func getBotInfo(botName: String = defaultBotName, saveSubdirs: [String] = defaultSaveSubdirs) throws -> BotInfo {
	let ownerDemo = "ID of bot owner here"
	let tokenDemo = "Put Token Here"
	let saveDirDemo = "Path to Save Directory Here"
	let configurationURL = try getConfigurationDirectory(botName: botName).appendingPathComponent("\(botName)Configuration.plist")

	func loadAndCheckDefault<T: Comparable>(_ value: T?, default defaultVal: T, configName: String) throws -> T {
		guard let value = value else {
			throw ConfigurationLoadError.fileFormatError("Couldn't load \(configName) from configuration file \(configurationURL)")
		}
		guard value != defaultVal else {
			throw ConfigurationLoadError.fileFormatError("Configuration file \(configurationURL) still has the default info for \(configName).  Please replace it with the correct information.")
		}
		return value
	}

	guard let configuration = NSDictionary(contentsOf: configurationURL) else {
		if FileManager.default.fileExists(atPath: configurationURL.path) {
			throw ConfigurationLoadError.filesystemError("Invalid file in place of my configuration plist: \(configurationURL)")
		}
		let demoConfiguration: [String: Any] = ["owner": ownerDemo, "token": tokenDemo, "saveDirectory": saveDirDemo]
		(demoConfiguration as NSDictionary).write(to: configurationURL, atomically: true)
		throw ConfigurationLoadError.filesystemError("Configuration plist missing, a new one was created at \(configurationURL).  Please fill it with the required information.")
	}
	let ownerString = try loadAndCheckDefault(configuration["owner"] as? String, default: ownerDemo, configName: "owner's ID")
	guard let owner = UserID(ownerString) else {
		throw ConfigurationLoadError.fileFormatError("User ID not a Snowflake ID in configuration file \(configurationURL)")
	}
	let token = try loadAndCheckDefault(configuration["token"] as? String, default: tokenDemo, configName: "bot token")
	let saveDirString = try loadAndCheckDefault(configuration["saveDirectory"] as? String, default: saveDirDemo, configName: "save directory")
	let saveDir = URL(fileURLWithPath: (saveDirString as NSString).expandingTildeInPath)
	try createDirIfNotExist(at: saveDir, withIntermediateDirectories: true, directoryDescription: "save location")
	for subdir in saveSubdirs {
		try createDirIfNotExist(at: saveDir.appendingPathComponent(subdir), withIntermediateDirectories: true, directoryDescription: "save location")
	}

	return BotInfo(botName: botName, owner: owner, token: token, saveDirectory: saveDir)
}

