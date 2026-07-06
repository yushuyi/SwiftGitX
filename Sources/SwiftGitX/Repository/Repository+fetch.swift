//
//  Repository+fetch.swift
//  SwiftGitX
//
//  Created by İbrahim Çetin on 23.11.2025.
//

import libgit2

extension Repository {
    /// 从远程抓取对象与引用。
    ///
    /// 未指定 `remote` 时，优先使用当前分支的上游远程，否则回退到 `origin`。
    public nonisolated func fetch(
        remote: Remote? = nil,
        refspecs: [String]? = nil,
        sshCredentials: SSHMemoryCredentials? = nil,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) {
        guard let remote = remote ?? (try? branch.current.remote) ?? self.remote["origin"] else {
            throw SwiftGitXError(code: .notFound, category: .reference, message: "Remote not found")
        }

        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: remote.name, repositoryPointer: pointer)
        defer { git_remote_free(remotePointer) }

        let sshContext: GitSSHNetworkContext?
        var plainProgressPointer: UnsafeMutablePointer<TransferProgressHandler>?
        var fetchOptions: git_fetch_options?

        if sshCredentials != nil || transferProgressHandler != nil {
            var options = git_fetch_options()
            git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION))

            if let sshCredentials {
                let context = GitSSHNetworkContext(
                    credentials: sshCredentials,
                    progressHandler: transferProgressHandler
                )
                context.bind(to: &options.callbacks)
                sshContext = context
            } else {
                sshContext = nil
                plainProgressPointer = GitSSHNetworkContext.bindPlainProgressHandler(
                    transferProgressHandler,
                    to: &options.callbacks
                )
            }
            fetchOptions = options
        } else {
            sshContext = nil
        }
        defer { plainProgressPointer?.deallocate() }
        _ = sshContext

        if let refspecs, !refspecs.isEmpty {
            var strArray = refspecs.gitStrArray
            defer { git_strarray_free(&strArray) }
            try git(operation: .fetch) {
                if var fetchOptions {
                    return git_remote_fetch(remotePointer, &strArray, &fetchOptions, nil)
                }
                return git_remote_fetch(remotePointer, &strArray, nil, nil)
            }
        } else {
            try git(operation: .fetch) {
                if var fetchOptions {
                    return git_remote_fetch(remotePointer, nil, &fetchOptions, nil)
                }
                return git_remote_fetch(remotePointer, nil, nil, nil)
            }
        }
    }
}
