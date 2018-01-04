//
//  CardPlanCalculator.swift
//  RengePackageDescription
//
//  Created by TellowKrinkle on 2018/01/04.
//

import Foundation
import SwiftDiscord
import Dispatch
import Atomics

// From https://docs.rs/crate/seahash/3.0.5/source/src/helper.rs
@_transparent
fileprivate func seahashDiffuse(_ number: UInt64) -> UInt64 {
	var x = number &* 0x6eed0e9da4d94a4f
	let a = x >> 32
	let b = x >> 60
	x ^= a &>> b
	return x &* 0x6eed0e9da4d94a4f
}

/// CardPlanCalculator Namespace
/// Calculates how to use crystals on the Amusement Club bot
public enum CardPlanCalculator {

	public final class AtomicFlag {
		private var atomic: AtomicBool
		var value: Bool {
			@inline(__always)
			get {
				return atomic.load()
			}
			@inline(__always)
			set {
				atomic.store(newValue)
			}
		}
		init(_ value: Bool) {
			atomic = AtomicBool()
			atomic.store(value)
		}
	}

	/// Represents a Crystal
	public enum Crystal : String {
		case platinum
		case gold
		case cyan
		case magenta
		case red
		case green
		case blue

		static let allCrystals: [Crystal] = [.platinum, .gold, .cyan, .magenta, .red, .green, .blue]
	}

	/// Represents a crystal recipe
	public struct CrystalRecipe : Comparable {
		let stars: Int
		let name: String
		let recipe: [Crystal]

		public static func ==(lhs: CrystalRecipe, rhs: CrystalRecipe) -> Bool {
			return lhs.stars == rhs.stars && lhs.name == rhs.name
		}

		public static func <(lhs: CrystalRecipe, rhs: CrystalRecipe) -> Bool {
			// Stars are sorted in reverse order (higher star count first)
			if lhs.stars > rhs.stars { return true }
			if lhs.stars < rhs.stars { return false }
			return lhs.name < rhs.name
		}
	}

	/// A list of crystals with easy methods to use crystals
	public struct CrystalList : Equatable, Hashable {
		public typealias CrystalInt = UInt8

		public var platinum: CrystalInt
		public var gold: CrystalInt
		public var cyan: CrystalInt
		public var magenta: CrystalInt
		public var red: CrystalInt
		public var green: CrystalInt
		public var blue: CrystalInt

		public var total: Int {
			return Int(platinum) + Int(gold) + Int(cyan) + Int(magenta) + Int(red) + Int(green) + Int(blue)
		}

		public static func ==(lhs: CrystalList, rhs: CrystalList) -> Bool {
			return
				lhs.blue == rhs.blue &&
					lhs.green == rhs.green &&
					lhs.red == rhs.red &&
					lhs.magenta == rhs.magenta &&
					lhs.cyan == rhs.cyan &&
					lhs.gold == rhs.gold &&
					lhs.platinum == rhs.platinum
		}

		public var hashValue: Int {
			// For better build times
			let top = UInt64(bitPattern: Int64(platinum)) << 48 ^ UInt64(bitPattern: Int64(gold)) << 40
			let middle = UInt64(bitPattern: Int64(cyan)) << 32 ^ UInt64(bitPattern: Int64(magenta)) << 24
			let bottom = UInt64(bitPattern: Int64(red)) << 16 ^ UInt64(bitPattern: Int64(green)) << 8 ^ UInt64(bitPattern: Int64(blue))
			let total = top ^ middle ^ bottom
			// Use diffuse function since otherwise changing one number only changes specific part of the output
			return Int(truncatingIfNeeded: seahashDiffuse(total))
		}

		subscript(crystal: Crystal) -> CrystalInt {
			get {
				switch crystal {
				case .platinum: return platinum
				case .gold:     return gold
				case .cyan:     return cyan
				case .magenta:  return magenta
				case .red:      return red
				case .green:    return green
				case .blue:     return blue
				}
			}
			set {
				switch crystal {
				case .platinum: platinum = newValue
				case .gold:     gold = newValue
				case .cyan:     cyan = newValue
				case .magenta:  magenta = newValue
				case .red:      red = newValue
				case .green:    green = newValue
				case .blue:     blue = newValue
				}
			}
		}

		public mutating func use(_ crystal: Crystal) -> Bool {
			if self[crystal] <= 0 {
				return false
			}
			else {
				self[crystal] -= 1
				return true
			}
		}

		@_transparent
		public mutating func use<S>(_ crystals: S) -> Bool where S: Sequence, S.Element == Crystal {
			var tmp = self
			for crystal in crystals {
				if !tmp.use(crystal) {
					return false
				}
			}
			self = tmp
			return true
		}

		public init(platinum: CrystalInt = 0, gold: CrystalInt = 0, cyan: CrystalInt = 0, magenta: CrystalInt = 0, red: CrystalInt = 0, green: CrystalInt = 0, blue: CrystalInt = 0) {
			self.platinum = platinum
			self.gold = gold
			self.cyan = cyan
			self.magenta = magenta
			self.red = red
			self.green = green
			self.blue = blue
		}

		public init<S>(crystalCounts: S) where S: Sequence, S.Element == (Crystal, CrystalInt) {
			self.init()
			for (crystal, count) in crystalCounts {
				self[crystal] = self[crystal] &+ count
			}
		}
	}


	// TODO: Don't hardcode this
	public static let recipes = try! CrystalRecipe.recipeList(fromCSV: """
	Stars	Card	Crystals
	4	A Scientific Christmas	Red	Cyan	Blue
	4	Christmas Pets	Cyan	Red	Magenta
	4	Christmas Singing Time	Green	Green	Cyan
	4	Couldn't Stay Awake	Gold	Green	Green
	4	Festive Nosebleed	Gold	Red	Green
	4	First Year Fun	Green	Red	Cyan
	4	Girls Und Weihnachten	Cyan	Red	Cyan
	4	Hero Reindeer Squad	Blue	Blue	Magenta
	4	Is The Order A Santa	Cyan	Cyan	Blue
	4	Jingle All The Way	Magenta	Green	Magenta
	4	Lets Create Some Memories	Blue	Cyan	Red
	4	Low Quality Padoru	Red	Magenta	Red
	4	Lowee Gift Delivery	Blue	Magenta	Blue
	4	Nico Puri Santa	Blue	Red	Blue	Cyan
	4	Padoru Padoru	Red	Blue	Gold
	4	Santa Assassination	Gold	Blue	Blue
	4	Satan Exclusion Day	Gold	Blue	Green
	4	Spare Some Time	Red	Magenta	Green
	4	Tehepero	Blue	Red	Gold
	4	The Gathering	Gold	Blue	Red
	4	Walking Home	Magenta	Gold	Green
	3	A Genuine Santa	Red	Blue	Blue
	3	Advent Angel	Magenta	Blue	Cyan
	3	Bashful Presence	Green	Cyan	Cyan
	3	Be My Guide	Magenta	Blue	Red
	3	Biblical Magi	Magenta	Blue	Blue
	3	Building A Tree	Green	Blue	Magenta
	3	Bunny Santa	Cyan	Blue	Green
	3	Coal Heart	Magenta	Red	Red
	3	Devils And Idols	Magenta	Cyan	Red
	3	Einzbern Christmas	Green	Red	Red
	3	Eromanga Celebration	Green	Blue	Cyan
	3	Extra Sleigh	Cyan	Green	Green	Blue
	3	Fated Christmas	Cyan	Green	Green
	3	Festive Karen	Cyan	Green	Blue
	3	Festive Magic	Magenta	Magenta	Cyan
	3	Festive Tornado	Green	Cyan	Red
	3	Forces Tree	Cyan	Green	Cyan
	3	Gifts For Despair	Cyan	Red	Red
	3	Hark The Herald Angel	Red	Cyan	Green
	3	Himouto Reindeer	Red	Red	Cyan
	3	Ho Ho Ho	Green	Green	Green
	3	Idols And Xmas	Cyan	Green	Red
	3	Illuminated Maki	Magenta	Green	Blue
	3	Kancolle Xmas	Green	Magenta	Blue
	3	Latifah And Reindeer	Cyan	Magenta	Green
	3	Lizzy By The Fire	Cyan	Blue	Cyan
	3	Magical Carnival Ride	Cyan	Blue	Red
	3	Mayu Kurisumas	Blue	Blue	Cyan
	3	Merry Explosions	Cyan	Cyan	Cyan
	3	Merry Tiger	Blue	Green	Cyan
	3	Nico Xmas Time	Magenta	Cyan	Blue
	3	Pair Of Santa	Cyan	Blue	Red	Green
	3	Party's Over	Magenta	Green	Red
	3	Raphiel The Banisher	Magenta	Red	Blue
	3	Reindeer Hug	Magenta	Blue	Green
	3	Rem Xmas Time	Blue	Green	Magenta
	3	Satan Claus	Green	Cyan	Magenta
	3	Snowy Stars	Green	Magenta	Green
	3	So Many Gifts	Green	Red	Green
	3	Suspicious Santa	Red	Cyan	Red
	3	Tsundere Gifts	Blue	Red	Red
	""")

	/// The actual calculator
	public enum PlanCalculator {
		public typealias RecipeInt = UInt8

		private struct MemoState : Hashable {
			let position: RecipeInt
			let cards: RecipeInt
			let crystals: CrystalList

			var hashValue: Int {
				let partial = UInt64(bitPattern: Int64(position.hashValue)) ^ UInt64(bitPattern: Int64(cards.hashValue)) << 32
				return Int(truncatingIfNeeded: seahashDiffuse(UInt64(bitPattern: Int64(crystals.hashValue)) ^ partial))
			}

			static func ==(lhs: MemoState, rhs: MemoState) -> Bool {
				return lhs.position == rhs.position && lhs.cards == rhs.cards && lhs.crystals == rhs.crystals
			}

			init(_ position: RecipeInt, _ crystals: CrystalList, cards: RecipeInt) {
				self.position = position
				self.crystals = crystals
				self.cards = cards
			}
		}

		private enum ShouldMake {
			case yes
			case no
			case either
		}

		public static func calculatePlan(recipeList: [CrystalRecipe], crystals: CrystalList, cancellationFlag: AtomicFlag? = nil) -> (recipes: [CrystalRecipe], leftovers: CrystalList, trials: Int) {
			typealias PlanChoice = (ShouldMake, score: RecipeInt)

			let totalRecipes = RecipeInt(recipeList.count)
			var memo: [MemoState: PlanChoice] = [:]
			var overallBest: RecipeInt = 0;

			func recursivePlanCalculator(state: MemoState) -> PlanChoice {
				if cancellationFlag?.value == true { return (.no, 0) }
				var crystals = state.crystals
				let position = state.position
				let cards = state.cards
				let current = recipeList[Int(position)]
				if position == recipeList.count - 1 {
					let returnValue: PlanChoice = crystals.use(current.recipe) ? (.yes, 1) : (.no, 0)
					return returnValue
				}
				if cards + (totalRecipes - position) < overallBest { return (.no, 0) }

				if let memoized = memo[state] { return memoized }

				var best: PlanChoice? = nil

				if crystals.use(current.recipe) {
					let yes = recursivePlanCalculator(state: MemoState(position + 1, crystals, cards: cards + 1))
					best = (.yes, yes.score + 1)
					overallBest = max(overallBest, cards + yes.score + 1)
				}

				let no = recursivePlanCalculator(state: MemoState(position + 1, state.crystals, cards: cards))
				if best == nil || best!.score < no.score {
					best = (.no, no.score)
				}
				else if best!.score == no.score {
					best = (.either, no.score)
				}

				memo[state] = best!
				return best!
			}

			var output: [CrystalRecipe] = []
			var crystals = crystals

			for (index, recipe) in recipeList.enumerated() {
				let choice = recursivePlanCalculator(state: MemoState(RecipeInt(index), crystals, cards: RecipeInt(output.count)))
				switch choice.0 {
				case .no: break
				case .either: fallthrough // Will do something else later
				case .yes:
					output.append(recipe)
					let worked = crystals.use(recipe.recipe)
					assert(worked, "Couldn't use recipe we should have been able to use!")
				}

			}

			return (output, crystals, memo.count)
		}
	}
}

/// Adds a fromCSV method for Crystal Lists
extension CardPlanCalculator.CrystalRecipe {
	struct CrystalRecipeCreationError : Error {
		let failedLines: [Int]
	}

	static func recipeList(fromCSV csv: String) throws -> [CardPlanCalculator.CrystalRecipe] {
		let lines = csv.split(separator: "\n")
		guard let firstLine = lines.first else { return [] }
		let delimeter: Character
		if firstLine.contains("\t") {
			delimeter = "\t"
		}
		else {
			delimeter = ","
		}
		let parts = lines.lazy.map { (line: Substring) -> LazyMapCollection<[Substring], String> in
			return line.split(separator: delimeter).lazy.map { (part: Substring) -> String in
				return part.trimmingCharacters(in: .whitespacesAndNewlines)
			}
		}

		let recipes = parts.map { line -> CardPlanCalculator.CrystalRecipe? in
			guard line.count >= 5 else { return nil }
			guard let stars = Int(line[0]) else { return nil }
			let name = line[1]
			let restOfLine = line.dropFirst(2)
			let optionalCrystals = restOfLine.lazy.map({ CardPlanCalculator.Crystal(rawValue: $0.lowercased()) })
			let crystals = Array(optionalCrystals.flatMap({ $0 }))
			guard optionalCrystals.count == crystals.count else { return nil }
			return CardPlanCalculator.CrystalRecipe(stars: stars, name: name, recipe: crystals)
		}

		guard let firstRecipe = recipes.first else { return [] }

		// Needed to be able to dropFirst and keep the same type
		var shortenedRecipes = recipes[...]
		if firstRecipe == nil {
			shortenedRecipes = shortenedRecipes.dropFirst()
		}

		// First recipe can be nil (title row), but the rest should all exist
		let failed = shortenedRecipes.enumerated().flatMap({ $0.element == nil ? $0.offset : nil })

		guard failed.count == 0 else {
			let extra = firstRecipe == nil ? 1 : 0
			throw CrystalRecipeCreationError(failedLines: failed.map({ $0 + extra }))
		}

		return shortenedRecipes.flatMap({ $0 })
	}
}

extension CardPlanCalculator.CrystalRecipe : CustomStringConvertible {
	public var description: String {
		return "\(stars)★ \(name) [\(recipe.map({ $0.rawValue }).joined(separator: ", "))]"
	}
}

struct RengeCardPlan : RengeCommand {
	var name: String { return "CardPlan" }

	var category: String { return "Random" }

	var shortDescription: String { return "Generates a list of cards to craft for <@340988108222758934> based on the crystals you have" }

	var usage: String? { return "<Either list of crystals amounts in the order gold cyan magenta red green blue or crystal types followed by numbers like gold 3 cyan 4> [stars (3|4)] [have <comma separated list of cards to not search>]" }

	var permissionClass: PermissionClass { return .user }

	static let executionQueue = DispatchQueue(label: "Renge.CardPlanCalculatorQueue", qos: .userInitiated)

	func execute(bot: Renge, arguments: Substring, messageObject: DiscordMessage, user: UserID, channel: ChannelID, errorLogger: @escaping (DiscordMessage) -> Void, output: @escaping (DiscordMessage) -> Void) {
		var split = arguments.lowercased().components(separatedBy: .whitespacesAndNewlines)
		var recipes = CardPlanCalculator.recipes
		if let haveIndex = split.index(of: "have") {
			let haveString = split[(haveIndex + 1)...].joined(separator: " ")
			split[haveIndex...] = []
			let haveList = haveString.split(separator: ",").lazy.map({ return $0.trimmingCharacters(in: .whitespaces) })
			for cardName in haveList {
				let filtered = recipes.enumerated().filter({ $0.element.name.lowercased().contains(cardName) })
				guard var card = filtered.first else {
					errorLogger(DiscordMessage(content: "Failed to find card with name \(cardName)"))
					return
				}
				if filtered.count > 1 {
					let newFiltered = filtered.filter({ $0.element.name.lowercased().hasPrefix(cardName) })
					guard newFiltered.count == 1 else {
						errorLogger(DiscordMessage(content: "Multiple cards were found matching \(cardName), please be more specific.  Cards:\n\(filtered.map({ $0.element.name }).joined(separator: "\n"))"))
						return
					}
					card = newFiltered[0]
				}
				recipes.remove(at: card.offset)
			}
		}
		if let starsIndex = split.index(of: "stars") {
			guard starsIndex + 1 < split.endIndex, let stars = Int(split[starsIndex + 1]), stars == 3 || stars == 4 else {
				errorLogger("The number of stars must be either 3 or 4")
				return
			}
			recipes = recipes.filter({ $0.stars == stars })
			split[starsIndex...(starsIndex + 1)] = []
		}
		var crystalArray: [(CardPlanCalculator.Crystal, CardPlanCalculator.CrystalList.CrystalInt)] = []
		var i = 0
		var crystalPos = 1
		while i < split.count && crystalPos < CardPlanCalculator.Crystal.allCrystals.count {
			if let count = CardPlanCalculator.CrystalList.CrystalInt(split[i]) {
				crystalArray.append((CardPlanCalculator.Crystal.allCrystals[crystalPos], count))
				crystalPos += 1
			}
			else if let crystal = CardPlanCalculator.Crystal(rawValue: split[i]), i + 1 < split.count, let count = CardPlanCalculator.CrystalList.CrystalInt(split[i + 1]) {
				crystalArray.append((crystal, count))
				i += 1
			}
			i += 1
		}

		let crystals = CardPlanCalculator.CrystalList(crystalCounts: crystalArray)

		Renge.logger.verbose("Calculating Card Plan for \(crystals)", type: "RengeCardPlan")
		let flag = CardPlanCalculator.AtomicFlag(false)
		RengeCardPlan.executionQueue.async {
			DispatchQueue.global().asyncAfter(deadline: DispatchTime(secondsFromNow: 4)) {
				flag.value = true
			}
			let plan = CardPlanCalculator.PlanCalculator.calculatePlan(recipeList: recipes, crystals: crystals, cancellationFlag: flag)
			if flag.value {
				Renge.logger.log("Canceled Card Plan calculation for taking too long, crystals: \(crystals)", type: "RengeCardPlan")
				output("The calculation took too long and was stopped.  Try again with less recipes or less crystals")
				return
			}
			let leftoverCrystalsString: String
			if plan.leftovers.total > 0 {
				let crystals = CardPlanCalculator.Crystal.allCrystals.map({ ($0, count: plan.leftovers[$0]) }).filter({ $0.count > 0 })
				leftoverCrystalsString = crystals.map({ "\($0.count) \($0.0)" }).joined(separator: ", ")
			}
			else {
				leftoverCrystalsString = "no crystals"
			}

			let endingString = "\nAfterwards, you will have \(leftoverCrystalsString) left.\n\(plan.trials) recipes were checked to make this list."
			let out = Util.makeListingMessage(items: plan.recipes.map({ $0.description }), delimeter: "\n", prefix: "**Craft these cards:\n**", postfix: endingString)
			output(out)
		}
	}
}
