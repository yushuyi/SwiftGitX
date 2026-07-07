//
//  Repository+pull.swift
//  SwiftGitX
//

import Foundation
import libgit2

extension Repository {
    /// 从远程拉取并合并到当前分支（fetch + merge）。
    public nonisolated func pull(
        remote: Remote? = nil,
        branchName: String? = nil,
        sshCredentials: SSHMemoryCredentials? = nil,
        httpCredentials: GitHTTPCredentials? = nil,
        connectionFetchURL: URL? = nil,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) {
        let currentBranch = try branch.current
        guard let resolvedRemote = remote ?? currentBranch.remote ?? self.remote["origin"] else {
            throw SwiftGitXError(
                code: .notFound, operation: .pull, category: .reference,
                message: "未找到远程仓库，请检查 .git/config 中的 remote 配置"
            )
        }

        let refspecs = branchName.map { Self.fetchRefspec(remoteName: resolvedRemote.name, branchName: $0) }
        try await fetch(
            remote: resolvedRemote,
            refspecs: refspecs.map { [$0] },
            sshCredentials: sshCredentials,
            httpCredentials: httpCredentials,
            connectionFetchURL: connectionFetchURL,
            transferProgressHandler: transferProgressHandler
        )

        let mergeBranch = try resolvePullMergeBranch(
            currentBranch: currentBranch,
            remote: resolvedRemote,
            branchName: branchName
        )
        try merge(branch: mergeBranch)
    }

    private func resolvePullMergeBranch(
        currentBranch: Branch,
        remote: Remote,
        branchName: String?
    ) throws(SwiftGitXError) -> Branch {
        if let branchName {
            let remoteBranchName: String
            if branchName.contains("/") {
                remoteBranchName = branchName
            } else {
                remoteBranchName = "\(remote.name)/\(branchName)"
            }
            return try branch.get(named: remoteBranchName, type: .remote)
        }

        if let upstream = currentBranch.upstream as? Branch, upstream.type == .remote {
            return try branch.get(named: upstream.name, type: .remote)
        }

        return try branch.get(named: "\(remote.name)/\(currentBranch.name)", type: .remote)
    }

    private static func fetchRefspec(remoteName: String, branchName: String) -> String {
        let shortName: String
        if branchName.hasPrefix("refs/heads/") {
            shortName = String(branchName.dropFirst("refs/heads/".count))
        } else if branchName.contains("/") {
            let parts = branchName.split(separator: "/", maxSplits: 1).map(String.init)
            shortName = parts.count == 2 ? parts[1] : branchName
        } else {
            shortName = branchName
        }
        return "refs/heads/\(shortName):refs/remotes/\(remoteName)/\(shortName)"
    }
}
