//
//  Repository+merge.swift
//  SwiftGitX
//

import Foundation
import libgit2

extension Repository {
    /// 将指定分支合并到当前 HEAD。
    ///
    /// 支持 fast-forward 与普通三方合并；若产生冲突会抛出 ``SwiftGitXError``。
    public func merge(branch: Branch) throws(SwiftGitXError) {
        let branchPointer = try ReferenceFactory.lookupBranchPointer(
            name: branch.name,
            type: branch.type.raw,
            repositoryPointer: pointer
        )
        defer { git_reference_free(branchPointer) }

        let annotatedCommit = try git(operation: .merge) {
            var annotated: OpaquePointer?
            let status = git_annotated_commit_from_ref(&annotated, pointer, branchPointer)
            return (annotated, status)
        }
        defer { git_annotated_commit_free(annotatedCommit) }

        var analysis = git_merge_analysis_t(GIT_MERGE_ANALYSIS_NONE.rawValue)
        var preference = git_merge_preference_t(GIT_MERGE_PREFERENCE_NONE.rawValue)
        var heads: [OpaquePointer?] = [annotatedCommit]

        try heads.withUnsafeMutableBufferPointer { buffer throws(SwiftGitXError) in
            try git(operation: .merge) {
                git_merge_analysis(
                    &analysis,
                    &preference,
                    pointer,
                    buffer.baseAddress,
                    buffer.count
                )
            }
        }

        if (analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue) != 0 {
            return
        }

        let prefersNoFastForward =
            (preference.rawValue & GIT_MERGE_PREFERENCE_NO_FASTFORWARD.rawValue) != 0
        let prefersFastForwardOnly =
            (preference.rawValue & GIT_MERGE_PREFERENCE_FASTFORWARD_ONLY.rawValue) != 0
        let canFastForward = (analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue) != 0
        let isUnborn = (analysis.rawValue & GIT_MERGE_ANALYSIS_UNBORN.rawValue) != 0
        let needsNormalMerge = (analysis.rawValue & GIT_MERGE_ANALYSIS_NORMAL.rawValue) != 0

        // libgit2 官方示例：fast-forward 须 checkout + 移动分支指针，不能走 git_merge。
        if isUnborn || (canFastForward && !prefersNoFastForward) {
            try performFastForward(to: annotatedCommit)
            return
        }

        if prefersFastForwardOnly && needsNormalMerge {
            throw SwiftGitXError(
                code: .nonFastForward,
                operation: .merge,
                category: .merge,
                message: "当前配置仅允许 fast-forward 合并，但存在分叉历史"
            )
        }

        try performNormalMerge(annotatedCommit: annotatedCommit, remoteBranchName: branch.name)
    }

    /// 清除进行中的 merge / rebase / cherry-pick 状态。
    public func cleanupMergeState() throws(SwiftGitXError) {
        try git(operation: .merge) {
            git_repository_state_cleanup(pointer)
        }
    }

    /// 中止进行中的 merge，将 HEAD、索引与工作区恢复到 ORIG_HEAD。
    public func abortMerge() throws(SwiftGitXError) {
        guard git_repository_state(pointer) == GIT_REPOSITORY_STATE_MERGE.rawValue else {
            throw SwiftGitXError(
                code: .error,
                operation: .merge,
                category: .merge,
                message: "没有可中止的合并（MERGE_HEAD 不存在）"
            )
        }

        guard let origRef = try? reference.get(named: "ORIG_HEAD"),
              let commit = origRef.target as? Commit
        else {
            throw SwiftGitXError(
                code: .notFound,
                operation: .merge,
                category: .reference,
                message: "无法解析 ORIG_HEAD，无法中止合并"
            )
        }

        try reset(to: commit, mode: .hard)
        try cleanupMergeState()
    }

    private func performFastForward(to annotatedCommit: OpaquePointer) throws(SwiftGitXError) {
        var targetOID = git_annotated_commit_id(annotatedCommit).pointee
        let targetCommit = try ObjectFactory.lookupCommit(oid: targetOID, repositoryPointer: pointer)
        let currentBranch = try branch.current

        try checkout(to: targetCommit)

        let branchPointer = try ReferenceFactory.lookupBranchPointer(
            name: currentBranch.name,
            type: BranchType.local.raw,
            repositoryPointer: pointer
        )
        defer { git_reference_free(branchPointer) }

        var updatedPointer: OpaquePointer?
        try git(operation: .merge) {
            git_reference_set_target(&updatedPointer, branchPointer, &targetOID, "fast-forward")
        }
        if let updatedPointer {
            git_reference_free(updatedPointer)
        }

        try cleanupMergeState()
    }

    private func performNormalMerge(
        annotatedCommit: OpaquePointer,
        remoteBranchName: String
    ) throws(SwiftGitXError) {
        var mergeOptions = git_merge_options()
        git_merge_options_init(&mergeOptions, UInt32(GIT_MERGE_OPTIONS_VERSION))

        var checkoutOptions = git_checkout_options()
        git_checkout_options_init(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        checkoutOptions.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        var heads: [OpaquePointer?] = [annotatedCommit]
        try heads.withUnsafeMutableBufferPointer { buffer throws(SwiftGitXError) in
            try git(operation: .merge) {
                git_merge(
                    pointer,
                    buffer.baseAddress,
                    buffer.count,
                    &mergeOptions,
                    &checkoutOptions
                )
            }
        }

        if try indexHasConflicts() {
            throw SwiftGitXError(
                code: .mergeConflict,
                operation: .merge,
                category: .merge,
                message: "合并冲突，请先解决冲突文件后再提交"
            )
        }

        let message = readMergeMessage() ?? "Merge \(remoteBranchName)"
        _ = try commit(message: message)
        try cleanupMergeState()
    }

    private func indexHasConflicts() throws(SwiftGitXError) -> Bool {
        let indexPointer = try git(operation: .index) {
            var indexPointer: OpaquePointer?
            let status = git_repository_index(&indexPointer, pointer)
            return (indexPointer, status)
        }
        defer { git_index_free(indexPointer) }
        return git_index_has_conflicts(indexPointer) == 1
    }

    private func readMergeMessage() -> String? {
        guard let workdir = try? workingDirectory else { return nil }
        let mergeMsgPath = workdir.appendingPathComponent(".git/MERGE_MSG")
        guard let data = try? Data(contentsOf: mergeMsgPath),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension SwiftGitXError.Operation {
    public static let merge = Self(rawValue: "merge")
    public static let pull = Self(rawValue: "pull")
}
