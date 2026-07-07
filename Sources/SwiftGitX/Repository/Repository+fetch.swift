//
//  Repository+fetch.swift
//  SwiftGitX
//

import Foundation
import libgit2

extension Repository {
    /// 从远程抓取对象与引用。
    ///
    /// 未指定 `remote` 时，优先使用当前分支的上游远程，否则回退到 `origin`。
    public nonisolated func fetch(
        remote: Remote? = nil,
        refspecs: [String]? = nil,
        sshCredentials: SSHMemoryCredentials? = nil,
        httpCredentials: GitHTTPCredentials? = nil,
        connectionFetchURL: URL? = nil,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) {
        guard let remote = remote ?? (try? branch.current.remote) ?? self.remote["origin"] else {
            throw SwiftGitXError(code: .notFound, category: .reference, message: "Remote not found")
        }

        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: remote.name, repositoryPointer: pointer)
        defer { git_remote_free(remotePointer) }

        if let connectionFetchURL {
            try GitRemoteInstanceURL.apply(fetchURL: connectionFetchURL, to: remotePointer)
        }

        let networkContext: GitNetworkContext?
        var plainProgressPointer: UnsafeMutablePointer<TransferProgressHandler>?
        var fetchOptions: git_fetch_options?

        if GitNetworkCallbackBinder.needsCustomCallbacks(
            sshCredentials: sshCredentials,
            httpCredentials: httpCredentials,
            progressHandler: transferProgressHandler
        ) {
            var options = git_fetch_options()
            git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION))

            let bound = GitNetworkCallbackBinder.bind(
                sshCredentials: sshCredentials,
                httpCredentials: httpCredentials,
                progressHandler: transferProgressHandler,
                to: &options.callbacks
            )
            networkContext = bound.context
            plainProgressPointer = bound.plainProgressPointer
            fetchOptions = options
        } else {
            networkContext = nil
        }
        defer { plainProgressPointer?.deallocate() }
        _ = networkContext

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
