import SwiftGitX
import Testing

@Suite("Repository - Log", .tags(.repository, .operation, .log))
final class RepositoryLogTests: SwiftGitXTest {
    @Test("Log returns commits in order")
    func log() async throws {
        let repository = mockRepository()

        // Create multiple commits
        let commits = try (0..<10).map { _ in try repository.mockCommit() }

        // Get log with reverse sorting
        let commitSequence = try repository.log(from: repository.HEAD, sorting: .reverse)
        let logCommits = Array(commitSequence)
        #expect(logCommits == commits)
    }

    @Test("Log with hiding excludes hidden ancestry")
    func logWithHiding() throws {
        let repository = mockRepository()

        // 线性三条提交：first ← second ← third
        let first = try repository.mockCommit()
        let second = try repository.mockCommit()
        let third = try repository.mockCommit()

        // a..b 语义：从 third 可达、排除 second 及其整条祖先链（first 一并排除）
        let commits = Array(repository.log(from: third, hiding: second))
        let hexes = commits.map { $0.id.hex }
        #expect(hexes == [third.id.hex], "应只含 third，实际: \(hexes)")
        #expect(!hexes.contains(first.id.hex))
        #expect(!hexes.contains(second.id.hex))
    }

    @Test("Log with nil hiding equals plain log")
    func logWithNilHiding() throws {
        let repository = mockRepository()
        let first = try repository.mockCommit()
        let second = try repository.mockCommit()

        let plain = Array(repository.log(from: second)).map { $0.id.hex }
        let withNil = Array(repository.log(from: second, hiding: nil)).map { $0.id.hex }
        #expect(plain == withNil, "hiding 传 nil 应等价普通 log")
        #expect(plain.contains(first.id.hex))
    }

    @Test("Log hiding itself yields empty")
    func logHidingItself() throws {
        let repository = mockRepository()
        let commit = try repository.mockCommit()

        // a..a：同一提交被标记 uninteresting，输出为空（对齐 git）
        let commits = Array(repository.log(from: commit, hiding: commit))
        #expect(commits.isEmpty)
    }
}
