import Foundation
import SwiftGitX
import Testing

@testable import SwiftGitX
import libgit2

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

        // soft reset 后 second 成为 dangling 提交：
        // 对齐真实 git 的 gc 延迟语义，对象必须仍在库里（否则 reset 无法反悔）
        try repository.reset(to: first, mode: .soft)

        // 1) libgit2 视角：OID 仍可直接查找（revparse / git show 依赖此路径）
        var oid = second.id.raw
        var object: OpaquePointer?
        let status = git_object_lookup_prefix(&object, repository.pointer, &oid, 40, GIT_OBJECT_COMMIT)
        #expect(status == 0, "dangling 提交对象应仍可查找（status=\(status)）")
        git_object_free(object)

        // 2) 磁盘视角：loose object 文件应存在（系统 git cat-file 同样依赖它）
        let hex = second.id.hex
        let looseObjectPath = repository.path
            .appendingPathComponent("objects/\(hex.prefix(2))/\(hex.dropFirst(2))")
        #expect(
            FileManager.default.fileExists(atPath: looseObjectPath.path),
            "loose object 文件应存在: \(looseObjectPath.path)"
        )
    }
}
