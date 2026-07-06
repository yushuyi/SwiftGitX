//
//  Repository+checkout.swift
//  SwiftGitX
//
//  Created by İbrahim Çetin on 28.11.2025.
//

import libgit2

extension Repository {
    // TODO: Implement checkout options as parameter

    /// Checks out the tree of the given reference to the working directory.
    ///
    /// - Parameter reference: The reference to checkout.
    ///
    /// - Important: This method updates the working directory files to match the state of the reference.
    /// It does not update HEAD. Use `switch(to:)` methods to update the HEAD reference after checkout.
    ///
    /// - SeeAlso: `switch(to:)`
    ///
    /// ### Example
    /// ```swift
    /// let branch = try repository.branch.get(named: "main")
    /// try repository.checkout(to: branch)
    /// ```
    public func checkout(to reference: any Reference) throws(SwiftGitXError) {
        try checkout(commitID: reference.target.id)
    }

    /// Checks out the tree of the given commit to the working directory.
    ///
    /// - Parameter commit: The commit to checkout.
    ///
    /// - Important: This method updates the working directory files to match the state of the given commit.
    /// It does not update HEAD. Use `switch(to:)-` methods to update the HEAD reference after checkout.
    ///
    /// - SeeAlso: `switch(to:)`
    ///
    /// ### Example
    /// ```swift
    /// let commit = try repository.log().first!
    /// try repository.checkout(to: commit)
    ///
    public func checkout(to commit: Commit) throws(SwiftGitXError) {
        try checkout(commitID: commit.id)
    }

    /// Checks out the tree of the given commit ID to the working directory.
    ///
    /// - Parameter commitID: The OID of the commit to checkout.
    ///
    /// This method updates the working directory files to match the state of the given commit.
    /// It does not update HEAD. Use ``switch`` methods to update the HEAD reference after checkout.
    /// 从指定提交检出部分路径到索引与工作区（等同 `git checkout <rev> -- <paths>`）。
    public func checkout(
        from commit: Commit,
        paths: [String],
        updateIndex: Bool = true
    ) throws(SwiftGitXError) {
        let commitPointer = try ObjectFactory.lookupObjectPointer(
            oid: commit.id.raw,
            type: GIT_OBJECT_COMMIT,
            repositoryPointer: pointer
        )
        defer { git_object_free(commitPointer) }

        var strategy: CheckoutStrategy = [.force, .disablePathSpecMatch]
        if !updateIndex {
            strategy.insert(.notUpdateIndex)
        }

        let options = CheckoutOptions(strategy: strategy, paths: paths)
        try options.withGitCheckoutOptions { (gitCheckoutOptions) throws(SwiftGitXError) -> Void in
            var opts = gitCheckoutOptions
            try git(operation: .checkout) {
                git_checkout_tree(pointer, commitPointer, &opts)
            }
        }
    }

    private func checkout(commitID: OID) throws(SwiftGitXError) {
        // Lookup the commit
        let commitPointer = try ObjectFactory.lookupObjectPointer(
            oid: commitID.raw,
            type: GIT_OBJECT_COMMIT,
            repositoryPointer: pointer
        )
        defer { git_object_free(commitPointer) }

        // Initialize checkout options
        var options = git_checkout_options()
        git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))

        options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        // Perform the checkout operation
        try git(operation: .checkout) {
            git_checkout_tree(pointer, commitPointer, &options)
        }
    }
}
