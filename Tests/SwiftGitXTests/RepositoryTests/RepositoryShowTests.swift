import SwiftGitX
import Testing

@Suite("Repository - Show", .tags(.repository, .operation, .show))
final class RepositoryShowTests: SwiftGitXTest {
    @Test("Show Commit")
    func showCommit() throws {
        // Create mock repository at the temporary directory
        let repository = mockRepository()

        // Create a new commit
        let commit = try repository.mockCommit()

        // Get the commit by id
        let commitShowed: Commit = try repository.show(id: commit.id)

        // Check if the commit is the same
        #expect(commit == commitShowed)
    }

    @Test("Show Tag")
    func showTag() throws {
        // Create mock repository at the temporary directory
        let repository = mockRepository()

        // Create a new commit
        let commit = try repository.mockCommit()

        // Create a new tag
        let tag = try repository.tag.create(named: "v1.0.0", target: commit)

        // Get the tag by id
        let tagShowed: SwiftGitX.Tag = try repository.show(id: tag.id)

        // Check if the tag is the same
        #expect(tag == tagShowed)
    }

    @Test("Show Tree")
    func showTree() throws {
        // Create mock repository at the temporary directory
        let repository = mockRepository()

        // Create a new commit
        let commit = try repository.mockCommit()

        // Get the tree of the commit
        let tree = try commit.tree

        // Get the tree by id
        let treeShowed: Tree = try repository.show(id: tree.id)

        // Check if the tree is the same
        #expect(tree == treeShowed)
    }

    @Test("Show Blob")
    func showBlob() throws {
        // Create mock repository at the temporary directory
        let repository = mockRepository()

        // Create a new commit
        let commit = try repository.mockCommit()

        // Get the blob of the file
        let blob = try #require(commit.tree.entries.first)

        // Get the blob by id
        let blobShowed: Blob = try repository.show(id: blob.id)

        // Check if the blob properties are the same
        #expect(blob.id == blobShowed.id)
        #expect(blob.type == blobShowed.type)
    }

    @Test("Show Invalid Object Type Should Fail")
    func showInvalidObjectType() throws {
        // Create mock repository at the temporary directory
        let repository = mockRepository()

        // Create a new commit
        let commit = try repository.mockCommit()

        // Try to show a commit as a tree
        #expect(throws: Error.self) {
            try repository.show(id: commit.id) as Tree
        }
    }

    @Test("Show commit by hex prefix (dangling commit included)")
    func showByHexPrefix() throws {
        let repository = mockRepository()
        let first = try repository.mockCommit()
        let second = try repository.mockCommit()

        // soft reset 后 second 成为 dangling 提交：短 SHA 前缀查找必须仍可命中
        // （对齐真实 git；此前 Terminal 解析器只扫可达提交导致 reset 后无法回退）
        try repository.reset(to: first, mode: .soft)

        let hex = second.id.hex
        let found: Commit = try repository.show(hexPrefix: String(hex.prefix(8)))
        #expect(found == second)

        // 全长度前缀（40 位）同样可用
        let foundFull: Commit = try repository.show(hexPrefix: hex)
        #expect(foundFull == second)
    }

    @Test("Show by invalid hex prefix throws")
    func showByInvalidHexPrefixThrows() throws {
        let repository = mockRepository()
        _ = try repository.mockCommit()

        // 少于 4 位 / 含非十六进制字符：前置 guard 抛「无效的哈希前缀」
        #expect(throws: SwiftGitXError.self) {
            do { let _: Commit = try repository.show(hexPrefix: "abc"); return }
            catch let e as SwiftGitXError { #expect(e.message.contains("无效的哈希前缀")); throw e }
        }
        #expect(throws: SwiftGitXError.self) {
            do { let _: Commit = try repository.show(hexPrefix: "xyz123"); return }
            catch let e as SwiftGitXError { #expect(e.message.contains("无效的哈希前缀")); throw e }
        }
        // 41 位（超过 40 上限）：同样前置 guard 拒绝
        #expect(throws: SwiftGitXError.self) {
            do { let _: Commit = try repository.show(hexPrefix: String(repeating: "a", count: 41)); return }
            catch let e as SwiftGitXError { #expect(e.message.contains("无效的哈希前缀")); throw e }
        }
        // 全角十六进制字符：非 ASCII，前置 guard 拒绝
        #expect(throws: SwiftGitXError.self) {
            do { let _: Commit = try repository.show(hexPrefix: "４６９２"); return }
            catch let e as SwiftGitXError { #expect(e.message.contains("无效的哈希前缀")); throw e }
        }
        // 格式合法但不存在的对象：走 libgit2 路径报 notFound
        #expect(throws: SwiftGitXError.self) {
            do { let _: Commit = try repository.show(hexPrefix: "ffffffff"); return }
            catch let e as SwiftGitXError { #expect(e.code == .notFound, "应报 notFound，实际 \(e.code)"); throw e }
        }
    }

    @Test("Show by uppercase hex prefix")
    func showByUppercaseHexPrefix() throws {
        let repository = mockRepository()
        let commit = try repository.mockCommit()

        // 大小写不敏感（文档承诺的行为）
        let hex = commit.id.hex.uppercased()
        let found: Commit = try repository.show(hexPrefix: String(hex.prefix(8)))
        #expect(found == commit)
    }
}
