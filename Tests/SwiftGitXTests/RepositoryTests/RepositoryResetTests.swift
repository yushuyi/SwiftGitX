import Testing

@testable import SwiftGitX

@Suite("Repository - Reset", .tags(.repository, .operation, .reset))
final class RepositoryResetTests: SwiftGitXTest {
    @Test("Reset staged file")
    func resetStagedFile() async throws {
        let repository = mockRepository()
        let initialCommit = try repository.mockCommit()

        // Create and stage a file
        let file = try repository.mockFile()
        try repository.add(file: file)

        #expect(try repository.status(file: file) == [.indexNew])

        // Reset the staged file
        try repository.reset(from: initialCommit, files: [file])

        // File should be untracked now
        let status = try repository.status(file: file)
        #expect(status == [.workingTreeNew])
    }

    @Test("Soft reset to previous commit")
    func resetSoft() async throws {
        let repository = mockRepository()
        let initialCommit = try repository.mockCommit()

        // Create another commit
        try repository.mockCommit()

        // Reset to initial commit
        try repository.reset(to: initialCommit)

        // HEAD should point to initial commit
        let headCommit = try #require(repository.HEAD.target as? Commit)
        #expect(headCommit == initialCommit)
    }

    @Test("Dangling commit survives soft reset (no immediate prune)")
    func danglingCommitSurvivesSoftReset() async throws {
        let repository = mockRepository()
        let first = try repository.mockCommit()
        let second = try repository.mockCommit()

        try repository.reset(to: first, mode: .soft)

        // libgit2 不做立即 prune：dangling 提交仍可经 ODB 前缀查找命中
        // （对齐真实 git 的 gc 延迟语义；此前设备端曾误诊为「对象被立即清理」，
        //  实际根因是上层解析器只扫可达提交——与本测试覆盖的行为无关）
        let found: Commit = try repository.show(hexPrefix: String(second.id.hex.prefix(8)))
        #expect(found == second)
    }
}
