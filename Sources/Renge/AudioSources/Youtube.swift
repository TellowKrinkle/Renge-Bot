//
//  Youtube.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/09/14.
//

import Foundation

class YoutubeProvider : RengeAudioProvider {

	static let type: RengeAudioProviderType = .youtube

	static func recognizes(url: URL) -> Bool {
		guard let host = url.host else { return false }
		return host == "youtu.be" || host == "youtube.com" || host == "www.youtube.com"
	}
	
	static func getBrowserURL(info: RengeAudioInformation) -> URL? {
		var secondsString: String = ""
		if let seconds = info.seconds.flatMap(Int.init(checking:)){
			secondsString = "&t=\(seconds)s"
		}
		return URL(string: "https://youtube.com/watch?v=\(info.id)\(secondsString)")
	}

	/// Only gets the info from the URL, nothing else
	static private func extractInfo(url: URL) -> RengeAudioInformation? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

		var id: String? = nil
		var time: Int? = nil
		let query: [URLQueryItem]
		switch components.host {
		case .some("youtu.be"):
			let path = components.path
			guard path.first == "/" else { return nil }
			id = String(path.suffix(from: path.index(after: path.startIndex)))
			query = components.queryItems ?? []
		case .some("youtube.com"):
			fallthrough
		case .some("www.youtube.com"):
			let path = components.path
			if path.hasPrefix("/embed/") {
				id = String(path.suffix(from: path.index(path.startIndex, offsetBy: "/embed/".count)))
			}
			query = components.queryItems ?? []
		default:
			return nil
		}
		for item in query {
			if item.name == "v", let value = item.value {
				id = value
			}
			if item.name == "t", let value = item.value {
				if let newtime = Int(value) {
					time = newtime
				}
				else if let newtime = Util.hmsToSeconds(hmsTime: value).flatMap(Int.init(checking:)) {
					time = newtime
				}
			}
		}
		if let id = id {
			return RengeAudioInformation(type: YoutubeProvider.type, id: id, name: "", seconds: time.map(Double.init), volume: nil)
		}
		else {
			return nil
		}
	}

	static func makeProvider(url: URL, urlSession: URLSession, callback: @escaping (RengeAudioProvider?) -> ()) {
		guard let info = extractInfo(url: url) else { callback(nil); return }
		makeProvider(info, urlSession: urlSession, callback: callback)
	}

	private static let importantFields: Set<Substring> = ["title", "loudness", "relative_loudness", "adaptive_fmts", "author", "avg_rating", "timestamp", "length_seconds"]
	private static let errorType = "RengeYoutube"

	static func makeProvider(_ info: RengeAudioInformation, urlSession: URLSession, callback: @escaping (RengeAudioProvider?) -> ()) {
		guard let url = URL(string: "https://www.youtube.com/get_video_info?video_id=\(info.id)") else {
			Renge.logger.verbose("Failed to get YouTube info for \(info.id)", type: errorType)
			callback(nil)
			return
		}
		let completion: (Data?, URLResponse?, Error?) -> Void = { (data, _, _) -> Void in
			guard let data = data, let string = String(data: data, encoding: .utf8) else {
				callback(nil)
				return
			}
			
			let parts = Util.parseHTMLQueryItems(queryString: string[...], wantedPieces: importantFields)
			let partsDict = Dictionary(parts) { (first, second) -> Substring in
				Renge.logger.error("YouTube video info tags weren't unique in \(info.id)! First: \(first), Second: \(second)", type: errorType)
				return first
			}
			
			guard let fmts = partsDict["adaptive_fmts"].map(Util.removeYTPercentEnc)?.replacingOccurrences(of: ",", with: "&") else {
				Renge.logger.error("YouTube video info missing adaptive_fmts for \(info.id)", type: errorType)
				Renge.logger.debug("All fields: \(string)", type: errorType)
				callback(nil)
				return
			}
			print(Util.parseHTMLQueryItems(queryString: fmts[...]).filter({ $0.0 != "url" }))
			let fmtParts = Util.parseHTMLQueryItems(queryString: fmts[...], wantedPieces: ["type", "url", "bitrate"])
			print(fmtParts.map({ $0.0 }))
			
			var bestBitrate: Int? = nil
			var bestURL: Substring? = nil
			var valid: Bool = false
			var bitrate: Int? = nil
			var url: Substring? = nil
			for item in fmtParts {
				switch item.0 {
				case "type":
					valid = item.1.contains("audio")
					url = nil
					bitrate = nil
				case "bitrate":
					guard valid else { continue }
					bitrate = Int(item.1)
					if bitrate == nil {
						Renge.logger.error("Failed to get bitrate from \(item.1) in video \(info.id)", type: errorType)
					}
				case "url":
					guard valid else { continue }
					url = item.1
				default:
					Renge.logger.error("Unexpected header \(item.0) in video \(info.id) format list", type: errorType)
				}
				if valid, let bitrate = bitrate, let url = url, bitrate > bestBitrate ?? 0 {
					bestBitrate = bitrate
					bestURL = url
				}
			}
			
			print(bestURL ?? "No URL")
			
			guard let finalURL = bestURL.map(Util.removeYTPercentEnc).flatMap({ URL.init(string: $0 + "&ratebypass=yes") }) else {
				Renge.logger.verbose("Video for \(info.id) contained no valid audio streams", type: errorType)
				callback(nil)
				return
			}
			
			callback(YoutubeProvider(
				id: info.id,
				name: partsDict["title"].map(Util.removeYTPercentEnc) ?? "Unknown",
				audioURL: finalURL,
				seconds: partsDict["length_seconds"].flatMap(Double.init) ?? 0,
				ytvolume: partsDict["loudness"].flatMap(Double.init) ?? 0,
				ytRelativeLoudness: partsDict["relative_loudness"].flatMap(Double.init) ?? 0
			))
		}
		urlSession.dataTask(with: URLRequest(url: url, timeoutInterval: 10), completionHandler: completion).resume()
	}
	
	init(id: String, name: String, audioURL: URL, seconds: Double, ytvolume: Double, ytRelativeLoudness: Double) {
		self.id = id
		self.name = name
		self._audioURL = audioURL
		self.seconds = seconds
		self.ytvolume = ytvolume
		self.ytRelativeLoudness = ytRelativeLoudness
	}
	
	let id: String
	let name: String
	let _audioURL: URL
	let seconds: Double
	let ytvolume: Double
	let ytRelativeLoudness: Double
	
	var audioInfo: RengeAudioInformation {
		return RengeAudioInformation(type: YoutubeProvider.type, id: id, name: name, seconds: seconds, volume: ytvolume)
	}
	
	var audioURL: URL? {
		return _audioURL
	}
}
