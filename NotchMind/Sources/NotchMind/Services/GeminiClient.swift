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
        let skill_name: String?
        let pain_point: String?
        let copy_ready_payloads: [CopyPayload]?
        let treasure_links: [TreasureLink]?
        let gotchas: [String]?
        let source_type: String?
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
        你是个人技能猎手与深度知识架构师，专门从互联网素材中挖掘用户能立刻拿去用的技能（Skill），拒绝劣质空泛概括。请深度拆解以下素材，严格返回 JSON，不要输出任何额外解释或 Markdown 代码块。

        核心信条：
        1. 必须提炼出可在 5 分钟内直接复制执行的 Prompt、脚本、命令或参数。做不到这点的不叫技能。
        2. Prompt、脚本、代码原文逐字录入，绝不改写、绝不缩写。
        3. 挖掘所有外链：帖子里提到的每一个工具、插件、仓库链接全部收录到 treasure_links，不可遗漏。
        4. 痛点与避坑：明确指出不学此技能前会在什么场景抓狂，以及版本限制或避坑点。

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

        JSON 字段规范：
        {
          "title": "精准中文标题（不超过36字，体现核心技法或结论）",
          "domain": "上述四选一",
          "ladder_level": "上述三选一",
          "skill_name": "技能/神器/技巧名（≤12字中文，如：Cursor高级Rules配置）",
          "pain_point": "解决的核心痛点（一句话直击抓狂场景，拒绝废话）",
          "one_line_essence": "高信息量核心结论（点出具体机理或事实）",
          "copy_ready_payloads": [
            {
              "type": "prompt|script|command|params|workflow",
              "label": "用户可读简明标签（如：审查Prompt原文）",
              "content": "用户可直接拷贝粘贴的完整原文（代码/Prompt/命令）",
              "source_note": "来源说明（如：推文原帖 / 评论区补充）"
            }
          ],
          "treasure_links": [
            {
              "title": "外链或工具名称",
              "url": "https://...",
              "why": "为什么值得收藏/解决什么问题"
            }
          ],
          "gotchas": ["小白实操避坑清单（版本约束/已知Bug/报错解法）"],
          "source_type": "x_post | github | blender_tutorial | general",
          "prerequisites": ["前置概念或适用场景（1-2条）"],
          "concept_breakdown": [
            {"term": "核心概念名", "explanation": "底层原理解释（40-80字）", "analogy": "生活或工程直觉类比"}
          ],
          "key_points": ["关键参数/核心机制1", "关键参数2"],
          "actionable_steps": ["实操步骤1（含具体路径/快捷键/命令）", "步骤2"],
          "project_optimizations": ["反哺个人项目的具体落地待办（怎么改/预期收益）"],
          "pitfalls": ["常见坑点或误区"],
          "self_check_qa": [
            {"question": "主动回忆自测题", "answer": "准确参考答案"}
          ],
          "copyable_snippets": ["备用可复用片段"],
          "further_exploration": ["下一步深挖方向"],
          "blender_script": "若涉及 3D/Blender 实操且可代码化，输出可直接在 Blender Scripting 运行的完整 Python (bpy) 脚本；否则设为 null"
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
                blenderScript: parsed.blender_script,
                skillName: parsed.skill_name,
                painPoint: parsed.pain_point,
                copyReadyPayloads: parsed.copy_ready_payloads ?? [],
                treasureLinks: parsed.treasure_links ?? [],
                gotchas: parsed.gotchas ?? [],
                sourceType: parsed.source_type
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
