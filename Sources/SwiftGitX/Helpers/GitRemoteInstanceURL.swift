//
//  GitRemoteInstanceURL.swift
//  SwiftGitX
//

import Foundation
import libgit2

/// 仅修改内存中的 remote 实例 URL，不写回 .git/config。
enum GitRemoteInstanceURL {

    static func apply(
        fetchURL: URL? = nil,
        pushURL: URL? = nil,
        to remotePointer: OpaquePointer
    ) throws(SwiftGitXError) {
        if let fetchURL {
            try git(operation: .remoteSetURL) {
                git_remote_set_instance_url(remotePointer, fetchURL.absoluteString)
            }
        }
        if let pushURL {
            try git(operation: .remoteSetURL) {
                git_remote_set_instance_pushurl(remotePointer, pushURL.absoluteString)
            }
        }
    }
}
