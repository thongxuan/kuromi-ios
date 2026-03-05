import Foundation

/// Returns similarity ratio 0.0–1.0 between two strings (Levenshtein-based)
func similarityRatio(_ a: String, _ b: String) -> Double {
    let a = Array(a), b = Array(b)
    let m = a.count, n = b.count
    guard m > 0 && n > 0 else { return 0 }
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 0...m { dp[i][0] = i }
    for j in 0...n { dp[0][j] = j }
    for i in 1...m {
        for j in 1...n {
            dp[i][j] = a[i-1] == b[j-1]
                ? dp[i-1][j-1]
                : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
        }
    }
    let dist = dp[m][n]
    return 1.0 - Double(dist) / Double(max(m, n))
}

/// Check if `text` contains a word/ngram that fuzzy-matches `phrase` at given threshold
func fuzzyContains(_ text: String, phrase: String, threshold: Double = 0.7) -> Bool {
    let text = text.lowercased()
    let phrase = phrase.lowercased()

    // Exact contains first (fast path)
    if text.contains(phrase) { return true }

    let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    let phraseWords = phrase.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    let n = phraseWords.count

    // Single word phrase — check each word
    if n == 1 {
        return words.contains { similarityRatio($0, phrase) >= threshold }
    }

    // Multi-word phrase — check sliding window of n words
    guard words.count >= n else {
        // Fewer words than phrase — compare whole text
        return similarityRatio(text, phrase) >= threshold
    }
    for i in 0...(words.count - n) {
        let window = words[i..<(i+n)].joined(separator: " ")
        if similarityRatio(window, phrase) >= threshold { return true }
    }
    return false
}
