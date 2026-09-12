import Foundation
import AppKit

// MARK: - 反馈类型

/// 反馈类型（与服务端 cloud/feedback-worker/src/worker.js 的 TYPES 一致）
enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug
    case idea
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bug: return "🐞 Bug"
        case .idea: return "💡 功能建议"
        case .other: return "💬 其他"
        }
    }
}

// MARK: - 附件

/// 反馈附件（截图图片，⌘V 粘贴或拖拽进来）
struct FeedbackAttachment: Identifiable {
    let id = UUID()
    let name: String
    let mime: String
    let data: Data
    let preview: NSImage?

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

// MARK: - 环境信息

/// 随反馈自动附带的环境信息（仅版本/系统等，不含任何用户数据）
struct FeedbackEnvironment {
    let appVersion: String
    let channel: String // dmg | appstore | dev
    let osVersion: String
    let locale: String

    var channelLabel: String {
        switch channel {
        case "appstore": return "App Store"
        case "dev": return "开发版"
        default: return "官网 DMG"
        }
    }

    static func collect() -> FeedbackEnvironment {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? ""
        let version = build.isEmpty ? short : "\(short) (\(build))"

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        var channel = "dmg"
        if bundleID.contains(".dev") {
            channel = "dev"
        } else if (Bundle.main.appStoreReceiptURL?.lastPathComponent ?? "") == "sandboxReceipt" {
            channel = "appstore"
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = " (ARM)"
        #else
        let arch = " (Intel)"
        #endif
        let patch = os.patchVersion > 0 ? ".\(os.patchVersion)" : ""

        return FeedbackEnvironment(
            appVersion: version,
            channel: channel,
            osVersion: "macOS \(os.majorVersion).\(os.minorVersion)\(patch)\(arch)",
            locale: String(Locale.current.identifier.prefix(12))
        )
    }
}

// MARK: - 错误

struct FeedbackError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - 服务

/// 用户反馈提交服务。
/// 后端：cloud/feedback-worker（Cloudflare Worker + D1 + R2，域名 feedback.drel.app，
/// 国内网络 *.workers.dev 不可达，必须走自定义域名）；提交成功后开发者手机实时收到推送。
final class FeedbackService {
    static let shared = FeedbackService()

    static let endpoint = URL(string: "https://feedback.drel.app/feedback")!

    /// 与服务端约束一致
    static let maxTextLength = 5000
    static let maxAttachments = 3
    static let maxAttachmentBytes = 5 * 1024 * 1024

    /// 网络不可用时的邮件降级收件箱
    static let fallbackEmail = "dyyz1993@qq.com"

    /// 提交反馈，成功返回服务端反馈编号。
    /// logs：可选诊断日志尾部（用户勾选"附带运行日志"时传入，App 端已按打点规范脱敏）
    func submit(
        kind: FeedbackKind,
        text: String,
        contact: String,
        attachments: [FeedbackAttachment],
        entry: String,
        logs: String = ""
    ) async throws -> Int {
        let env = FeedbackEnvironment.collect()
        var payload: [String: Any] = [
            "type": kind.rawValue,
            "text": String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextLength)),
            "contact": contact,
            "entry": entry,
            "appVersion": env.appVersion,
            "channel": env.channel,
            "osVersion": env.osVersion,
            "locale": env.locale,
            "attachments": attachments.map {
                ["name": $0.name, "mime": $0.mime, "data": $0.data.base64EncodedString()]
            },
        ]
        if !logs.isEmpty {
            payload["logs"] = String(logs.prefix(32 * 1024))
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeedbackError(message: "服务响应异常 (\(status))")
        }
        if let ok = json["ok"] as? Bool, ok, let id = json["id"] as? Int {
            return id
        }
        if status == 429 {
            throw FeedbackError(message: "发送太频繁了，请 2 分钟后再试")
        }
        throw FeedbackError(message: (json["error"] as? String) ?? "提交失败 (\(status))")
    }

    /// 网络不可用时的邮件降级链接（不携带截图附件，正文带提示）
    static func mailtoURL(kind: FeedbackKind, text: String, contact: String) -> URL {
        let env = FeedbackEnvironment.collect()
        let subject = "[QuiteNote 反馈] \(kind.label) \(env.appVersion) \(env.channel)"
        var body = text
        if !text.isEmpty { body += "\n\n---\n" }
        body += "版本：\(env.appVersion)（\(env.channel)）\n系统：\(env.osVersion)\n联系方式：\(contact.isEmpty ? "未填写" : contact)"

        let allowed = CharacterSet.urlQueryAllowed
        let enc = { (s: String) -> String in s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let encodedBody = enc(body.replacingOccurrences(of: "\n", with: "\r\n"))
        let urlString = "mailto:\(fallbackEmail)?subject=\(enc(subject))&body=\(encodedBody)"
        return URL(string: urlString) ?? URL(string: "mailto:\(fallbackEmail)")!
    }
}
