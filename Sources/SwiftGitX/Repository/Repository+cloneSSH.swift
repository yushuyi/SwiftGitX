//
//  Repository+cloneSSH.swift
//  SwiftGitX
//
//  iOS 上 libgit2 无法 fork ssh 子进程，须通过 libssh2 + 内存 SSH 凭据克隆。
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
        try SwiftGitXRuntime.initialize()

        let sshContext = GitSSHNetworkContext(
            credentials: credentials,
            progressHandler: transferProgressHandler
        )

        var cloneOptions = options.gitCloneOptions
        cloneOptions.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        sshContext.bind(to: &cloneOptions.fetch_opts.callbacks)

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
