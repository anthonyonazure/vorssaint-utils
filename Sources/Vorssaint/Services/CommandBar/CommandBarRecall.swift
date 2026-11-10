// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The commands the person ran lately, for the empty bar. Off by default.
///
/// It keeps which command was run, never the words typed to find it, and only
/// the kinds of command that have a lasting identity: a window, a menu item
/// or a clipboard entry is a different thing tomorrow.
enum CommandBarRecents {
    /// Stored this many, so a few can be skipped (pinned, uninstalled) and the
    /// list the bar shows is still full.
    static let storedLimit = 10
    static let shownLimit = 5

    /// Answers carry no prefix of their own, so they are named here.
    private static let answerPrefixes = ["math.", "units.", "color.", "date."]

    static func mayRemember(rowID: String) -> Bool {
        guard !answerPrefixes.contains(where: rowID.hasPrefix) else { return false }
        switch CommandBarPreferences.source(ofRowID: rowID) {
        case .actions, .apps, .settingsPages, .macSettings, .snippets, .folders, .links:
            return true
        case .menus, .windows, .quitApps, .uninstallApps, .clipboard, .emoji, .answers, .calculator,
             .tools, .selection, .files, .killProcess:
            return false
        }
    }

    static func decode(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encode(_ keys: [String]) -> String {
        keys.joined(separator: "\n")
    }

    /// The newest first, each key once.
    static func recording(_ key: String, in keys: [String]) -> [String] {
        guard !key.isEmpty, !key.contains("\n") else { return keys }
        return Array(([key] + keys.filter { $0 != key }).prefix(storedLimit))
    }

    /// What the empty bar shows: the remembered keys that still exist, minus
    /// what is already shown above them.
    static func visible(_ keys: [String], available: Set<String>, excluding: Set<String>) -> [String] {
        Array(keys.filter { available.contains($0) && !excluding.contains($0) }.prefix(shownLimit))
    }
}

/// The searches the person typed lately, for ⌥↑ and ⌥↓ in the field. Off by
/// default, kept on this Mac, never exported with the settings.
enum CommandBarSearchHistory {
    static let storedLimit = 20
    static let shortest = 2
    static let longest = 120

    /// First words of the tools whose input is text that may be a secret, a
    /// password to hash, a token to decode. A search that starts with one is
    /// never kept.
    static var unrecordedWords: Set<String> {
        var words: Set<String> = ["password", "pass", "pw", "json", "qr", "qrcode"]
        words.formUnion(CommandBarTools.hashKeywords)
        words.formUnion(CommandBarTools.encodingKeywords)
        words.formUnion(CommandBarTools.caseKeywords)
        return words
    }

    static func mayRemember(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (shortest...longest).contains(trimmed.count), trimmed != "?",
              !trimmed.contains(where: \.isNewline) else { return false }
        let word = CommandBarTools.split(trimmed).word.lowercased()
        return !unrecordedWords.contains(word)
    }

    static func decode(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func encode(_ queries: [String]) -> String {
        queries.joined(separator: "\n")
    }

    /// The newest first, each search once whatever its case.
    static func recording(_ query: String, in queries: [String]) -> [String] {
        guard mayRemember(query) else { return queries }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        return Array(([trimmed] + queries.filter { $0.lowercased() != key }).prefix(storedLimit))
    }

    enum Direction { case older, newer }

    /// Where ⌥↑ or ⌥↓ lands. Nil is what the person had typed before they
    /// started going back, so stepping forward from the newest returns to it.
    static func step(from cursor: Int?, _ direction: Direction, count: Int) -> Int? {
        guard count > 0 else { return nil }
        switch direction {
        case .older:
            guard let cursor else { return 0 }
            return min(cursor + 1, count - 1)
        case .newer:
            guard let cursor, cursor > 0 else { return nil }
            return cursor - 1
        }
    }
}
