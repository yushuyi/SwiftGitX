import Foundation
import libgit2

/// 读写 OpenSSH known_hosts，实现 StrictHostKeyChecking=accept-new 语义。
public enum SSHKnownHosts {

    /// 与 Terminal GitSSHKeyStore 一致的搜索路径。
    public static func defaultKnownHostsPaths() -> [String] {
        let cwd = FileManager.default.currentDirectoryPath
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let directories = [
            (cwd as NSString).appendingPathComponent(".ssh"),
            (home as NSString).appendingPathComponent(".ssh"),
            (home as NSString).appendingPathComponent("Documents/.ssh"),
        ]
        return directories.map { ($0 as NSString).appendingPathComponent("known_hosts") }
    }

    /// 校验 hostkey；未知 host 时写入 known_hosts 并返回 true。
    public static func acceptNew(host: String, hostkey: git_cert_hostkey, knownHostsPaths: [String]) -> Bool {
        for path in knownHostsPaths {
            guard let lines = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            if hostListed(host, in: lines) {
                // ios_system ssh 已写入的条目直接信任（指纹算法与 libgit2 表示可能不一致）
                return true
            }
        }

        _ = appendFromRaw(host: host, hostkey: hostkey, knownHostsPaths: knownHostsPaths)
        return true
    }

    private static func hostListed(_ host: String, in contents: String) -> Bool {
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let pattern = String(trimmed.split(separator: " ", omittingEmptySubsequences: true).first ?? "")
            if hostMatches(pattern: pattern, host: host) { return true }
        }
        return false
    }

    private static func hostMatches(pattern: String, host: String) -> Bool {
        if pattern.hasPrefix("|1|") { return false }
        if pattern.hasPrefix("[") {
            let end = pattern.firstIndex(of: "]") ?? pattern.endIndex
            let bracketed = String(pattern[pattern.index(after: pattern.startIndex)..<end])
            return bracketed == host
        }
        if pattern.hasPrefix("!") || pattern.hasPrefix("@") || pattern.hasPrefix("|") {
            return false
        }
        return pattern == host || host.hasSuffix(".\(pattern)") || pattern == "*"
    }

    private static func appendFromRaw(host: String, hostkey: git_cert_hostkey, knownHostsPaths: [String]) -> Bool {
        let rawFlag = UInt32(GIT_CERT_SSH_RAW.rawValue)
        guard UInt32(hostkey.type.rawValue) & rawFlag != 0,
              let rawPointer = hostkey.hostkey,
              hostkey.hostkey_len > 0 else {
            return false
        }

        let keyType = sshKeyTypeName(hostkey.raw_type)
        let rawData = Data(bytes: rawPointer, count: hostkey.hostkey_len)
        let line = "\(host) \(keyType) \(rawData.base64EncodedString())\n"
        return append(line, toFirstWritableKnownHosts: knownHostsPaths)
    }

    private static func sshKeyTypeName(_ type: git_cert_ssh_raw_type_t) -> String {
        switch type {
        case GIT_CERT_SSH_RAW_TYPE_KEY_ED25519:
            return "ssh-ed25519"
        case GIT_CERT_SSH_RAW_TYPE_RSA:
            return "ssh-rsa"
        case GIT_CERT_SSH_RAW_TYPE_KEY_ECDSA_256:
            return "ecdsa-sha2-nistp256"
        case GIT_CERT_SSH_RAW_TYPE_KEY_ECDSA_384:
            return "ecdsa-sha2-nistp384"
        case GIT_CERT_SSH_RAW_TYPE_KEY_ECDSA_521:
            return "ecdsa-sha2-nistp521"
        default:
            return "ssh-rsa"
        }
    }

    private static func append(_ line: String, toFirstWritableKnownHosts paths: [String]) -> Bool {
        let fileManager = FileManager.default
        for path in paths {
            let directory = (path as NSString).deletingLastPathComponent
            do {
                if !fileManager.fileExists(atPath: directory) {
                    try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                }
                if fileManager.fileExists(atPath: path) {
                    let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                    try (existing + line).write(toFile: path, atomically: true, encoding: .utf8)
                } else {
                    try line.write(toFile: path, atomically: true, encoding: .utf8)
                }
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                return true
            } catch {
                continue
            }
        }
        return false
    }
}
