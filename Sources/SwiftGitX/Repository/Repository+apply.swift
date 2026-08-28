//
//  Repository+apply.swift
//  SwiftGitX
//

import libgit2

extension SwiftGitXError.Operation {
    public static let apply = Self(rawValue: "apply")
}

extension Repository {

    /// 将 unified diff 补丁文本应用到当前工作区。
    ///
    /// - Parameters:
    ///   - patch: 补丁文本，`git diff` 输出格式（可含多个文件的 diff）。
    ///   - checkOnly: `true` 时只校验补丁能否干净应用，不改动任何文件，
    ///     等价于命令行 `git apply --check`。
    ///
    /// 等价于命令行 `git apply <patchfile>`（应用到工作区，不写索引）。
    /// 补丁与工作区冲突时抛出 `SwiftGitXError`。
    public func apply(patch: String, checkOnly: Bool = false) throws(SwiftGitXError) {
        // 直接把补丁文本解析为 git_diff（无需先构造 patch 对象）
        var diffPointer: OpaquePointer?
        let status = patch.utf8CString.withUnsafeBufferPointer { buffer in
            // count - 1：去掉 C 字符串末尾的 NUL，content_len 传纯内容长度
            git_diff_from_buffer(&diffPointer, buffer.baseAddress, buffer.count - 1)
        }
        try SwiftGitXError.check(status, operation: .apply)
        defer { git_diff_free(diffPointer) }

        // GIT_APPLY_OPTIONS_VERSION 为 C 宏（值为 1）不会导出到 Swift，直接传 1
        var options = git_apply_options()
        git_apply_options_init(&options, 1)
        options.flags = checkOnly ? GIT_APPLY_CHECK.rawValue : 0

        try git(operation: .apply) {
            git_apply(pointer, diffPointer, GIT_APPLY_LOCATION_WORKDIR, &options)
        }
    }
}
