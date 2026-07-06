//
//  GitSSHNetworkContext.swift
//  SwiftGitX
//
//  iOS 上 libgit2 通过 libssh2 传输，须注入内存 SSH 凭据与 known_hosts 校验。
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

final class GitSSHNetworkContext: @unchecked Sendable {
    let credentials: SSHMemoryCredentials
    var progressHandler: TransferProgressHandler?

    init(credentials: SSHMemoryCredentials, progressHandler: TransferProgressHandler? = nil) {
        self.credentials = credentials
        self.progressHandler = progressHandler
    }

    func bind(to callbacks: inout git_remote_callbacks) {
        callbacks.transfer_progress = Self.sshTransferProgressCallback
        callbacks.credentials = Self.credentialsCallback
        callbacks.certificate_check = Self.certificateCheckCallback
        callbacks.payload = Unmanaged.passUnretained(self).toOpaque()
    }

    private static let credentialsCallback: git_credential_acquire_cb = { out, _, usernameFromURL, allowedTypes, payload in
        guard let out, let payload else { return -1 }

        let context = Unmanaged<GitSSHNetworkContext>.fromOpaque(payload).takeUnretainedValue()
        let username: String
        if let usernameFromURL {
            username = String(cString: usernameFromURL)
        } else {
            username = context.credentials.username
        }

        if allowedTypes & GIT_CREDENTIAL_SSH_MEMORY.rawValue != 0 {
            return git_credential_ssh_key_memory_new(
                out,
                username,
                context.credentials.publicKey,
                context.credentials.privateKey,
                context.credentials.passphrase
            )
        }

        return Int32(GIT_PASSTHROUGH.rawValue)
    }

    private static let certificateCheckCallback: git_transport_certificate_check_cb = { cert, valid, host, payload in
        if valid != 0 { return 0 }
        guard let cert, let host else { return -1 }
        guard cert.pointee.cert_type == GIT_CERT_HOSTKEY_LIBSSH2 else { return -1 }

        let hostkey = UnsafeRawPointer(cert).assumingMemoryBound(to: git_cert_hostkey.self).pointee
        let hostString = String(cString: host)
        let paths: [String]
        if let payload {
            paths = Unmanaged<GitSSHNetworkContext>.fromOpaque(payload).takeUnretainedValue().credentials.knownHostsPaths
        } else {
            paths = SSHKnownHosts.defaultKnownHostsPaths()
        }

        return SSHKnownHosts.acceptNew(host: hostString, hostkey: hostkey, knownHostsPaths: paths) ? 0 : -1
    }

    private static let sshTransferProgressCallback: git_indexer_progress_cb = { stats, payload in
        guard Task.isCancelled == false else { return 1 }

        guard let stats = stats?.pointee,
              let payload,
              let handler = Unmanaged<GitSSHNetworkContext>.fromOpaque(payload).takeUnretainedValue().progressHandler
        else {
            return 0
        }

        handler(TransferProgress(from: stats))
        return 0
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

    /// 为非 SSH 传输绑定进度回调；返回的指针须在 fetch 完成前保持有效。
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
}
