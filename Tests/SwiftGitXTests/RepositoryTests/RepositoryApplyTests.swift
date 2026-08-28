import Foundation
import SwiftGitX
import Testing

@Suite("Repository - Apply & Amend", .tags(.repository, .operation, .patch, .commit))
final class RepositoryApplyTests: SwiftGitXTest {

    @Test("Amend rewrites message with clean index")
    func amendRewritesMessage() async throws {
        let repository = mockRepository()
        _ = try repository.mockCommit(message: "first")
        let second = try repository.mockCommit(message: "second")

        // 暂存区干净时 amend 仅改写提交信息
        let amended = try repository.amendCommit(message: "second (amended)")

        let head = try #require(repository.HEAD.target as? Commit)
        #expect(head.id == amended.id)
        #expect(head.summary == "second (amended)")
        let amendedTree = try amended.tree
        let secondTree = try second.tree
        #expect(amendedTree.id == secondTree.id, "amend 不应改动树")

        let commitCount = (try? repository.log().reduce(0) { count, _ in count + 1 }) ?? 0
        #expect(commitCount == 2, "amend 不应新增提交")
    }

    @Test("Apply full git-style patch to working tree")
    func applyFullPatch() async throws {
        let repository = mockRepository()
        let file = try repository.mockFile(name: "a.txt", content: "v1\n")
        try repository.add(file: file)
        _ = try repository.mockCommit(file: file)

        let patch = "diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-v1\n+v2\n"
        try repository.apply(patch: patch, checkOnly: true)
        try repository.apply(patch: patch)

        #expect(try String(contentsOf: file, encoding: .utf8) == "v2\n")
    }

    @Test("Apply patch without diff --git header is rejected")
    func applyHeaderlessPatch() async throws {
        let repository = mockRepository()
        let file = try repository.mockFile(name: "b.txt", content: "v1\n")
        try repository.add(file: file)
        _ = try repository.mockCommit(file: file)

        // libgit2 的补丁解析要求以 diff --git 头行开头，裸 --- / +++ 形状必须被拒绝
        let patch = "--- a/b.txt\n+++ b/b.txt\n@@ -1 +1 @@\n-v1\n+v2\n"
        #expect(throws: (any Error).self) {
            try repository.apply(patch: patch)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "v1\n", "解析失败的补丁不应改动文件")
    }

    @Test("Apply new-file patch shape")
    func applyNewFilePatch() async throws {
        let repository = mockRepository()
        _ = try repository.mockCommit(message: "base")

        // 首提交合成 diff 的输出形状：diff --git + new file mode + /dev/null 旧侧
        let patch = "diff --git a/new.txt b/new.txt\nnew file mode 100644\n--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1 @@\n+hello\n"
        try repository.apply(patch: patch)

        let created = try repository.workingDirectory.appendingPathComponent("new.txt")
        #expect(try String(contentsOf: created, encoding: .utf8) == "hello\n")
    }

    @Test("Apply checkOnly does not modify and conflict throws")
    func applyCheckAndConflict() async throws {
        let repository = mockRepository()
        let file = try repository.mockFile(name: "c.txt", content: "v1\n")
        try repository.add(file: file)
        _ = try repository.mockCommit(file: file)

        let patch = "diff --git a/c.txt b/c.txt\n--- a/c.txt\n+++ b/c.txt\n@@ -1 +1 @@\n-v1\n+v2\n"

        try repository.apply(patch: patch, checkOnly: true)
        #expect(try String(contentsOf: file, encoding: .utf8) == "v1\n", "--check 不应改动文件")

        // 文件已是 v2 时再应用同一补丁应报冲突
        try "v2\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) {
            try repository.apply(patch: patch)
        }
    }
}
