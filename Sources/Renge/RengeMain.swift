//
//  RengeMain.swift
//  Workaround to SPM's issue with Tests of Executables
//

import Foundation
import SwiftDiscord

public func RengeStart() {
	let info: BotInfo
	do {
		info = try getBotInfo()
	}
	catch let error as ConfigurationLoadError {
		print(error)
		exit(EXIT_FAILURE)
	}
	catch let error {
		print(error)
		exit(EXIT_FAILURE)
	}

	Renge.logger = RengeLogger(level: .debug)

	let renge = Renge(info: info)
	renge.connect()

	CFRunLoopRun()
//	let session = URLSession(configuration: .default)
//	let group = DispatchGroup()
//	group.enter()
////	let hnote = "https://www.youtube.com/embed/wBZt40dBgKs"
//	let nanairo = "https://www.youtube.com/watch?v=j6WuUAuD8JU"
//	YoutubeProvider.makeProvider(url: URL(string: nanairo)!, urlSession: session) { provider in
//		print("Got audio provider: \(provider?.audioInfo), url: \(provider?.audioURL)")
//		Util.runTextProcess(
//			arguments: ["ffmpeg", "-nostdin", "-y", "-i", provider!.audioURL!.absoluteString, "-filter:a", "volumedetect", "-vn", "-sn", "-dn", "-f", "null", "/dev/null"],
//			stderr: true,
//			completion: { print("leaving"); group.leave() },
//			lineCallback: { (line) in
//			print("\(Date()) Got line: \(line)")
//		})
//	}
//	group.wait()

}
