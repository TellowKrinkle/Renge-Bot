//
//  YoutubeDL.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/11/03.
//

import Foundation

struct YoutubeDLYoutubeInfo : Codable {

}

class YoutubeDL {
	static let shared = YoutubeDL()
	let process = Process()
	let outPipe = Pipe()
	let handleQueue = DispatchQueue(label: "Renge.YoutubeDLHandlerQueue")
	var callbacks: [(Data) -> ()] = []

	init() {
		process.standardInput = outPipe
		Util.runTextProcess(
			arguments: ["python", "-c", YoutubeDL.extractorCode],
			process: process,
			stderr: false,
			completion: {
				Renge.logger.log("Youtube-dl process died", type: "YoutubeDL")
			},
			lineCallback: { [weak self] (line) in
				self?.handleQueue.async {
					guard let callback = self?.callbacks.removeFirst() else {
						Renge.logger.error("Youtube-dl outputted but no callback to run!", type: "YoutubeDL")
						return
					}
					callback(line)
				}
			}
		)
	}

//	func youtube(url: String) ->

	static let extractorCode = """
	from __future__ import unicode_literals
	from __future__ import print_function
	import youtube_dl
	from youtube_dl.extractor.youtube import YoutubeIE
	import sys
	import json

	class Logger(object):
		def debug(self, msg):
			pass
		def warning(self, msg):
			pass
		def error(self, msg):
			pass

	youtubeDLOpts = {
		'format': 'bestaudio/best',
		'logger': Logger(),
		'forcejson': True,
		'quiet': True,
		'simulate': True,
		'youtube_include_dash_manifest': False
	}

	ydl = youtube_dl.YoutubeDL(youtubeDLOpts)
	extractor = ydl.get_info_extractor("Youtube")
	extractor.set_downloader(ydl)
	extractor.initialize()

	while True:
		try:
			line = sys.stdin.readline()
			if line == "":
				break
			line = line.strip()
			print("Downloading " + line + "...", file=sys.stderr)
			result = extractor.extract(line)
			print(json.dumps(result))
		except youtube_dl.utils.ExtractorError as e:
			print("{}")
			print("Youtube DL Download Error downloading file " + line + ": " + str(e), file=sys.stderr)
	"""
}
