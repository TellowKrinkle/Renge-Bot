//
//  AudioProvider.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/09/14.
//

import Foundation

let audioProviderList: [RengeAudioProvider.Type] = [YoutubeProvider.self]

/// To make RengeAudioProvider.Type conform to Codable
enum RengeAudioProviderType : String, Codable {
	case youtube = "Youtube"

	var provider: RengeAudioProvider.Type {
		switch self {
		case .youtube: return YoutubeProvider.self
		}
	}
}

protocol RengeAudioProvider {
	/// The type of the provider
	static var type: RengeAudioProviderType { get }
	/// Checks if a URL is recognized (using the URL only)
	static func recognizes(url: URL) -> Bool
	/// Gets a usable url from an AudioInformation struct (for use by non-bots)
	static func getBrowserURL(info: RengeAudioInformation) -> URL?
	
	/// Makes an instance of the provider using a URL
	static func makeProvider(url: URL, urlSession: URLSession, callback: @escaping (RengeAudioProvider?) -> ())
	
	/// Makes an instance of the provider using a RengeAudioInformation struct
	static func makeProvider(_ info: RengeAudioInformation, urlSession: URLSession, callback: @escaping (RengeAudioProvider?) -> ())
	
	/// Get an audioInfo struct for storage
	var audioInfo: RengeAudioInformation { get }
	/// Get the url to the playable audio file (for use by the bot)
	var audioURL: URL? { get }
	
}

struct RengeAudioInformation : Codable {
	let type: RengeAudioProviderType
	let id: String
	let name: String
	var seconds: Double?
	var volume: Double?

	var url: URL? {
		return type.provider.getBrowserURL(info: self)
	}
}
