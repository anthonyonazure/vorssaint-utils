// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How the quick tools get found. A tool answers only when its first word is
/// typed, so nothing on screen would ever say it exists. Typing `?` lists one
/// example per tool, and typing a tool's word on its own offers the example
/// for that tool. Choosing one puts it in the field, ready to edit.
///
/// The examples are the tools' own words and carry no text of their own, so
/// every language reads the same list.
extension CommandBarTools {
    struct Example: Equatable {
        let id: String
        /// Every first word that names this tool.
        let keywords: [String]
        /// What goes in the field when it is chosen.
        let text: String
        let symbol: String
    }

    static let examples: [Example] = [
        Example(id: "dice", keywords: ["dice", "roll"], text: "roll 2d6+3", symbol: "dice"),
        Example(id: "uuid", keywords: ["uuid", "guid"], text: "uuid", symbol: "number.square"),
        Example(id: "random", keywords: ["random", "rand"], text: "random 1-100", symbol: "die.face.5"),
        Example(id: "password", keywords: ["password", "pass", "pw"], text: "password 20", symbol: "key"),
        Example(id: "lorem", keywords: ["lorem"], text: "lorem 3", symbol: "text.alignleft"),
        Example(id: "bases", keywords: Array(baseKeywords).sorted(), text: "hex ff", symbol: "number"),
        Example(id: "hash", keywords: Array(hashKeywords).sorted(), text: "sha256 hello", symbol: "number.circle"),
        Example(id: "base64", keywords: ["base64", "b64", "unbase64", "b64d", "base64d"],
                text: "base64 hello", symbol: "arrow.right.square"),
        Example(id: "url", keywords: ["url", "urlencode", "urldecode"], text: "url a b&c", symbol: "link"),
        Example(id: "html", keywords: ["html"], text: "html <b>", symbol: "chevron.left.forwardslash.chevron.right"),
        Example(id: "json", keywords: ["json"], text: "json {\"a\":1}", symbol: "curlybraces"),
        Example(id: "case", keywords: Array(caseKeywords).sorted(), text: "snake hello world", symbol: "textformat"),
        Example(id: "time", keywords: ["time", "tz"], text: "time 3pm new york to tokyo", symbol: "clock"),
        Example(id: "define", keywords: ["define", "def", "meaning"], text: "define serendipity",
                symbol: "character.book.closed"),
        Example(id: "qr", keywords: ["qr", "qrcode"], text: "qr https://example.com", symbol: "qrcode"),
    ]

    /// Examples to offer for what was typed: all of them for `?`, or the one
    /// whose word was typed without anything that made it answer.
    static func hints(for query: String, context: Context = Context()) -> [Example] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "?" { return examples }
        let (word, _) = split(trimmed)
        let key = word.lowercased()
        guard !key.isEmpty, trimmed.count <= 80,
              let example = examples.first(where: { $0.keywords.contains(key) }),
              answers(for: trimmed, context: context).isEmpty,
              definitionWord(for: trimmed) == nil else { return [] }
        return [example]
    }
}
