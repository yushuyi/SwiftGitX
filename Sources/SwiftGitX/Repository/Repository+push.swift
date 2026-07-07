//
//  Repository+push.swift
//  SwiftGitX
//
//  Created by İbrahim Çetin on 23.11.2025.
//

import Foundation
import libgit2

extension Repository {
    /// Push changes of the current branch to the remote.
    ///
    /// - Parameters:
    ///   - remote: The remote to push the changes to.
    ///   - createsRefspec: If `true`, automatically creates a push refspec when none exists.
    ///     If `false`, throws an error when no matching refspec is found. Defaults to `true`.
    ///
    /// This method uses the configured refspecs to push the changes to the remote.
    ///
    /// If the remote is not specified, the upstream of the current branch is used
    /// and if the upstream branch is not found, the `origin` remote is used.
    // TODO: Implement options of these methods
    public nonisolated func push(
        remote: Remote? = nil,
        createsRefspec: Bool = true,
        sshCredentials: SSHMemoryCredentials? = nil,
        httpCredentials: GitHTTPCredentials? = nil,
        connectionFetchURL: URL? = nil,
        connectionPushURL: URL? = nil,
        transferProgressHandler: TransferProgressHandler? = nil
    ) async throws(SwiftGitXError) {
        // Get the current branch or throw an error if HEAD is detached
        let currentBranch = try branch.current

        // Get the remote or throw an error if not found
        guard let remote = remote ?? currentBranch.remote ?? self.remote["origin"] else {
            throw SwiftGitXError(code: .notFound, category: .reference, message: "Remote not found")
        }

        // Ensure a push refspec exists for the current branch
        if try !hasPushRefspec(for: currentBranch, remote: remote) {
            if createsRefspec {
                // Add a push refspec for the current branch if not exists
                try addPushRefspec(for: currentBranch, remote: remote)
            } else {
                throw SwiftGitXError(
                    code: .notFound, operation: .push, category: .reference,
                    message: "No push refspec configured for branch '\(currentBranch.name)' on remote '\(remote.name)'"
                )
            }
        }

        // Lookup the remote
        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: remote.name, repositoryPointer: pointer)
        defer { git_remote_free(remotePointer) }

        if connectionFetchURL != nil || connectionPushURL != nil {
            try GitRemoteInstanceURL.apply(
                fetchURL: connectionFetchURL,
                pushURL: connectionPushURL,
                to: remotePointer
            )
        }

        let networkContext: GitNetworkContext?
        var plainProgressPointer: UnsafeMutablePointer<TransferProgressHandler>?
        var pushOptions: git_push_options?

        if GitNetworkCallbackBinder.needsCustomCallbacks(
            sshCredentials: sshCredentials,
            httpCredentials: httpCredentials,
            progressHandler: transferProgressHandler
        ) {
            var options = git_push_options()
            git_push_options_init(&options, UInt32(GIT_PUSH_OPTIONS_VERSION))

            let bound = GitNetworkCallbackBinder.bind(
                sshCredentials: sshCredentials,
                httpCredentials: httpCredentials,
                progressHandler: transferProgressHandler,
                to: &options.callbacks
            )
            networkContext = bound.context
            plainProgressPointer = bound.plainProgressPointer
            pushOptions = options
        } else {
            networkContext = nil
        }
        defer { plainProgressPointer?.deallocate() }
        _ = networkContext

        // Perform the push operation using configured refspecs
        try git(operation: .push) {
            if var pushOptions {
                return git_remote_push(remotePointer, nil, &pushOptions)
            }
            return git_remote_push(remotePointer, nil, nil)
        }
    }

    // MARK: - Private Helpers

    /// Checks if a push refspec is configured for the given branch on the remote.
    ///
    /// - Parameters:
    ///   - branch: The branch to check.
    ///   - remote: The remote to check.
    /// - Returns: `true` if a matching push refspec exists, `false` otherwise.
    /// - Throws: `SwiftGitXError` if the remote lookup fails.
    private func hasPushRefspec(for branch: Branch, remote: Remote) throws(SwiftGitXError) -> Bool {
        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: remote.name, repositoryPointer: pointer)
        defer { git_remote_free(remotePointer) }

        let refspecCount = git_remote_refspec_count(remotePointer)

        for index in 0..<refspecCount {
            guard let refspec = git_remote_get_refspec(remotePointer, index) else { continue }

            let isPushRefspec = git_refspec_direction(refspec) == GIT_DIRECTION_PUSH
            let matchesBranch = git_refspec_src_matches(refspec, branch.fullName) == 1

            if isPushRefspec && matchesBranch {
                return true
            }
        }

        return false
    }

    /// Adds a push refspec for the given branch on the remote.
    ///
    /// - Parameters:
    ///   - branch: The branch to add the refspec for.
    ///   - remote: The remote to add the refspec to.
    private func addPushRefspec(for branch: Branch, remote: Remote) throws(SwiftGitXError) {
        let refspec = "\(branch.fullName):\(branch.fullName)"

        try git(operation: .push) {
            git_remote_add_push(pointer, remote.name, refspec)
        }
    }
}
