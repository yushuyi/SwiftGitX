//
//  RemoteCollection.swift
//  SwiftGitX
//
//  Created by İbrahim Çetin on 24.11.2025.
//

import Foundation
import libgit2

/// A collection of remotes and their operations.
public struct RemoteCollection: Sequence {
    private let repositoryPointer: OpaquePointer

    init(repositoryPointer: OpaquePointer) {
        self.repositoryPointer = repositoryPointer
    }

    /// Retrieves a remote by its name.
    ///
    /// - Parameter name: The name of the remote.
    ///
    /// - Returns: The remote with the specified name, or `nil` if it doesn't exist.
    public subscript(name: String) -> Remote? {
        try? get(named: name)
    }

    /// Returns a remote by name.
    ///
    /// - Parameter name: The name of the remote.
    ///
    /// - Returns: The remote with the specified name.
    public func get(named name: String) throws(SwiftGitXError) -> Remote {
        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: name, repositoryPointer: repositoryPointer)
        defer { git_remote_free(remotePointer) }

        return try Remote(pointer: remotePointer)
    }

    /// Returns a list of remotes.
    ///
    /// - Returns: An array of remotes.
    ///
    /// If you want to iterate over the remotes, you can use the `makeIterator()` method.
    /// Iterator continues to the next remote even if an error occurs while getting the remote.
    public func list() throws(SwiftGitXError) -> [Remote] {
        let remotes = try remoteNames.map { (remoteName) throws(SwiftGitXError) -> Remote in
            try get(named: remoteName)
        }

        return remotes
    }

    /// Adds a new remote to the repository.
    ///
    /// - Parameters:
    ///   - name: The name of the remote.
    ///   - url: The URL of the remote.
    ///
    /// - Returns: The remote that was added.
    @discardableResult
    public func add(named name: String, at url: URL) throws(SwiftGitXError) -> Remote {
        let remotePointer = try git(operation: .remoteAdd) {
            var remotePointer: OpaquePointer?
            let status = git_remote_create(&remotePointer, repositoryPointer, name, url.absoluteString)
            return (remotePointer, status)
        }
        defer { git_remote_free(remotePointer) }

        return try Remote(pointer: remotePointer)
    }

    /// Remove a remote from the repository.
    ///
    /// - Parameter remote: The remote to remove.
    public func remove(_ remote: Remote) throws(SwiftGitXError) {
        try git(operation: .remoteRemove) {
            git_remote_delete(repositoryPointer, remote.name)
        }
    }

    /// 更新远程 fetch URL（对应 `git remote set-url`）。
    public func setURL(named name: String, url: URL) throws(SwiftGitXError) {
        try git(operation: .remoteSetURL) {
            git_remote_set_url(repositoryPointer, name, url.absoluteString)
        }
    }

    /// 更新远程 push URL（对应 `git remote set-url --push`）。
    public func setPushURL(named name: String, url: URL) throws(SwiftGitXError) {
        try git(operation: .remoteSetURL) {
            git_remote_set_pushurl(repositoryPointer, name, url.absoluteString)
        }
    }

    /// 读取远程 fetch URL 字符串。
    public func urlString(named name: String) throws(SwiftGitXError) -> String {
        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: name, repositoryPointer: repositoryPointer)
        defer { git_remote_free(remotePointer) }
        guard let url = git_remote_url(remotePointer) else {
            throw SwiftGitXError(code: .notFound, category: .reference, message: "Remote '\(name)' 无 fetch URL")
        }
        return String(cString: url)
    }

    /// 读取远程 push URL；未单独配置时回退 fetch URL。
    public func pushURLString(named name: String) throws(SwiftGitXError) -> String {
        let remotePointer = try ReferenceFactory.lookupRemotePointer(name: name, repositoryPointer: repositoryPointer)
        defer { git_remote_free(remotePointer) }
        if let pushURL = git_remote_pushurl(remotePointer) {
            return String(cString: pushURL)
        }
        return try urlString(named: name)
    }

    /// 重命名远程（对应 `git remote rename`）。
    public func rename(_ remote: Remote, to newName: String) throws(SwiftGitXError) {
        try git(operation: .remoteRename) {
            var problems = git_strarray()
            defer { git_strarray_free(&problems) }
            return git_remote_rename(&problems, repositoryPointer, remote.name, newName)
        }
    }

    public func makeIterator() -> RemoteIterator {
        RemoteIterator(remoteNames: (try? remoteNames) ?? [], repositoryPointer: repositoryPointer)
    }

    private var remoteNames: [String] {
        get throws(SwiftGitXError) {
            // Create a list to store the remote names
            var array = git_strarray()
            defer { git_strarray_free(&array) }

            // Get the remote names
            try git(operation: .remoteList) {
                git_remote_list(&array, repositoryPointer)
            }

            // Create a list to store the remote names
            var remoteNames = [String]()

            // Convert raw remote names to Swift strings
            for index in 0..<array.count {
                guard let rawRemoteName = array.strings.advanced(by: index).pointee
                else {
                    throw SwiftGitXError(
                        code: .notFound, category: .invalid,
                        message: "Failed to get remote name at index \(index)"
                    )
                }

                let remoteName = String(cString: rawRemoteName)
                remoteNames.append(remoteName)
            }

            return remoteNames
        }
    }
}

extension SwiftGitXError.Operation {
    public static let remoteList = Self(rawValue: "remoteList")
    public static let remoteAdd = Self(rawValue: "remoteAdd")
    public static let remoteRemove = Self(rawValue: "remoteRemove")
    public static let remoteSetURL = Self(rawValue: "remoteSetURL")
    public static let remoteRename = Self(rawValue: "remoteRename")
}
