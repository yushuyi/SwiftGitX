//
//  Repository+show.swift
//  SwiftGitX
//
//  Created by İbrahim Çetin on 23.11.2025.
//

import libgit2

extension Repository {
    /// Lookups an object in the repository by its ID.
    ///
    /// - Parameter id: The ID of the object.
    ///
    /// - Returns: The object with the specified ID.
    ///
    /// - Throws: `ObjectError.invalid` if the object is not found or an error occurs.
    ///
    /// The type of the object must be specified when calling this method.
    ///
    /// Look up a commit by its ID
    /// ```swift
    /// let commit: Commit = try repository.show(id: commitID)
    /// ```
    ///
    /// Look up a tag by its ID
    /// ```swift
    /// let tag: Tag = try repository.show(id: treeID)
    /// ```
    public func show<ObjectType: Object>(id: OID) throws(SwiftGitXError) -> ObjectType {
        try ObjectFactory.lookupObject(oid: id.raw, repositoryPointer: pointer) as ObjectType
    }

    /// 按十六进制前缀（4-40 位）查找对象。
    ///
    /// - Parameter hexPrefix: 对象 ID 的十六进制前缀（4-40 位，大小写不敏感）。
    /// - Returns: 匹配的对象；前缀歧义（多个对象共享同一前缀）时抛错。
    ///
    /// 直接走 ODB 前缀查找，**不要求对象可达**：dangling 提交（如 reset 后的旧提交）
    /// 也可引用，与真实 git 的短 SHA 语义一致。
    ///
    /// ```swift
    /// let commit: Commit = try repository.show(hexPrefix: "469241e7")
    /// ```
    public func show<ObjectType: Object>(hexPrefix: String) throws(SwiftGitXError) -> ObjectType {
        let lowered = hexPrefix.lowercased()
        // 4 = GIT_OID_MINPREFIXLEN；isHexDigit 是 Unicode 属性，需再限 ASCII
        guard (4...40).contains(lowered.count),
              lowered.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw SwiftGitXError(
                code: .invalid,
                category: .object,
                message: "无效的哈希前缀: \(hexPrefix)"
            )
        }

        var oid = git_oid()
        try git { git_oid_fromstrp(&oid, lowered) }

        return try ObjectFactory.lookupObject(
            oid: oid, length: lowered.count, repositoryPointer: pointer
        )
    }

    /// 按修订版本表达式查找对象。
    ///
    /// - Parameter revision: 修订版本表达式（`HEAD`、`HEAD~2`、`origin/main`、
    ///   `HEAD:<path>`、完整/短 SHA 等，交由 libgit2 `git_revparse_single` 解析）。
    /// - Returns: 表达式指向的对象。
    ///
    /// ```swift
    /// let blob: Blob = try repository.show(revision: "HEAD:README.md")
    /// ```
    public func show<ObjectType: Object>(revision: String) throws(SwiftGitXError) -> ObjectType {
        let object = try ObjectFactory.lookupObject(revision: revision, repositoryPointer: pointer)
        guard let typed = object as? ObjectType else {
            throw SwiftGitXError(
                code: .invalid,
                category: .object,
                message: "对象类型不匹配：期望 \(ObjectType.self)"
            )
        }
        return typed
    }
}
