//
//  GitNetworkContext.swift
//  SwiftGitX
//
//  iOS 上 libgit2 网络传输：SSH（libssh2 内存密钥）与 HTTPS（userpass）凭据回调。
//

import Foundation
import libgit2

/// 内存中的 SSH 密钥凭据，供 fetch / clone / pull 等网络操作使用。
public struct SSHMemoryCredentials: Sendable {
    public let username: String
    public let publicKey: String
    public let privateKey: String
    public let passphrase: String
    public let knownHostsPaths: [String]

    public init(
        username: String,
        publicKey: String,
        privateKey: String,
        passphrase: String = "",
        knownHostsPaths: [String] = SSHKnownHosts.defaultKnownHostsPaths()
    ) {
        self.username = username
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.passphrase = passphrase
        self.knownHostsPaths = knownHostsPaths
    }
}

final class GitNetworkContext: @unchecked Sendable {
    let sshCredentials: SSHMemoryCredentials?
    let httpCredentials: GitHTTPCredentials?
    var progressHandler: TransferProgressHandler?

    init(
        sshCredentials: SSHMemoryCredentials? = nil,
        httpCredentials: GitHTTPCredentials? = nil,
        progressHandler: TransferProgressHandler? = nil
    ) {
        self.sshCredentials = sshCredentials
        self.httpCredentials = httpCredentials
        self.progressHandler = progressHandler
    }

    func bind(to callbacks: inout git_remote_callbacks) {
        callbacks.transfer_progress = Self.transferProgressCallback
        callbacks.credentials = Self.credentialsCallback
        callbacks.certificate_check = Self.certificateCheckCallback
        callbacks.payload = Unmanaged.passUnretained(self).toOpaque()
    }

    private static let credentialsCallback: git_credential_acquire_cb = { out, _, usernameFromURL, allowedTypes, payload in
        guard let out, let payload else { return -1 }

        let context = Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue()

        if allowedTypes & GIT_CREDENTIAL_SSH_MEMORY.rawValue != 0, let ssh = context.sshCredentials {
            let username: String
            if let usernameFromURL {
                username = String(cString: usernameFromURL)
            } else {
                username = ssh.username
            }
            return git_credential_ssh_key_memory_new(
                out,
                username,
                ssh.publicKey,
                ssh.privateKey,
                ssh.passphrase
            )
        }

        if allowedTypes & GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue != 0, let http = context.httpCredentials {
            return git_credential_userpass_plaintext_new(out, http.username, http.password)
        }

        return Int32(GIT_PASSTHROUGH.rawValue)
    }

    private static let certificateCheckCallback: git_transport_certificate_check_cb = { cert, valid, host, payload in
        if valid != 0 { return 0 }
        guard let cert else { return -1 }

        if cert.pointee.cert_type == GIT_CERT_X509 {
            return 0
        }

        guard cert.pointee.cert_type == GIT_CERT_HOSTKEY_LIBSSH2, let host else { return -1 }

        let hostkey = UnsafeRawPointer(cert).assumingMemoryBound(to: git_cert_hostkey.self).pointee
        let hostString = String(cString: host)
        let paths: [String]
        if let payload {
            paths = Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue()
                .sshCredentials?.knownHostsPaths ?? SSHKnownHosts.defaultKnownHostsPaths()
        } else {
            paths = SSHKnownHosts.defaultKnownHostsPaths()
        }

        return SSHKnownHosts.acceptNew(host: hostString, hostkey: hostkey, knownHostsPaths: paths) ? 0 : -1
    }

    private static let transferProgressCallback: git_indexer_progress_cb = { stats, payload in
        guard Task.isCancelled == false else { return 1 }

        guard let stats = stats?.pointee,
              let payload,
              let handler = Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue().progressHandler
        else {
            return 0
        }

        handler(TransferProgress(from: stats))
        return 0
    }

    /// 为非 SSH/HTTP 凭据场景绑定进度回调；返回的指针须在操作完成前保持有效。
    static func bindPlainProgressHandler(
        _ handler: TransferProgressHandler?,
        to callbacks: inout git_remote_callbacks
    ) -> UnsafeMutablePointer<TransferProgressHandler>? {
        guard let handler else { return nil }
        let handlerPointer = UnsafeMutablePointer<TransferProgressHandler>.allocate(capacity: 1)
        handlerPointer.initialize(to: handler)
        callbacks.transfer_progress = plainTransferProgressCallback
        callbacks.payload = UnsafeMutableRawPointer(handlerPointer)
        return handlerPointer
    }

    private static let plainTransferProgressCallback: git_indexer_progress_cb = { stats, payload in
        guard Task.isCancelled == false else { return 1 }

        guard let stats = stats?.pointee,
              let payload = payload?.assumingMemoryBound(to: TransferProgressHandler.self)
        else {
            return 0
        }

        payload.pointee(TransferProgress(from: stats))
        return 0
    }
}

// MARK: - 回调绑定辅助

enum GitNetworkCallbackBinder {
    /// 根据凭据/进度需求配置 `git_remote_callbacks`，返回需保活至操作结束的 context。
    static func bind(
        sshCredentials: SSHMemoryCredentials?,
        httpCredentials: GitHTTPCredentials?,
        progressHandler: TransferProgressHandler?,
        to callbacks: inout git_remote_callbacks
    ) -> (context: GitNetworkContext?, plainProgressPointer: UnsafeMutablePointer<TransferProgressHandler>?) {
        if sshCredentials != nil || httpCredentials != nil {
            let context = GitNetworkContext(
                sshCredentials: sshCredentials,
                httpCredentials: httpCredentials,
                progressHandler: progressHandler
            )
            context.bind(to: &callbacks)
            return (context, nil)
        }

        let plain = GitNetworkContext.bindPlainProgressHandler(progressHandler, to: &callbacks)
        return (nil, plain)
    }

    static func needsCustomCallbacks(
        sshCredentials: SSHMemoryCredentials?,
        httpCredentials: GitHTTPCredentials?,
        progressHandler: TransferProgressHandler?
    ) -> Bool {
        sshCredentials != nil || httpCredentials != nil || progressHandler != nil
    }
}
