//
//  Repository+cloneSSH.swift
//  SwiftGitX
//

import Foundation
import libgit2

extension Repository {
    /// 使用内存中的 SSH 密钥克隆仓库（iOS libssh2 传输所需）。
    public nonisolated static func cloneWithSSHMemoryCredentials(
        from remoteURL: URL,
        to localURL: URL,
        username: String,
        publicKey: String,
        privateKey: String,
        passphrase: String = "",
        knownHostsPaths: [String] = SSHKnownHosts.defaultKnownHostsPaths(),
        options: CloneOptions = .default,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) -> Repository {
        let credentials = SSHMemoryCredentials(
            username: username,
            publicKey: publicKey,
            privateKey: privateKey,
            passphrase: passphrase,
            knownHostsPaths: knownHostsPaths
        )
        return try await cloneWithSSHMemoryCredentials(
            from: remoteURL,
            to: localURL,
            credentials: credentials,
            options: options,
            transferProgressHandler: transferProgressHandler
        )
    }

    /// 使用 ``SSHMemoryCredentials`` 克隆仓库。
    public nonisolated static func cloneWithSSHMemoryCredentials(
        from remoteURL: URL,
        to localURL: URL,
        credentials: SSHMemoryCredentials,
        options: CloneOptions = .default,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) -> Repository {
        try await cloneWithNetworkCredentials(
            from: remoteURL,
            to: localURL,
            sshCredentials: credentials,
            httpCredentials: nil,
            options: options,
            transferProgressHandler: transferProgressHandler
        )
    }

    /// 使用 SSH 和/或 HTTPS 凭据克隆仓库。
    public nonisolated static func cloneWithNetworkCredentials(
        from remoteURL: URL,
        to localURL: URL,
        sshCredentials: SSHMemoryCredentials? = nil,
        httpCredentials: GitHTTPCredentials? = nil,
        options: CloneOptions = .default,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) -> Repository {
        try SwiftGitXRuntime.initialize()

        var cloneOptions = options.gitCloneOptions
        cloneOptions.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        let networkContext: GitNetworkContext?
        if GitNetworkCallbackBinder.needsCustomCallbacks(
            sshCredentials: sshCredentials,
            httpCredentials: httpCredentials,
            progressHandler: transferProgressHandler
        ) {
            let context = GitNetworkContext(
                sshCredentials: sshCredentials,
                httpCredentials: httpCredentials,
                progressHandler: transferProgressHandler
            )
            context.bind(to: &cloneOptions.fetch_opts.callbacks)
            networkContext = context
        } else {
            networkContext = nil
        }
        _ = networkContext

        do {
            let pointer = try git(operation: .clone) {
                var pointer: OpaquePointer?
                let status = git_clone(&pointer, remoteURL.absoluteString, localURL.path, &cloneOptions)
                return (pointer, status)
            }
            return Repository(pointer: pointer)
        } catch {
            _ = try? SwiftGitXRuntime.shutdown()
            throw error
        }
    }
}
