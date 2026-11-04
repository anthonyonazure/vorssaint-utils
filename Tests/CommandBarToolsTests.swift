// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The command bar's quick tools: what each one answers, what it refuses, and
/// that ordinary searching never turns into an answer by accident.
enum CommandBarToolsTests {
    /// A repeatable stand-in for chance, so a failure can be reproduced.
    private final class Pseudo {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private static func context(roll: @escaping (Int) -> Int = { _ in 0 },
                                zone: String = "America/Phoenix") -> CommandBarTools.Context {
        var context = CommandBarTools.Context()
        // 2026-01-15 12:00 UTC: winter, so New York is UTC-5 and Phoenix UTC-7.
        context.now = Date(timeIntervalSince1970: 1_768_478_400)
        context.locale = Locale(identifier: "en_US")
        context.localTimeZone = TimeZone(identifier: zone)!
        context.roll = roll
        return context
    }

    private static func values(_ query: String,
                               _ context: CommandBarTools.Context = context()) -> [String] {
        CommandBarTools.answers(for: query, context: context).map(\.value)
    }

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func run(_ suite: TestSuite) {
        routing(suite)
        dice(suite)
        randomData(suite)
        lorem(suite)
        bases(suite)
        hashes(suite)
        encodings(suite)
        json(suite)
        cases(suite)
        zones(suite)
    }

    // MARK: - Routing

    private static func routing(_ suite: TestSuite) {
        for query in ["", "   ", "volume up", "safari", "time", "uuid foo", "password manager",
                      "hash", "json", "hex", "lorem ipsum dolor", "roll the dice", "upper", "qr"] {
            suite.expect(values(query).isEmpty, "ordinary or incomplete text \"\(query)\" answers nothing")
        }
        suite.expect(values(String(repeating: "a", count: 4_001)).isEmpty
                     && values("sha256 " + String(repeating: "a", count: 4_001)).isEmpty,
                     "text over the length limit is never treated as tool input")
    }

    // MARK: - Dice

    private static func dice(_ suite: TestSuite) {
        suite.expect(CommandBarTools.parseDice("2d6+3") == [
            .init(sign: 1, count: 2, sides: 6), .init(sign: 1, count: 3, sides: nil)],
            "2d6+3 reads as two dice and a constant")
        suite.expect(CommandBarTools.parseDice("D20") == [.init(sign: 1, count: 1, sides: 20)],
                     "d20 is one die, in any case")
        suite.expect(CommandBarTools.parseDice("4d8 - 1d4 + 2") == [
            .init(sign: 1, count: 4, sides: 8), .init(sign: -1, count: 1, sides: 4),
            .init(sign: 1, count: 2, sides: nil)],
            "spaces and subtraction are read")
        for bad in ["2d", "d1", "0d6", "101d6", "2d1001", "5", "2d6++3", "abc", "1d6 mac", "d", "+", ""] {
            suite.expect(CommandBarTools.parseDice(bad) == nil, "\"\(bad)\" is not dice notation")
        }

        let low = context(roll: { _ in 0 })
        let high = context(roll: { $0 - 1 })
        suite.expect(values("roll 3d6", low) == ["3"] && values("roll 3d6", high) == ["18"],
                     "the lowest and highest rolls of 3d6 are 3 and 18")
        suite.expect(values("dice 2d6+3", high) == ["15"] && values("dice 2d6-1", low) == ["1"],
                     "constants add and subtract")
        suite.expect(values("roll", high) == ["20"], "a bare roll is a d20")
        suite.expect(values("2d6", high) == ["12"] && values("d8", high) == ["8"],
                     "a notation typed alone rolls")
        suite.expect(values("3d6 mac", high).isEmpty && values("dice 2d6 foo", high).isEmpty,
                     "dice with extra words answer nothing")
        let detail = CommandBarTools.answers(for: "2d6+1d4", context: high).first?.detail ?? ""
        suite.expect(detail == "2d6+d4 · (6 + 6) + 4", "the detail shows each roll: \(detail)")
        let sequence = Pseudo()
        let live = context(roll: { sequence.next($0) })
        let totals = (0..<200).compactMap { _ in Int(values("d6", live).first ?? "") }
        suite.expect(totals.count == 200 && totals.allSatisfy { (1...6).contains($0) }
                     && Set(totals).count == 6, "a d6 stays in 1 to 6 and reaches every face")
    }

    // MARK: - Random data

    private static func randomData(_ suite: TestSuite) {
        let rows = CommandBarTools.answers(for: "uuid")
        suite.expect(rows.count == 2 && rows[0].value == rows[1].value.lowercased()
                     && UUID(uuidString: rows[0].value) != nil && rows[0].value != rows[1].value,
                     "uuid offers a lower and an upper case form of one identifier")

        suite.expect(CommandBarTools.parseRange("")! == (1, 100) && CommandBarTools.parseRange("50")! == (1, 50)
                     && CommandBarTools.parseRange("10-20")! == (10, 20)
                     && CommandBarTools.parseRange("5..9")! == (5, 9)
                     && CommandBarTools.parseRange("3 to 8")! == (3, 8)
                     && CommandBarTools.parseRange("-5-5")! == (-5, 5),
                     "ranges are read in every spelling, negatives included")
        for bad in ["20-10", "abc", "0", "-3", "1..", "9999999999999999"] {
            suite.expect(CommandBarTools.parseRange(bad) == nil, "\"\(bad)\" is not a range")
        }
        suite.expect(values("random 10-20", context(roll: { _ in 0 })) == ["10"]
                     && values("random 10-20", context(roll: { $0 - 1 })) == ["20"],
                     "random stays inside its bounds")

        let chance = Pseudo()
        let rolled = context(roll: { chance.next($0) })
        let passwords = CommandBarTools.answers(for: "pw", context: rolled)
        suite.expect(passwords.count == 2 && passwords.allSatisfy { $0.action == .copySecret },
                     "passwords are copied as secrets")
        let symbols = passwords[0].value
        let plain = passwords[1].value
        suite.expect(symbols.count == 16 && plain.count == 16, "the default length is 16")
        suite.expect(symbols.contains(where: \.isLowercase) && symbols.contains(where: \.isUppercase)
                     && symbols.contains(where: \.isNumber)
                     && symbols.contains(where: { "!@#$%^&*()-_=+[]{};:,.?".contains($0) }),
                     "a password with symbols has every kind of character")
        suite.expect(plain.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                     && plain.contains(where: \.isNumber),
                     "the plain password is letters and digits only")
        suite.expect(CommandBarTools.answers(for: "password 40", context: rolled).first?.value.count == 40,
                     "a length can be asked for")
        for bad in ["pw 7", "pw 129", "pw x", "password 0"] {
            suite.expect(values(bad).isEmpty, "\"\(bad)\" generates nothing")
        }
        let system = (0..<20).map { _ in CommandBarTools.answers(for: "pw")[0].value }
        suite.expect(Set(system).count == 20, "the real generator never repeats a password")
    }

    // MARK: - Lorem ipsum

    private static func lorem(_ suite: TestSuite) {
        let chance = Pseudo()
        let roll = context(roll: { chance.next($0) })
        let one = values("lorem", roll).first ?? ""
        suite.expect(one.hasPrefix("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
                     && !one.contains("\n\n"), "one paragraph starts the classic way")
        suite.expect((values("lorem 3", roll).first ?? "").components(separatedBy: "\n\n").count == 3,
                     "three paragraphs are separated by blank lines")
        let words = values("lorem 40 words", roll).first ?? ""
        suite.expect(words.split(separator: " ").count == 40 && words.hasSuffix("."),
                     "a word count is exact and ends with a full stop")
        suite.expect(values("lorem 2 word", roll).first?.split(separator: " ").count == 2, "singular word works")
        for bad in ["lorem 0", "lorem 11", "lorem x", "lorem 3 pages", "lorem 501 words", "lorem 1 2 3"] {
            suite.expect(values(bad, roll).isEmpty, "\"\(bad)\" gives no text")
        }
    }

    // MARK: - Number bases

    private static func bases(_ suite: TestSuite) {
        suite.expect(values("hex ff") == ["255", "0xFF", "0b11111111", "0o377"],
                     "hex ff in every base")
        suite.expect(values("bin 1010").first == "10" && values("oct 17").first == "15"
                     && values("dec 255").dropFirst().first == "0xFF",
                     "the keyword names the base of the input")
        suite.expect(values("dec 0xff").first == "255" && values("hex 0b101").first == "5",
                     "a prefix overrides the keyword")
        suite.expect(values("hex 1_000").first == "4096", "underscores are ignored")
        suite.expect(values("dec 18446744073709551615").first == "18446744073709551615"
                     && values("dec 18446744073709551616").isEmpty,
                     "the largest 64 bit value works and one more is refused")
        for bad in ["hex zz", "bin 102", "oct 8", "dec -5", "hex 0x"] {
            suite.expect(values(bad).isEmpty, "\"\(bad)\" is not a number in that base")
        }
    }

    // MARK: - Hashes

    private static func hashes(_ suite: TestSuite) {
        suite.expect(values("sha256 abc") == ["ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"],
                     "SHA-256 of abc")
        suite.expect(values("md5 abc") == ["900150983cd24fb0d6963f7d28e17f72"], "MD5 of abc")
        suite.expect(values("sha1 abc") == ["a9993e364706816aba3e25717850c26c9cd0d89d"], "SHA-1 of abc")
        suite.expect(values("sha512 abc").first?.hasPrefix("ddaf35a193617aba") == true, "SHA-512 of abc")
        suite.expect(values("hash abc").count == 4, "hash shows all four")
        suite.expect(values("sha256 a b").first != values("sha256 ab").first,
                     "inner spaces are part of what is hashed")
    }

    // MARK: - Encodings

    private static func encodings(_ suite: TestSuite) {
        suite.expect(values("base64 hello") == ["aGVsbG8="], "a word that is not Base64 only encodes")
        suite.expect(values("base64 aGVsbG8=") == ["YUdWc2JHOD0=", "hello"],
                     "valid Base64 also offers the decoded text")
        suite.expect(values("unbase64 aGk") == ["hi"], "missing padding is tolerated")
        suite.expect(values("b64d aGVsbG8") == ["hello"], "the unpadded form decodes too")
        suite.expect(values("unbase64 !!!").isEmpty && values("unbase64 test").isEmpty,
                     "garbage and non-text bytes are never an answer")
        suite.expect(values("unbase64 AAEC").isEmpty, "bytes with control characters are refused")
        suite.expect(values("url a b&c") == ["a%20b%26c"], "URL encoding is strict")
        suite.expect(values("url a%20b") == ["a%2520b", "a b"], "a percent sequence also offers the decoded text")
        suite.expect(values("urlencode ü") == ["%C3%BC"] && values("urldecode %C3%BC") == ["ü"],
                     "non ASCII letters are percent encoded as UTF-8")
        suite.expect(values("urldecode plain").isEmpty, "decoding text with no escapes offers nothing")
        suite.expect(values("html <a href=\"x\">&").first == "&lt;a href=&quot;x&quot;&gt;&amp;",
                     "HTML escaping")
        suite.expect(values("html &lt;b&gt; &#65; &#x42; &amp;").last == "<b> A B &",
                     "HTML entities decode, numeric ones included")
        suite.expect(CommandBarTools.unescapeHTML("&bogus; &") == nil, "an unknown entity is left alone")
        suite.expect(values("html").isEmpty && values("base64").isEmpty, "no input, no answer")
    }

    // MARK: - JSON

    private static func json(_ suite: TestSuite) {
        let input = "{\"a\":1,\"b\":[1,2],\"c\":{}}"
        let rows = CommandBarTools.answers(for: "json " + input)
        suite.expect(rows.count == 2, "tidy and compact forms are offered")
        suite.expect(rows.first?.value == "{\n  \"a\": 1,\n  \"b\": [\n    1,\n    2\n  ],\n  \"c\": {}\n}",
                     "tidy form: \(rows.first?.value ?? "")")
        suite.expect(rows.last?.value == input, "compact form")
        let big = CommandBarTools.answers(for: "json {\"n\": 12345678901234567890, \"f\": 1.50}").first?.value ?? ""
        suite.expect(big.contains("12345678901234567890") && big.contains("1.50"),
                     "numbers come out exactly as typed")
        let tricky = CommandBarTools.answers(for: "json {\"s\":\"a,{b}: [c] \\\" d\"}").first?.value ?? ""
        suite.expect(tricky.contains("\"a,{b}: [c] \\\" d\""), "text inside strings is never touched")
        suite.expect(values("json {a:1}").isEmpty && values("json 5").isEmpty && values("json {\"a\":").isEmpty
                     && values("json hello").isEmpty,
                     "anything that is not a JSON document is refused")
        suite.expect(CommandBarTools.formatJSON("[ ]", pretty: true) == "[]", "empty containers stay closed")
        suite.expect(CommandBarTools.answers(for: "json []").count == 1, "one form when both are the same")
    }

    // MARK: - Case changes

    private static func cases(_ suite: TestSuite) {
        suite.expect(CommandBarTools.words(in: "myHTTPServer_v2-name x") == ["my", "HTTP", "Server", "v2", "name", "x"],
                     "words are found in any naming style")
        suite.expect(values("case helloWorld")
                     == ["hello_world", "helloWorld", "HelloWorld", "hello-world", "HELLO_WORLD", "Hello World"],
                     "case shows every style")
        suite.expect(values("snake Hello World") == ["hello_world"] && values("camel hello big world") == ["helloBigWorld"]
                     && values("pascal hello world") == ["HelloWorld"] && values("kebab Hello World") == ["hello-world"]
                     && values("constant hello world") == ["HELLO_WORLD"]
                     && values("title the quick brown") == ["The Quick Brown"],
                     "each style on its own")
        suite.expect(values("upper abc def") == ["ABC DEF"] && values("lower ABC Def") == ["abc def"],
                     "upper and lower keep spacing")
        suite.expect(values("snake !!!").isEmpty, "no words, no answer")
    }

    // MARK: - Time zones

    private static func zones(_ suite: TestSuite) {
        suite.expect(CommandBarTools.parseClock("3pm")! == (15, 0) && CommandBarTools.parseClock("12am")! == (0, 0)
                     && CommandBarTools.parseClock("12pm")! == (12, 0) && CommandBarTools.parseClock("3:30 pm")! == (15, 30)
                     && CommandBarTools.parseClock("15:45")! == (15, 45) && CommandBarTools.parseClock("noon")! == (12, 0),
                     "clock times are read")
        for bad in ["3", "25:00", "13pm", "0am", "3:60", "pm", "", "3:3:3", "x3pm"] {
            suite.expect(CommandBarTools.parseClock(bad) == nil, "\"\(bad)\" is not a clock time")
        }

        suite.expect(CommandBarTools.resolvePlace("tokyo")?.zone.identifier == "Asia/Tokyo"
                     && CommandBarTools.resolvePlace("New York")?.zone.identifier == "America/New_York"
                     && CommandBarTools.resolvePlace("pst")?.zone.identifier == "America/Los_Angeles"
                     && CommandBarTools.resolvePlace("tok")?.zone.identifier == "Asia/Tokyo"
                     && CommandBarTools.resolvePlace("Europe/London")?.zone.identifier == "Europe/London",
                     "places resolve by city, alias, prefix and identifier")
        suite.expect(CommandBarTools.resolvePlace("EST")?.name == "EST" && CommandBarTools.resolvePlace("xyzzy") == nil
                     && CommandBarTools.resolvePlace("") == nil, "unknown places do not resolve")

        let now = context()
        let tokyoNow = CommandBarTools.answers(for: "time tokyo", context: now).first
        suite.expect(tokyoNow.map { plain($0.value) } == "9:00 PM" && tokyoNow?.detail.hasPrefix("Tokyo") == true
                     && tokyoNow?.detail.contains("d") == false,
                     "the time in Tokyo at 12:00 UTC: \(tokyoNow?.value ?? "") \(tokyoNow?.detail ?? "")")
        let across = CommandBarTools.answers(for: "3pm new york to tokyo", context: now).first
        suite.expect(across.map { plain($0.value) } == "5:00 AM" && across?.detail.hasSuffix("+1d") == true,
                     "3pm in New York is 5 AM tomorrow in Tokyo: \(across?.value ?? "") \(across?.detail ?? "")")
        let behind = CommandBarTools.answers(for: "time 9am tokyo", context: now).first
        suite.expect(behind.map { plain($0.value) } == "5:00 PM" && behind?.detail.hasSuffix("-1d") == true,
                     "9 AM in Tokyo is 5 PM yesterday in Phoenix: \(behind?.value ?? "") \(behind?.detail ?? "")")
        let local = CommandBarTools.answers(for: "time 3pm to tokyo", context: now).first
        suite.expect(local.map { plain($0.value) } == "7:00 AM" && local?.detail.hasSuffix("+1d") == true,
                     "3 PM in Phoenix is 7 AM tomorrow in Tokyo: \(local?.value ?? "") \(local?.detail ?? "")")
        for query in ["tokyo", "3pm tokyo", "3pm to tokyo", "to tokyo", "3pm", "meet at 3pm"] {
            suite.expect(values(query, now).isEmpty, "\"\(query)\" without the keyword answers nothing")
        }
        for query in ["time 3pm atlantis", "time", "time 3pm new york to atlantis", "time to"] {
            suite.expect(values(query, now).isEmpty, "\"\(query)\" has no answer")
        }
        let summer = CommandBarTools.Context(
            now: Date(timeIntervalSince1970: 1_784_635_200), // 2026-07-21 12:00 UTC
            locale: Locale(identifier: "en_US"),
            localTimeZone: TimeZone(identifier: "America/Phoenix")!,
            roll: { _ in 0 })
        let est = CommandBarTools.answers(for: "time 12pm est to utc", context: summer).first
        suite.expect(est.map { plain($0.value) } == "4:00 PM",
                     "est in July follows daylight saving, as people mean it: \(est?.value ?? "")")

        suite.expect(CommandBarTools.definitionWord(for: "define serendipity") == "serendipity"
                     && CommandBarTools.definitionWord(for: "DEF don't") == "don't"
                     && CommandBarTools.definitionWord(for: "meaning well-known") == "well-known",
                     "a single word after define, def or meaning is looked up")
        for bad in ["define", "define a", "define two words", "define 123", "define --", "meaning of life",
                    "definitely", "define " + String(repeating: "a", count: 41)] {
            suite.expect(CommandBarTools.definitionWord(for: bad) == nil, "\"\(bad)\" is not a lookup")
        }
        suite.expect(CommandBarTools.answers(for: "qr hello").first?.action == .copyQRCode
                     && values("qr " + String(repeating: "a", count: 1_001)).isEmpty,
                     "qr asks for an image, within a length limit")
    }
}
