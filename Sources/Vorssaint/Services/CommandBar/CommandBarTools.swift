// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// One line a quick tool offers: what it worked out and what that is.
///
/// The labels are the names of the things themselves (SHA-256, UUID, a dice
/// notation), so no row needs words of its own and every language reads the
/// same line.
struct CommandBarToolAnswer: Equatable {
    enum Action: Equatable {
        /// Return copies the value.
        case copy
        /// Return copies the value and asks everything that watches the
        /// clipboard to forget it: a generated password is a secret.
        case copySecret
        /// Return copies a QR code image that carries the value.
        case copyQRCode
    }

    let id: String
    /// What the row shows: the value on one line, shortened.
    let title: String
    /// What Return puts on the clipboard.
    let value: String
    let detail: String
    let symbol: String
    var action: Action = .copy
}

/// Quick lookups answered from what was typed: dice, random data, number
/// bases, hashes, encodings, case changes, time zones. Pure, so the rules are
/// pinned by tests and the catalog only has to turn the lines into rows.
///
/// A tool answers only when the first word names it and the rest reads as its
/// input, so ordinary searching never turns into an answer by accident.
enum CommandBarTools {
    struct Context {
        var now = Date()
        var locale = Locale.current
        var localTimeZone = TimeZone.current
        /// A whole number from 0 up to, not including, the bound. The default
        /// draws from the system generator, which is safe for passwords.
        var roll: (Int) -> Int = { Int.random(in: 0..<$0) }
    }

    /// Nothing longer than this is treated as input for a tool.
    static let maxQueryLength = 4_000

    static func answers(for query: String, context: Context = Context()) -> [CommandBarToolAnswer] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxQueryLength else { return [] }
        let (word, rest) = split(trimmed)
        switch word.lowercased() {
        case "dice", "roll": return dice(rest, context)
        case "uuid", "guid": return rest.isEmpty ? uuids() : []
        case "random", "rand": return randomNumber(rest, context)
        case "password", "pass", "pw": return passwords(rest, context)
        case "lorem": return lorem(rest, context)
        case let key where baseKeywords.contains(key): return bases(key, rest)
        case let key where hashKeywords.contains(key): return hashes(key, rest)
        case let key where encodingKeywords.contains(key): return encodings(key, rest)
        case "json": return jsonAnswers(rest)
        case let key where caseKeywords.contains(key): return caseAnswers(key, rest)
        case "time", "tz": return time(rest, context)
        case "qr", "qrcode": return qr(rest)
        default: break
        }
        if let bare = bareDice(trimmed, context) { return bare }
        return zoneConversion(trimmed, context)
    }

    // MARK: - Shared helpers

    static func split(_ text: String) -> (word: String, rest: String) {
        guard let index = text.firstIndex(where: \.isWhitespace) else { return (text, "") }
        return (String(text[..<index]),
                String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A value on one line, shortened, for the row title.
    static func oneLine(_ value: String, limit: Int = 140) -> String {
        let flat = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    static func answer(_ id: String, _ value: String, _ detail: String, _ symbol: String,
                       action: CommandBarToolAnswer.Action = .copy) -> CommandBarToolAnswer {
        CommandBarToolAnswer(id: id, title: oneLine(value), value: value,
                             detail: detail, symbol: symbol, action: action)
    }

    // MARK: - Dice

    struct DiceTerm: Equatable {
        /// +1 or -1.
        let sign: Int
        /// How many dice, or the value itself for a constant.
        let count: Int
        /// Nil for a constant.
        let sides: Int?
    }

    static let maxDiceCount = 100
    static let maxDiceSides = 1_000
    static let maxDiceConstant = 100_000

    /// "2d6+3", "d20", "4d8 - 1d4 + 2". Nil for anything else.
    static func parseDice(_ text: String) -> [DiceTerm]? {
        let chars = Array(text.lowercased().filter { !$0.isWhitespace })
        guard !chars.isEmpty, chars.count <= 80 else { return nil }
        var segments: [(sign: Int, body: String)] = []
        var sign = 1
        var body = ""
        for character in chars {
            if character == "+" || character == "-" {
                if !body.isEmpty {
                    segments.append((sign, body))
                    body = ""
                } else if !segments.isEmpty {
                    return nil // two operators in a row
                }
                sign = character == "-" ? -1 : 1
            } else {
                body.append(character)
            }
        }
        guard !body.isEmpty else { return nil }
        segments.append((sign, body))
        guard segments.count <= 20 else { return nil }

        var terms: [DiceTerm] = []
        for segment in segments {
            if segment.body.contains("d") {
                let parts = segment.body.split(separator: "d", maxSplits: 1,
                                               omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 2,
                      parts[0].isEmpty || parts[0].allSatisfy(\.isASCII),
                      let sides = Int(parts[1]), (2...maxDiceSides).contains(sides)
                else { return nil }
                let count = parts[0].isEmpty ? 1 : (Int(parts[0]) ?? 0)
                guard (1...maxDiceCount).contains(count) else { return nil }
                terms.append(DiceTerm(sign: segment.sign, count: count, sides: sides))
            } else {
                guard segment.body.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let value = Int(segment.body), value <= maxDiceConstant else { return nil }
                terms.append(DiceTerm(sign: segment.sign, count: value, sides: nil))
            }
        }
        return terms.contains(where: { $0.sides != nil }) ? terms : nil
    }

    private static func dice(_ expression: String, _ context: Context) -> [CommandBarToolAnswer] {
        guard let terms = parseDice(expression.isEmpty ? "d20" : expression) else { return [] }
        return [rollDice(terms, context)]
    }

    /// "2d6" and "d20" typed alone cannot be anything else.
    private static func bareDice(_ text: String, _ context: Context) -> [CommandBarToolAnswer]? {
        let lowered = text.lowercased()
        guard lowered.contains("d"),
              let first = lowered.first, first.isNumber || first == "d",
              let terms = parseDice(lowered) else { return nil }
        return [rollDice(terms, context)]
    }

    static func rollDice(_ terms: [DiceTerm], _ context: Context) -> CommandBarToolAnswer {
        var total = 0
        var canonical = ""
        var breakdown = ""
        for (index, term) in terms.enumerated() {
            let part: String
            let shown: String
            if let sides = term.sides {
                let rolls = (0..<term.count).map { _ in context.roll(sides) + 1 }
                total += term.sign * rolls.reduce(0, +)
                part = (term.count == 1 ? "d\(sides)" : "\(term.count)d\(sides)")
                shown = rolls.count == 1 || terms.count == 1
                    ? rolls.map(String.init).joined(separator: " + ")
                    : "(" + rolls.map(String.init).joined(separator: " + ") + ")"
            } else {
                total += term.sign * term.count
                part = "\(term.count)"
                shown = "\(term.count)"
            }
            if index == 0 {
                canonical += (term.sign < 0 ? "-" : "") + part
                breakdown += (term.sign < 0 ? "-" : "") + shown
            } else {
                canonical += (term.sign < 0 ? "-" : "+") + part
                breakdown += (term.sign < 0 ? " - " : " + ") + shown
            }
        }
        let single = terms.count == 1 && terms[0].count == 1
        let detail = single ? canonical : canonical + " · " + breakdown
        return answer("dice", String(total), detail, "dice")
    }

    // MARK: - Random data

    private static func uuids() -> [CommandBarToolAnswer] {
        let value = UUID().uuidString
        return [answer("uuid.lower", value.lowercased(), "UUID", "number.square"),
                answer("uuid.upper", value, "UUID", "number.square")]
    }

    static let maxRandomMagnitude = 1_000_000_000_000

    /// "random", "random 50", "random 10-20", "random 5..9".
    static func parseRange(_ text: String) -> (low: Int, high: Int)? {
        func value(_ piece: Substring) -> Int? {
            // magnitude, not abs: abs(Int.min) traps.
            guard let number = Int(piece.trimmingCharacters(in: .whitespaces)),
                  number.magnitude <= UInt(maxRandomMagnitude) else { return nil }
            return number
        }
        if text.isEmpty { return (1, 100) }
        if let single = Int(text) {
            return single >= 1 && single <= maxRandomMagnitude ? (1, single) : nil
        }
        for separator in ["...", "..", " to ", ","] {
            if let range = text.range(of: separator),
               let low = value(text[..<range.lowerBound]),
               let high = value(text[range.upperBound...]), low <= high { return (low, high) }
        }
        if let index = text.dropFirst().firstIndex(of: "-"),
           let low = value(text[..<index]),
           let high = value(text[text.index(after: index)...]), low <= high { return (low, high) }
        return nil
    }

    private static func randomNumber(_ rest: String, _ context: Context) -> [CommandBarToolAnswer] {
        guard let bounds = parseRange(rest) else { return [] }
        let span = bounds.high - bounds.low + 1
        let value = bounds.low + context.roll(span)
        return [answer("random", String(value), "\(bounds.low)…\(bounds.high)", "die.face.5")]
    }

    private static let lowerLetters = Array("abcdefghijklmnopqrstuvwxyz")
    private static let upperLetters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digitCharacters = Array("0123456789")
    private static let symbolCharacters = Array("!@#$%^&*()-_=+[]{};:,.?")

    static let passwordLengths = 8...128

    /// At least one of every kind of character, then a shuffle, so no
    /// password starts with the same pattern.
    static func generatePassword(length: Int, symbols: Bool, roll: (Int) -> Int) -> String {
        var classes = [lowerLetters, upperLetters, digitCharacters]
        if symbols { classes.append(symbolCharacters) }
        let all = classes.flatMap { $0 }
        var characters = classes.map { $0[roll($0.count)] }
        while characters.count < length { characters.append(all[roll(all.count)]) }
        var index = characters.count - 1
        while index > 0 {
            characters.swapAt(index, roll(index + 1))
            index -= 1
        }
        return String(characters)
    }

    private static func passwords(_ rest: String, _ context: Context) -> [CommandBarToolAnswer] {
        let length = rest.isEmpty ? 16 : (Int(rest) ?? 0)
        guard passwordLengths.contains(length) else { return [] }
        return [
            answer("password.symbols",
                   generatePassword(length: length, symbols: true, roll: context.roll),
                   "Aa1! · \(length)", "key", action: .copySecret),
            answer("password.plain",
                   generatePassword(length: length, symbols: false, roll: context.roll),
                   "Aa1 · \(length)", "key", action: .copySecret),
        ]
    }

    // MARK: - Lorem ipsum

    private static let loremWords = (
        "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor "
        + "incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud "
        + "exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure "
        + "in reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint "
        + "occaecat cupidatat non proident sunt culpa qui officia deserunt mollit anim id est "
        + "laborum"
    ).split(separator: " ").map(String.init)

    private static let loremOpening = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

    private static func loremSentence(_ context: Context) -> String {
        let count = 8 + context.roll(9)
        var words = (0..<count).map { _ in loremWords[context.roll(loremWords.count)] }
        words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        return words.joined(separator: " ") + "."
    }

    /// "lorem" (one paragraph), "lorem 3" (three paragraphs), "lorem 40 words".
    static func lorem(_ rest: String, _ context: Context) -> [CommandBarToolAnswer] {
        let parts = rest.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        var number = 1
        var words = false
        switch parts.count {
        case 0: break
        case 1:
            guard let count = Int(parts[0]) else { return [] }
            number = count
        case 2:
            guard let count = Int(parts[0]), ["words", "word"].contains(parts[1]) else { return [] }
            number = count
            words = true
        default: return []
        }
        if words {
            guard (1...500).contains(number) else { return [] }
            var text: [String] = []
            while text.count < number {
                text.append(text.count < loremWords.count && text.count < 8
                    ? loremWords[text.count] : loremWords[context.roll(loremWords.count)])
            }
            var joined = text.joined(separator: " ")
            joined = joined.prefix(1).uppercased() + joined.dropFirst() + "."
            return [answer("lorem", joined, "Lorem ipsum · \(number)", "text.alignleft")]
        }
        guard (1...10).contains(number) else { return [] }
        var paragraphs: [String] = []
        for index in 0..<number {
            var sentences = index == 0 ? [loremOpening] : []
            while sentences.count < 5 { sentences.append(loremSentence(context)) }
            paragraphs.append(sentences.joined(separator: " "))
        }
        return [answer("lorem", paragraphs.joined(separator: "\n\n"),
                       "Lorem ipsum · ¶ \(number)", "text.alignleft")]
    }

    // MARK: - Number bases

    static let baseKeywords: Set<String> = ["hex", "bin", "binary", "oct", "octal", "dec", "decimal"]

    /// "hex ff", "bin 1010", "dec 255", "oct 17", or any of them with a
    /// 0x, 0b or 0o prefix. The keyword says which base the input is in.
    static func bases(_ key: String, _ rest: String) -> [CommandBarToolAnswer] {
        let radix: Int
        switch key {
        case "hex": radix = 16
        case "bin", "binary": radix = 2
        case "oct", "octal": radix = 8
        default: radix = 10
        }
        guard let value = parseInteger(rest, defaultRadix: radix) else { return [] }
        return [
            answer("base.dec", String(value), "DEC", "number"),
            answer("base.hex", "0x" + String(value, radix: 16, uppercase: true), "HEX", "number"),
            answer("base.bin", "0b" + String(value, radix: 2), "BIN", "number"),
            answer("base.oct", "0o" + String(value, radix: 8), "OCT", "number"),
        ]
    }

    static func parseInteger(_ text: String, defaultRadix: Int) -> UInt64? {
        var digits = text.lowercased().filter { $0 != "_" && !$0.isWhitespace }
        guard !digits.isEmpty else { return nil }
        var radix = defaultRadix
        // One prefix at most: after "0x" the "0b1" of "0x0b1" is digits.
        for (prefix, base) in [("0x", 16), ("0b", 2), ("0o", 8)] where digits.hasPrefix(prefix) {
            digits.removeFirst(2)
            radix = base
            break
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return UInt64(digits, radix: radix)
    }

    // MARK: - Hashes

    static let hashKeywords: Set<String> = ["sha1", "sha256", "sha512", "md5", "hash"]

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hashes(_ key: String, _ rest: String) -> [CommandBarToolAnswer] {
        guard !rest.isEmpty else { return [] }
        let data = Data(rest.utf8)
        var rows: [CommandBarToolAnswer] = []
        func add(_ id: String, _ label: String, _ value: String) {
            rows.append(answer("hash.\(id)", value, label, "number.circle"))
        }
        if key == "sha256" || key == "hash" { add("sha256", "SHA-256", hex(SHA256.hash(data: data))) }
        if key == "sha512" || key == "hash" { add("sha512", "SHA-512", hex(SHA512.hash(data: data))) }
        if key == "sha1" || key == "hash" { add("sha1", "SHA-1", hex(Insecure.SHA1.hash(data: data))) }
        if key == "md5" || key == "hash" { add("md5", "MD5", hex(Insecure.MD5.hash(data: data))) }
        return rows
    }
}
