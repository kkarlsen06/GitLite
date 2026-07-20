import Foundation

struct RepositoryFileSearchMatch: Identifiable, Equatable, Sendable {
    let path: String
    let score: Int

    var id: String { path }
}

struct RepositoryTextSearchMatch: Identifiable, Equatable, Sendable {
    let path: String
    let line: Int
    let preview: String

    var id: String { "\(path):\(line)" }
}

struct RepositorySearchResults: Equatable, Sendable {
    static let empty = RepositorySearchResults(
        fileMatches: [],
        textMatches: [],
        fileMatchesWereLimited: false,
        textMatchesWereLimited: false
    )

    let fileMatches: [RepositoryFileSearchMatch]
    let textMatches: [RepositoryTextSearchMatch]
    let fileMatchesWereLimited: Bool
    let textMatchesWereLimited: Bool

    var matchingFilePaths: Set<String> {
        Set(fileMatches.map(\.path))
    }
}

enum RepositoryPathMatcher {
    static func score(query rawQuery: String, path: String) -> Int? {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return nil }

        let normalizedPath = path.lowercased()
        let name = URL(fileURLWithPath: normalizedPath).lastPathComponent

        if query.contains("*") || query.contains("?") {
            if wildcardMatch(pattern: query, candidate: name) {
                return 0
            }
            if wildcardMatch(pattern: query, candidate: normalizedPath) {
                return 20
            }
            return nil
        }

        if name == query { return 0 }
        if name.hasPrefix(query) { return 10 + max(0, name.count - query.count) }
        if let range = name.range(of: query) {
            return 30 + name.distance(from: name.startIndex, to: range.lowerBound)
        }
        if let range = normalizedPath.range(of: query) {
            return 60 + normalizedPath.distance(
                from: normalizedPath.startIndex,
                to: range.lowerBound
            )
        }
        if let score = subsequenceScore(query: query, candidate: name) {
            return 100 + score
        }
        if let score = subsequenceScore(query: query, candidate: normalizedPath) {
            return 160 + score
        }
        return nil
    }

    private static func subsequenceScore(
        query: String,
        candidate: String
    ) -> Int? {
        var candidateIndex = candidate.startIndex
        var previousMatchIndex: String.Index?
        var score = 0

        for character in query {
            guard let matchIndex = candidate[candidateIndex...]
                .firstIndex(of: character) else {
                return nil
            }
            if let previousMatchIndex {
                score += candidate.distance(
                    from: previousMatchIndex,
                    to: matchIndex
                ) - 1
            } else {
                score += candidate.distance(
                    from: candidate.startIndex,
                    to: matchIndex
                )
            }
            previousMatchIndex = matchIndex
            candidateIndex = candidate.index(after: matchIndex)
        }
        return score
    }

    private static func wildcardMatch(
        pattern: String,
        candidate: String
    ) -> Bool {
        let pattern = Array(pattern)
        let candidate = Array(candidate)
        var matches = Array(
            repeating: Array(repeating: false, count: candidate.count + 1),
            count: pattern.count + 1
        )
        matches[0][0] = true

        if !pattern.isEmpty {
            for patternIndex in 1...pattern.count
            where pattern[patternIndex - 1] == "*" {
                matches[patternIndex][0] = matches[patternIndex - 1][0]
            }
        }

        guard !pattern.isEmpty, !candidate.isEmpty else {
            return matches[pattern.count][candidate.count]
        }
        for patternIndex in 1...pattern.count {
            for candidateIndex in 1...candidate.count {
                switch pattern[patternIndex - 1] {
                case "*":
                    matches[patternIndex][candidateIndex] =
                        matches[patternIndex - 1][candidateIndex]
                        || matches[patternIndex][candidateIndex - 1]
                case "?":
                    matches[patternIndex][candidateIndex] =
                        matches[patternIndex - 1][candidateIndex - 1]
                default:
                    matches[patternIndex][candidateIndex] =
                        matches[patternIndex - 1][candidateIndex - 1]
                        && pattern[patternIndex - 1]
                            == candidate[candidateIndex - 1]
                }
            }
        }
        return matches[pattern.count][candidate.count]
    }
}

enum RepositorySearchParser {
    static func filePaths(from output: String) -> [String] {
        output.split(separator: "\0").map(String.init)
    }

    static func textMatches(
        from output: String,
        limit: Int
    ) -> (matches: [RepositoryTextSearchMatch], wasLimited: Bool) {
        guard limit > 0 else { return ([], !output.isEmpty) }
        var matches: [RepositoryTextSearchMatch] = []
        var wasLimited = false

        for rawRecord in output.split(separator: "\n") {
            let fields = rawRecord.split(
                separator: "\0",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            guard fields.count == 3,
                  let line = Int(fields[1]),
                  line > 0 else {
                continue
            }
            if matches.count == limit {
                wasLimited = true
                break
            }
            let preview = fields[2]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            matches.append(RepositoryTextSearchMatch(
                path: String(fields[0]),
                line: line,
                preview: String(preview.prefix(300))
            ))
        }
        return (matches, wasLimited)
    }
}
