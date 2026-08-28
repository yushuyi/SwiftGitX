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

    /// 修改最近一次提交（HEAD），以当前暂存区为提交内容。
    ///
    /// - Parameter message: 新的提交信息。
    /// - Returns: 改写后的提交。
    ///
    /// 与命令行 `git commit --amend -m <message>` 语义一致：
    /// - 提交内容为当前暂存区（干净暂存区时即「仅改提交信息」场景）
    /// - 作者沿用原提交，committer 更新为当前配置身份
    /// - 需要已配置 user.name / user.email（与真实 git 一致）
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

        // 用当前暂存区生成树：对齐真实 git 的「amend 提交当前 index」语义，
        // 干净暂存区时 index 树 == 原树，行为退化为仅改提交信息
        var indexPointer: OpaquePointer?
        try SwiftGitXError.check(git_repository_index(&indexPointer, pointer), operation: .index)
        defer { git_index_free(indexPointer) }

        var indexTreeOID = git_oid()
        try SwiftGitXError.check(git_index_write_tree(&indexTreeOID, indexPointer), operation: .index)

        let treePointer = try ObjectFactory.lookupObjectPointer(
            oid: indexTreeOID,
            type: GIT_OBJECT_TREE,
            repositoryPointer: pointer
        )
        defer { git_object_free(treePointer) }

        // committer 更新为当前配置身份（对齐真实 git），author 沿用原提交
        var committer: UnsafeMutablePointer<git_signature>?
        try SwiftGitXError.check(git_signature_default(&committer, pointer), operation: .commit)
        defer { git_signature_free(committer) }

        // update_ref = "HEAD"：改写后同步移动当前分支指向
        var oid = git_oid()
        try git(operation: .commit) {
            git_commit_amend(&oid, commitPointer, "HEAD", nil, committer, nil, message, treePointer)
        }

        return try ObjectFactory.lookupCommit(oid: oid, repositoryPointer: pointer)
    }
}
