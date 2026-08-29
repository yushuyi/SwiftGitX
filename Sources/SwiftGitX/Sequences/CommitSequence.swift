import libgit2

/// A sequence of commits.
///
/// This sequence is an async sequence that iterates over the commits in a repository.
///
/// - Warning: The sequence's task should be cancelled before ``Repository`` is deinitialized.
public struct CommitSequence: Sequence {
    public typealias Element = Commit

    public let root: Commit
    /// 从遍历中隐藏的提交（其整个祖先链被排除），对应 `git log a..b` 的 a 侧
    public let hiding: Commit?
    public let sorting: LogSortingOption

    private let repositoryPointer: OpaquePointer

    init(
        root: Commit,
        hiding: Commit? = nil,
        sorting: LogSortingOption,
        repositoryPointer: OpaquePointer
    ) {
        self.root = root
        self.hiding = hiding
        self.sorting = sorting
        self.repositoryPointer = repositoryPointer
    }

    public func makeIterator() -> CommitIterator {
        CommitIterator(root: root, hiding: hiding, sorting: sorting, repositoryPointer: repositoryPointer)
    }
}

public class CommitIterator: IteratorProtocol {
    public let root: Commit
    public let hiding: Commit?
    public let sorting: LogSortingOption

    private let walkerPointer: OpaquePointer?
    private let repositoryPointer: OpaquePointer

    init(
        root: Commit,
        hiding: Commit? = nil,
        sorting: LogSortingOption,
        repositoryPointer: OpaquePointer
    ) {
        self.root = root
        self.hiding = hiding
        self.sorting = sorting

        self.repositoryPointer = repositoryPointer

        // Create a rev walker
        var walkerPointer: OpaquePointer?
        git_revwalk_new(&walkerPointer, repositoryPointer)

        self.walkerPointer = walkerPointer

        // Set the root commit
        // push/hide 均操作同一缓存 commit node；对已成功 lookup 的 oid 实际不会
        // 失败，故沿用既有模式忽略返回值（极端失败时迭代器输出空序列）
        var rootID = root.id.raw
        git_revwalk_push(walkerPointer, &rootID)

        // 隐藏提交：其祖先链整体排除（对齐 git revwalk 的 hide 语义）
        if let hiding {
            var hideID = hiding.id.raw
            git_revwalk_hide(walkerPointer, &hideID)
        }

        // Set the sorting
        git_revwalk_sorting(walkerPointer, sorting.rawValue)
    }

    deinit {
        git_revwalk_free(walkerPointer)
    }

    public func next() -> Commit? {
        // Task should not be cancelled
        if Task.isCancelled { return nil }

        // Get the next commit
        var oid = git_oid()
        let status = git_revwalk_next(&oid, walkerPointer)

        // Check if the status is OK
        guard status == GIT_OK.rawValue else {
            return nil
        }

        return try? ObjectFactory.lookupObject(oid: oid, repositoryPointer: repositoryPointer)
    }
}
