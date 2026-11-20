import Foundation

public struct FetchedSource: Sendable {
    public let source: String
    public let title: String
    public let url: String
    public let content: String
}

public enum BilibiliFetcher {
    private struct ViewResponse: Decodable {
        let code: Int
        let data: VideoData?
    }

    private struct VideoData: Decodable {
        let bvid: String?
        let title: String?
        let desc: String?
        let tname: String?
        let owner: Owner?
        let stat: Stat?
        let pages: [Page]?
    }

    private struct Owner: Decodable { let name: String? }
    private struct Stat: Decodable { let view: Int?; let like: Int?; let favorite: Int? }
    private struct Page: Decodable { let part: String? }

    public static func fetch(urlString: String) async throws -> FetchedSource {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bvid = URLCanonicalizer.extractBVID(from: cleaned) {
            return try await fetchBilibili(bvid: bvid)
        }
        return try await fetchWebPage(urlString: cleaned)
    }

    public static func fetchBilibili(bvid: String) async throws -> FetchedSource {
        let canonicalURL = "https://www.bilibili.com/video/\(bvid)"
        guard let apiURL = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: apiURL)
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")

        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(ViewResponse.self, from: data)
        guard decoded.code == 0, let v = decoded.data else {
            return FetchedSource(
                source: "B站视频",
                title: "B站视频 \(bvid)",
                url: canonicalURL,
                content: "BVID: \(bvid)\nURL: \(canonicalURL)"
            )
        }

        var parts: [String] = []
        if let title = v.title, !title.isEmpty { parts.append("标题：\(title)") }
        if let author = v.owner?.name, !author.isEmpty { parts.append("UP主：\(author)") }
        if let tname = v.tname, !tname.isEmpty { parts.append("分区：\(tname)") }
        if let stat = v.stat {
            parts.append("数据：播放 \(stat.view ?? 0) / 点赞 \(stat.like ?? 0) / 收藏 \(stat.favorite ?? 0)")
        }
        if let desc = v.desc, !desc.isEmpty {
            parts.append("简介：\n\(desc)")
        }
        if let pages = v.pages, pages.count > 1 {
            let names = pages.prefix(12).compactMap(\.part).joined(separator: " / ")
            if !names.isEmpty { parts.append("分P目录：\(names)") }
        }

        return FetchedSource(
            source: "B站视频",
            title: v.title ?? "B站视频 \(bvid)",
            url: canonicalURL,
            content: parts.joined(separator: "\n")
        )
    }

    public static func fetchWebPage(urlString: String) async throws -> FetchedSource {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let title = extractFirstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#) ?? (url.host ?? urlString)
        let desc = extractFirstMatch(
            in: html,
            pattern: #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#
        ) ?? ""
        let plainText = stripHTML(html).prefix(3500)
        let body = [
            "网页标题：\(title)",
            desc.isEmpty ? nil : "摘要：\(desc)",
            "正文节选：\n\(plainText)",
        ].compactMap { $0 }.joined(separator: "\n\n")

        return FetchedSource(
            source: url.host ?? "网页链接",
            title: title,
            url: urlString,
            content: body
        )
    }

    private static func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[r].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
