package com.caddieai.android.data.llm

/**
 * Client-side guardrails for all free-text LLM inputs.
 * Mirrors iOS InputGuard.swift — enforces character limits and golf-relevance checks.
 */
object InputGuard {
    const val MAX_CHARS = 1000
    private const val RELEVANCE_WORD_THRESHOLD = 20

    /** Truncates [input] to [MAX_CHARS] characters. */
    fun enforceLimit(input: String): String =
        if (input.length <= MAX_CHARS) input else input.take(MAX_CHARS)

    /** Returns true if [input] is within the [MAX_CHARS] limit. */
    fun isWithinLimits(input: String): Boolean = input.length <= MAX_CHARS

    /**
     * Returns true if [input] is golf-related or short enough to pass through.
     *
     * Inputs of 20 words or fewer always pass (avoids false positives on short queries).
     * Longer inputs must contain at least one keyword from [keywords].
     */
    fun isGolfRelated(input: String, keywords: List<String>): Boolean {
        val words = input.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size <= RELEVANCE_WORD_THRESHOLD) return true
        val lowerInput = input.lowercase()
        return keywords.any { keyword -> lowerInput.contains(keyword.lowercase()) }
    }
}
