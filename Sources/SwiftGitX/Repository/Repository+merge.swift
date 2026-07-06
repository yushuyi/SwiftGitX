//
//  Repository+merge.swift
//  SwiftGitX
//

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

        var mergeOptions = git_merge_options()
        git_merge_options_init(&mergeOptions, UInt32(GIT_MERGE_OPTIONS_VERSION))

        var checkoutOptions = git_checkout_options()
        git_checkout_options_init(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        checkoutOptions.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

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
    }
}

extension SwiftGitXError.Operation {
    public static let merge = Self(rawValue: "merge")
    public static let pull = Self(rawValue: "pull")
}
