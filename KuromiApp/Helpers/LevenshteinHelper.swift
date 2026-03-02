import Foundation

struct LevenshteinHelper {
    /// Compute Levenshtein distance between two strings
    static func distance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1.lowercased())
        let b = Array(s2.lowercased())
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        return dp[m][n]
    }

    /// Returns similarity ratio 0.0 - 1.0
    static func similarity(_ s1: String, _ s2: String) -> Double {
        let maxLen = max(s1.count, s2.count)
        if maxLen == 0 { return 1.0 }
        let dist = distance(s1, s2)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    /// Returns true if s1 and s2 are similar above threshold (default 0.75)
    static func matches(_ s1: String, _ s2: String, threshold: Double = 0.75) -> Bool {
        return similarity(s1, s2) >= threshold
    }

    /// Check if recognized text contains wake word (fuzzy)
    static func containsWakeWord(_ text: String, wakeWord: String, threshold: Double = 0.75) -> Bool {
        let words = text.lowercased().components(separatedBy: .whitespaces)
        let wakeWords = wakeWord.lowercased().components(separatedBy: .whitespaces)
        guard !wakeWords.isEmpty else { return false }

        // Sliding window over recognized words
        if words.count >= wakeWords.count {
            for i in 0...(words.count - wakeWords.count) {
                let window = words[i..<(i + wakeWords.count)].joined(separator: " ")
                if similarity(window, wakeWord.lowercased()) >= threshold {
                    return true
                }
            }
        }
        // Also check full text against wake word
        return similarity(text.lowercased(), wakeWord.lowercased()) >= threshold
    }
}
