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
        guard lowered.count >= 4, lowered.allSatisfy(\.isHexDigit) else {
            throw SwiftGitXError(
                code: .error,
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
}
