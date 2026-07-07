//
//  GitHTTPCredentials.swift
//  SwiftGitX
//

import Foundation

/// HTTPS 用户名/密码凭据，供 libgit2 fetch/clone/pull/push 使用。
public struct GitHTTPCredentials: Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// GitHub Personal Access Token 的标准 libgit2 用户名。
    public static func githubPAT(_ token: String) -> GitHTTPCredentials {
        GitHTTPCredentials(username: "x-access-token", password: token)
    }
}
