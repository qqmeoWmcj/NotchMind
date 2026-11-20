import Foundation

public enum GeminiClient {
    public enum ClientError: LocalizedError {
        case missingAPIKey
        case httpError(Int, String)
        case emptyResponse
        case decodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "未配置 GEMINI_API_KEY（请在设置中填写）"
            case .httpError(let code, let body): return "Gemini HTTP \(code)：\(body.prefix(120))"
            case .emptyResponse: return "Gemini 返回空内容"
            case .decodeFailed(let detail): return "解析 Gemini JSON 失败：\(detail.prefix(120))"
            }
        }
    }

    private struct ExtractionPayload: Decodable {
        let title: String
        let domain: String
        let ladder_level: String?
        let one_line_essence: String
        let prerequisites: [String]?
        let concept_breakdown: [ConceptItem]?
        let key_points: [String]?
        let actionable_steps: [String]?
        let project_optimizations: [String]?
        let pitfalls: [String]?
        let self_check_qa: [QuizItem]?
        let copyable_snippets: [String]?
        let further_exploration: [String]?
        let blender_script: String?
    }

    private struct APIResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    public static func extractKnowledge(
        apiKey: String,
        model: String,
        source: String,
        titleHint: String,
        url: String,
        textContent: String,
        imageJPEG: Data? = nil,
        focusGoal: FocusGoal? = nil
    ) async throws -> KnowledgeEntry {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "your_gemini_api_key_here" else {
            throw ClientError.missingAPIKey
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)"
        guard let endpointURL = URL(string: endpoint) else { throw URLError(.badURL) }

        let goalBlock: String
        if let goal = focusGoal, goal.isConfigured {
            goalBlock = """
            用户当前学习目标：\(goal.title.isEmpty ? "未指定" : goal.title)
            用户关注关键词：\(goal.keywords.isEmpty ? "无" : goal.keywords.joined(separator: "、"))
            用户正在推进的项目/痛点背景：\(goal.projectContext.isEmpty ? "无" : goal.projectContext)
            """
        } else {
            goalBlock = "用户当前未设定特定项目背景，请仍从实战落地角度给出可直接应用到个人项目的优化手段。"
        }

        let prompt = """
        你是一个高密度、面向深度理解与实战落地的中文知识工程与学习教练助手（融合费曼学习法与主动回忆原理）。请深度拆解以下素材，严格返回 JSON，不要输出任何额外解释或 Markdown 代码块。

        严格禁止空泛总结（例如“该文章介绍了一些 Blender 技能”、“讲解了某工具的使用方法”这类毫无信息量的废话）。你必须提取出：
        1. 底层核心概念与直觉类比（让学习者真正理解“为什么有效”，而不是死记步骤）；
        2. 具体的技法、参数、节点/命令、操作路径与避坑点；
        3. 能够直接反哺到用户当前项目的可优化手段；
        4. 2-3 道高质量的主动回忆自测题（考察原理理解与场景应用，禁止无脑复述标题）。

        \(goalBlock)

        可选领域 domain（必须四选一）：
        - 01-LLM与新模型
        - 02-AI学习与教程
        - 03-AI创作与3D工具
        - 04-行业深度认知

        可选层级 ladder_level（必须三选一）：
        - L1基础教程
        - L2工具与AI联动
        - L3一站式自动化

        JSON 字段：
        {
          "title": "精准中文标题（不超过36字，体现核心技法或结论）",
          "domain": "上述四选一",
          "ladder_level": "上述三选一",
          "one_line_essence": "高信息量核心结论（不超过100字，必须点出具体方法/机制/效果，禁止套话）",
          "prerequisites": ["学习本内容前建议了解的前置概念或适用场景（1-2条）"],
          "concept_breakdown": [
            {"term": "核心概念/术语名", "explanation": "用精准但易懂的语言解释底层原理（40-80字）", "analogy": "一句生活或工程类比帮助直觉记忆（可选）"}
          ],
          "key_points": ["具体知识点/关键参数/核心机制1", "具体知识点2", "具体知识点3"],
          "actionable_steps": ["可直接照做的实操步骤1（含具体菜单/节点/快捷键/命令）", "实操步骤2", "实操步骤3"],
          "project_optimizations": ["反哺当前项目的具体可优化手段1（说明改哪里、怎么改、预期收益）", "反哺优化手段2"],
          "pitfalls": ["常见坑点、误区或边界条件（1-2条）"],
          "self_check_qa": [
            {"question": "检验是否真懂的原理或场景应用题", "answer": "简洁准确的参考答案（30-80字）"}
          ],
          "copyable_snippets": ["可直接复用的 Prompt、命令、节点配方或代码片段（最多2条）"],
          "further_exploration": ["顺着这个知识点下一步值得深挖的方向或关联主题（1-2条）"],
          "blender_script": "若内容涉及 3D/Blender（建模、几何节点、材质Shader、渲染灯光、修改器、动画等），请生成一段可直接在 Blender Scripting 运行生效的 Python (bpy) 实操参数脚本（含 import bpy、安全检查与参数设置）；若完全非 3D 场景则为 null"
        }

        来源：\(source)
        原始标题：\(titleHint)
        链接：\(url.isEmpty ? "无" : url)
        素材内容：
        \(textContent.prefix(8000))
        """

        var parts: [[String: Any]] = [["text": prompt]]
        if let jpeg = imageJPEG {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": jpeg.base64EncodedString(),
                ],
            ])
        }

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "temperature": 0.25,
                "responseMimeType": "application/json",
            ],
        ]

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpError(http.statusCode, msg)
        }

        let apiResp = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let rawText = apiResp.candidates?.first?.content?.parts?.first?.text,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ClientError.emptyResponse
        }

        let jsonString = stripCodeFence(rawText)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClientError.decodeFailed(rawText)
        }

        do {
            let parsed = try JSONDecoder().decode(ExtractionPayload.self, from: jsonData)
            let goalTitle = focusGoal?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return KnowledgeEntry(
                title: parsed.title.isEmpty ? titleHint : parsed.title,
                source: source,
                url: url,
                domain: parsed.domain,
                ladderLevel: parsed.ladder_level ?? "L1基础教程",
                matchedProject: nil,
                focusGoal: (goalTitle?.isEmpty == false) ? goalTitle : nil,
                oneLineEssence: parsed.one_line_essence,
                prerequisites: parsed.prerequisites ?? [],
                conceptBreakdown: parsed.concept_breakdown ?? [],
                keyPoints: parsed.key_points ?? [],
                actionableSteps: parsed.actionable_steps ?? [],
                projectOptimizations: parsed.project_optimizations ?? [],
                pitfalls: parsed.pitfalls ?? [],
                selfCheckQA: parsed.self_check_qa ?? [],
                copyableSnippets: parsed.copyable_snippets ?? [],
                furtherExploration: parsed.further_exploration ?? [],
                blenderScript: parsed.blender_script
            )
        } catch {
            throw ClientError.decodeFailed("\(error.localizedDescription) | \(jsonString)")
        }
    }

    private static func stripCodeFence(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
