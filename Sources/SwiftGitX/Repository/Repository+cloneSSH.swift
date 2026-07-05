//
//  Repository+cloneSSH.swift
//  SwiftGitX
//
//  iOS 上 libgit2 无法 fork ssh 子进程，须通过 libssh2 + 内存 SSH 凭据克隆。
//

import Foundation
import libgit2

private final class SSHCloneContext: @unchecked Sendable {
    let username: String
    let publicKey: String
    let privateKey: String
    let passphrase: String
    let knownHostsPaths: [String]
    var progressHandler: TransferProgressHandler?

    init(
        username: String,
        publicKey: String,
        privateKey: String,
        passphrase: String,
        knownHostsPaths: [String],
        progressHandler: TransferProgressHandler? = nil
    ) {
        self.username = username
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.passphrase = passphrase
        self.knownHostsPaths = knownHostsPaths
        self.progressHandler = progressHandler
    }
}

private let sshCloneCredentialsCallback: git_credential_acquire_cb = { out, _, usernameFromURL, allowedTypes, payload in
    guard let out, let payload else { return -1 }

    let context = Unmanaged<SSHCloneContext>.fromOpaque(payload).takeUnretainedValue()
    let username: String
    if let usernameFromURL {
        username = String(cString: usernameFromURL)
    } else {
        username = context.username
    }

    if allowedTypes & GIT_CREDENTIAL_SSH_MEMORY.rawValue != 0 {
        return git_credential_ssh_key_memory_new(
            out,
            username,
            context.publicKey,
            context.privateKey,
            context.passphrase
        )
    }

    return Int32(GIT_PASSTHROUGH.rawValue)
}

private let sshCloneCertificateCheckCallback: git_transport_certificate_check_cb = { cert, valid, host, payload in
    if valid != 0 { return 0 }
    guard let cert, let host else { return -1 }
    guard cert.pointee.cert_type == GIT_CERT_HOSTKEY_LIBSSH2 else { return -1 }

    let hostkey = UnsafeRawPointer(cert).assumingMemoryBound(to: git_cert_hostkey.self).pointee
    let hostString = String(cString: host)
    let paths: [String]
    if let payload {
        paths = Unmanaged<SSHCloneContext>.fromOpaque(payload).takeUnretainedValue().knownHostsPaths
    } else {
        paths = SSHKnownHosts.defaultKnownHostsPaths()
    }

    return SSHKnownHosts.acceptNew(host: hostString, hostkey: hostkey, knownHostsPaths: paths) ? 0 : -1
}

private let sshCloneTransferProgressCallback: git_indexer_progress_cb = { stats, payload in
    guard Task.isCancelled == false else { return 1 }

    guard let stats = stats?.pointee,
          let payload,
          let handler = Unmanaged<SSHCloneContext>.fromOpaque(payload).takeUnretainedValue().progressHandler
    else {
        return 0
    }

    handler(TransferProgress(from: stats))
    return 0
}

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
        try SwiftGitXRuntime.initialize()

        let cloneContext = SSHCloneContext(
            username: username,
            publicKey: publicKey,
            privateKey: privateKey,
            passphrase: passphrase,
            knownHostsPaths: knownHostsPaths,
            progressHandler: transferProgressHandler
        )
        let contextPayload = Unmanaged.passUnretained(cloneContext).toOpaque()

        var cloneOptions = options.gitCloneOptions
        cloneOptions.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        cloneOptions.fetch_opts.callbacks.transfer_progress = sshCloneTransferProgressCallback
        cloneOptions.fetch_opts.callbacks.credentials = sshCloneCredentialsCallback
        cloneOptions.fetch_opts.callbacks.certificate_check = sshCloneCertificateCheckCallback
        cloneOptions.fetch_opts.callbacks.payload = contextPayload

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
