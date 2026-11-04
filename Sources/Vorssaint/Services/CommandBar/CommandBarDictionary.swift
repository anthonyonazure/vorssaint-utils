// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreServices
import Foundation

/// Looks a word up in the Dictionary app's own dictionaries, on this Mac, off
/// the main thread, so typing never waits on the first load of a dictionary.
/// Debounced like a saved script, and cached by the exact word.
final class CommandBarDictionary {
    enum Lookup: Equatable {
        case found(String)
        case missing
        /// Not asked yet, or still being looked up.
        case unknown
    }

    static let debounce: TimeInterval = 0.2

    /// Called on the main thread when an answer lands.
    var onResult: (() -> Void)?

    private var found: [String: String] = [:]
    private var missing: Set<String> = []
    private var inFlight: Set<String> = []
    private var pendingWorkItem: DispatchWorkItem?
    private var generation = 0
    private let queue = DispatchQueue(label: "com.vorssaint.commandbar.dictionary", qos: .userInitiated)

    var isAwaiting: Bool { pendingWorkItem != nil || !inFlight.isEmpty }

    func lookup(_ word: String) -> Lookup {
        let key = word.lowercased()
        if let text = found[key] { return .found(text) }
        return missing.contains(key) ? .missing : .unknown
    }

    /// A word never changes meaning between openings, so the answers stay;
    /// only work that is still waiting is dropped.
    func reset() {
        generation &+= 1
        cancelPending()
        inFlight.removeAll()
    }

    func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    func schedule(_ word: String) {
        let key = word.lowercased()
        guard lookup(key) == .unknown, !inFlight.contains(key) else { return }
        cancelPending()
        let opening = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == opening else { return }
            self.pendingWorkItem = nil
            self.inFlight.insert(key)
            let queue = self.queue
            queue.async { [weak self] in
                let text = CommandBarDictionary.definition(of: key)
                DispatchQueue.main.async {
                    guard let self, self.generation == opening else { return }
                    self.inFlight.remove(key)
                    if let text { self.found[key] = text } else { self.missing.insert(key) }
                    self.onResult?()
                }
            }
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }

    private static func definition(of word: String) -> String? {
        let range = CFRangeMake(0, (word as NSString).length)
        guard let text = DCSCopyTextDefinition(nil, word as CFString, range) else { return nil }
        let value = (text.takeRetainedValue() as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
