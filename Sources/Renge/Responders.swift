//
//  Responders.swift
//  Renge-Bot
//
//  Created by TellowKrinkle on 2017/08/10.
//

// A responder is a temporary object that can be tied to a message (for reactions), channel, or channel + user, usually to respond to a question that was asked

import Foundation
import SwiftDiscord

/// How the bot should handle a message that was sent
/// The responder has the option of stopping the message from being handled by the normal command handling mechanisms
/// For example, a yes/no responder may want to stop the normal command from handling a `<prefix> yes` message.
enum EventHandleMethod {
	/// Don't do anything else with the message
	case ignore
	/// Handle the message normally
	case propagate
}

/// What the bot should do with the responder next
enum ResponderHandleMethod<T> {
	/// Keep the current responder in place
	case keep
	/// Remove the current responder, running its delete method
	case remove
	/// Replace the current responder with the included new one
	case replace(with: T)
}

/// A reason that a responder is being removed
enum RemovalReason {
	/// Responder returned `.remove` from a respond message
	case manualRemove
	/// Responder returned `.replace` from a respond message
	case manualReplace
	/// The responder timed out
	case timeout
	/// Something else requested that this responder be removed or replaced
	case otherRemove
}

protocol Responder: class {
	/// The time this responder will exist if it isn't interacted with
	/// nil means the responder will never time out
	var timeoutTime: Double? { get }
	/**
	Gets run when the responder is about to be removed.
	Can be used to delete a question message, for example.
	- parameter reason: The cause of the removal
	*/
	func willBeRemoved(reason: RemovalReason)
}

protocol MessageResponder : Responder {
	/**
	Responds to a message
	- parameter message: The message that was sent in this responder's domain
	- returns: What to do with the message and what to do with the responder
	*/
	func respond(to message: DiscordMessage, bot: Renge) -> (EventHandleMethod, ResponderHandleMethod<MessageResponder>)
}

/// For asking a yes or no question
class YesNoResponder : MessageResponder {
	let timeoutTime: Double?
	/// A callback that will be called when this responder is removed
	let removalCallback: (RemovalReason) -> ()
	/// A callback that will be called when the user responds.  The two inputs are the user's response (true for yes, false for no) as well as the actual message struct for that response
	let callback: (Bool, DiscordMessage) -> ()

	func respond(to message: DiscordMessage, bot: Renge) -> (EventHandleMethod, ResponderHandleMethod<MessageResponder>) {
		if let response = Util.yesNoValidator(message: message, bot: bot) {
			callback(response, message)
			return (.ignore, .remove)
		}
		else {
			return (.propagate, .keep)
		}
	}

	func willBeRemoved(reason: RemovalReason) {
		removalCallback(reason)
	}

	/**
	Simple init that fills properties
	- parameter timeoutTime: The time after which the question should time out
	- parameter removalCallback: A callback that will be called when this responder is removed
	- parameter reason: The reason the responder was removed
	- parameter callback: A callback that will be called when the user responds
	- parameter response: The user's response (true for yes, false for no)
	- parameter message: The message containing the user's response
	*/
	init(timeoutTime: Double?, removalCallback: @escaping (_ reason: RemovalReason) -> (), callback: @escaping (_ response: Bool, _ message: DiscordMessage) -> ()) {
		self.timeoutTime = timeoutTime
		self.removalCallback = removalCallback
		self.callback = callback
	}

	/**
	Automatically registers a new Yes/No responder which sends a question message and deletes the response when done
	- parameter bot: The bot to register on
	- parameter timeoutTime: The time after which the question should time out
	- parameter question: The message to send as the question
	- parameter yesResponse: What the bot should edit the question message to if the user answers yes
	- parameter noResponse: What the bot should edit the question message to if the user answers no
	- parameter user: The user to bind the question to
	- parameter channel: The channel to bind the question to
	- parameter defaultResponse: A default response to call the callback with if the user doesn't respond, or nil to not call the callback at all
	- parameter callback: The callback that will be run with the user's response if they respond
	- parameter response: The user's response
	*/
	static func registerResponder(bot: Renge, timeoutTime: Double?, question: DiscordMessage, yesResponse: String, noResponse: String, user: UserID, channel: ChannelID, defaultResponse: Bool?, callback: @escaping (_ response: Bool) -> ()) {
		var result: Bool? = nil
		var questionMessage: MessageID? = nil
		var responseMessage: MessageID? = nil

		let finishFunction = { [weak bot] in
			guard let result = result, let questionMessage = questionMessage, let bot = bot else { return }
			let message = result ? yesResponse : noResponse
			bot.client.editMessage(questionMessage, on: channel, content: message)
			if let responseMessage = responseMessage {
				bot.client.deleteMessage(responseMessage, on: channel)
			}
			callback(result)
		}

		bot.client.sendMessage(question, to: channel) { message in
			questionMessage = message?.id
			finishFunction()
		}

		let handler = YesNoResponder(
			timeoutTime: timeoutTime,
			removalCallback: { [weak bot] (reason) in
				if reason == .timeout || reason == .otherRemove, let questionMessage = questionMessage {
					bot?.client.editMessage(questionMessage, on: channel, content: "Question timed out")
					if let defaultResponse = defaultResponse {
						callback(defaultResponse)
					}
				}
			},
			callback: { (response, message) in
				result = response
				responseMessage = message.id
				finishFunction()
			}
		)

		bot.registerResponder(handler, forUser: user, inChannel: channel)
	}
}

class QuestionResponder : MessageResponder {
	let timeoutTime: Double?
	/// A callback that will be called when this responder is removed
	let removalCallback: (RemovalReason) -> ()
	/// A validator that returns whether a message is a valid response to the question
	let validator: (DiscordMessage, Renge) -> Bool
	/// A callback that will be called when the user responds.  The two inputs are the user's response (true for yes, false for no) as well as the actual message struct for that response
	let callback: (DiscordMessage, Renge) -> ()

	func respond(to message: DiscordMessage, bot: Renge) -> (EventHandleMethod, ResponderHandleMethod<MessageResponder>) {
		if validator(message, bot) {
			callback(message, bot)
			return (.ignore, .remove)
		}
		else {
			return (.propagate, .keep)
		}
	}

	func willBeRemoved(reason: RemovalReason) {
		removalCallback(reason)
	}

	/**
	Simple init that fills properties
	- parameter timeoutTime: The time after which a timeout should occur
	- parameter validator: A callback to decide whether a user's message is a valid answer to the question
	- parameter message: The user's response to the question
	- parameter bot: Easy access to the bot
	- parameter removalCallback: A callback that will be called when this responder is removed
	- parameter reason: The reason the responder was removed
	- parameter callback: A callback that will be called when the user responds.
	*/
	init(timeoutTime: Double?, validator: @escaping (_ message: DiscordMessage, _ bot: Renge) -> Bool, removalCallback: @escaping (_ reason: RemovalReason) -> (), callback: @escaping (_ message: DiscordMessage, _ bot: Renge) -> ()) {
		self.timeoutTime = timeoutTime
		self.validator = validator
		self.removalCallback = removalCallback
		self.callback = callback
	}

	/**
	Automatically registers a new question responder which sends a question message and calls a callback on response
	- parameter bot: The bot to register on
	- parameter timeoutTime: The time after which the question should time out
	- parameter question: The message to send as the question
	- parameter user: The user to bind the question to
	- parameter channel: The channel to bind the question to
	- parameter validator: A callback to decide whether a user's message is a valid answer to the question
	- parameter message: The user's answer to the question
	- parameter responseBot: Easy access to the bot
	- parameter callback: The callback that will be run with the user's response if they respond
	- parameter sentQuestion: The message object for the question sent by the bot
	- parameter userResponse: The message object for the user's response to the question
	*/
	static func registerResponder(bot: Renge, timeoutTime: Double?, question: DiscordMessage, user: UserID, channel: ChannelID, validator: @escaping (_ message: DiscordMessage, _ responseBot: Renge) -> Bool, callback: @escaping (_ sentQuestion: DiscordMessage, _ userResponse: DiscordMessage) -> ()) {
		var response: DiscordMessage? = nil
		var sentQuestion: DiscordMessage? = nil

		let finishFunction = {
			guard let response = response, let sentQuestion = sentQuestion else { return }
			callback(sentQuestion, response)
		}

		bot.client.sendMessage(question, to: channel) { message in
			sentQuestion = message
			finishFunction()
		}

		let handler = QuestionResponder(
			timeoutTime: timeoutTime,
			validator: validator,
			removalCallback: { [weak bot] (reason) in
				if reason == .timeout || reason == .otherRemove, let sentQuestion = sentQuestion {
					bot?.client.editMessage(sentQuestion.id, on: channel, content: "Question timed out")
				}
			},
			callback: { message, bot in
				response = message
				finishFunction()
			}
		)

		bot.registerResponder(handler, forUser: user, inChannel: channel)
	}

	/**
	Automatically registers a new question responder which sends a question message and calls a callback on response

	- parameter bot: The bot to register on
	- parameter timeoutTime: The time after which the question should time out
	- parameter question: The message to send as the question
	- parameter user: The user to bind the question to
	- parameter channel: The channel to bind the question to
	- parameter shouldDeleteQuestion: Whether or not to delete the asked question.  This will only be used if the callback returns nil
	- parameter shouldDeleteResponse: Whether or not the user's response to the question should be deleted
	- parameter validator: A callback to decide whether a user's message is a valid answer to the question
	- parameter message: The user's answer to the question
	- parameter responseBot: Easy access to the bot
	- parameter callback: The callback that will be run with the user's response if they respond.  The original message will be edited to the return value of this function
	- parameter userResponse: The the user's response to the question
	*/
	static func registerResponder(bot: Renge, timeoutTime: Double?, question: DiscordMessage, user: UserID, channel: ChannelID, shouldDeleteQuestion: Bool, shouldDeleteResponse: Bool, validator: @escaping (_ message: DiscordMessage, _ responseBot: Renge) -> Bool, callback: @escaping (_ userResponse: String) -> String?) {
		var sentQuestionID: MessageID? = nil
		var response: (String, MessageID)? = nil

		let finishFunction = { [weak bot] in
			guard let response = response, let sentQuestionID = sentQuestionID else { return }
			if shouldDeleteResponse {
				bot?.client.deleteMessage(response.1, on: channel)
			}
			if let edit = callback(response.0) {
				bot?.client.editMessage(sentQuestionID, on: channel, content: edit)
			}
			else if shouldDeleteQuestion {
				bot?.client.deleteMessage(sentQuestionID, on: channel)
			}
		}

		bot.client.sendMessage(question, to: channel) { message in
			sentQuestionID = message?.id
			finishFunction()
		}

		let handler = QuestionResponder(
			timeoutTime: timeoutTime,
			validator: validator,
			removalCallback: { [weak bot] (reason) in
				if reason == .timeout || reason == .otherRemove, let sentQuestionID = sentQuestionID {
					bot?.client.editMessage(sentQuestionID, on: channel, content: "Question timed out")
				}
			},
			callback: { message, bot in
				response = (message.content, message.id)
				finishFunction()
			}
		)

		bot.registerResponder(handler, forUser: user, inChannel: channel)
	}
}
