//
//  Repository+commit.swift
//  SwiftGitX
//
//  Created by İbrahim Çetin on 23.11.2025.
//

import libgit2

extension Repository {
    /// Create a new commit containing the current contents of the index.
    ///
    /// - Parameters:
    ///   - message: The commit message.
    ///   - options: The options to use when creating the commit.
    ///
    /// - Returns: The created commit.
    ///
    /// This method uses the default author and committer information.
    @discardableResult
    public func commit(message: String, options: CommitOptions = .default) throws(SwiftGitXError) -> Commit {
        // Create a new commit from the index
        var oid = git_oid()
        var gitOptions = options.gitCommitCreateOptions

        try git(operation: .commit) {
            git_commit_create_from_stage(
                &oid,
                pointer,
                message,
                &gitOptions
            )
        }

        // Lookup the resulting commit
        return try ObjectFactory.lookupCommit(oid: oid, repositoryPointer: pointer)
    }

    /// 修改最近一次提交（HEAD）的提交信息。
    ///
    /// - Parameter message: 新的提交信息。
    /// - Returns: 改写后的提交。
    ///
    /// 仅改写提交信息：作者、树与暂存区内容保持不变，且不要求暂存区有任何改动，
    /// 等价于命令行 `git commit --amend -m <message>` 的「只改信息」场景。
    @discardableResult
    public func amendCommit(message: String) throws(SwiftGitXError) -> Commit {
        // 取 HEAD 指向的提交作为被改写对象（空仓库 / 未出生分支时直接报错）
        let headReference = try HEAD
        guard let commit = headReference.target as? Commit else {
            throw SwiftGitXError(
                code: .error,
                category: .internal,
                message: "HEAD 不指向提交，无法 amend"
            )
        }

        let commitPointer = try ObjectFactory.lookupObjectPointer(
            oid: commit.id.raw,
            type: GIT_OBJECT_COMMIT,
            repositoryPointer: pointer
        )
        defer { git_object_free(commitPointer) }

        // update_ref = "HEAD"：改写后同步移动当前分支指向；
        // author / committer / tree 传 nil 沿用原提交，仅替换提交信息。
        var oid = git_oid()
        try git(operation: .commit) {
            git_commit_amend(&oid, commitPointer, "HEAD", nil, nil, nil, message, nil)
        }

        return try ObjectFactory.lookupCommit(oid: oid, repositoryPointer: pointer)
    }
}
