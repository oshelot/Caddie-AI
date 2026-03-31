//
//  InputGuard.swift
//  CaddieAI
//
//  Client-side input guardrails: length limits and golf-relevance checks.
//

import Foundation

enum InputGuard {
    // MARK: - Limits

    static let maxCharacters = 1_000
    static let maxWords = 200

    // MARK: - Length Enforcement

    /// Trims text to stay within the character limit. Use as an onChange handler.
    static func enforceLimit(_ text: inout String) {
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
        }
    }

    /// Returns `true` when the text is within both word and character limits.
    static func isWithinLimits(_ text: String) -> Bool {
        text.count <= maxCharacters && wordCount(text) <= maxWords
    }

    /// Human-readable limit description for UI hints.
    static func remainingDescription(_ text: String) -> String? {
        let chars = text.count
        guard chars > 0 else { return nil }
        let remaining = maxCharacters - chars
        if remaining <= 100 {
            return "\(remaining) characters remaining"
        }
        return nil
    }

    // MARK: - Golf Relevance

    /// Returns `true` when the text appears golf-related.
    /// Short inputs (≤ 20 words) are assumed relevant (e.g. "What club?").
    /// Longer inputs must contain at least one golf keyword.
    static func isGolfRelated(_ text: String) -> Bool {
        let words = lowercasedWords(text)
        guard words.count > 20 else { return true }
        let keywords = PromptService.shared.golfKeywords
        return words.contains(where: { keywords.contains($0) })
    }

    // MARK: - Helpers

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private static func lowercasedWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline || $0.isPunctuation })
            .map(String.init)
    }
}
