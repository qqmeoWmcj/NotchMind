SYSTEM_INSTRUCTION = """你是一位深耕 AI 行业、擅长输出「高密度行业认知」的个人创作者与总编。
你的核心原则：
1. 拒绝教人点按钮式的工具搬运，聚焦真正有价值的行业认知、架构演进、反共识观点与商业/个人落地启示。
2. 彻底去 AI 味：禁止使用「赋能、抓手、颠覆、众所周知、总而言之、不仅如此」等空洞套话；用克制、犀利、像真人在跟朋友聊天复盘的口吻写作。
3. 所有分析必须基于提供的原始素材，不编造不存在的数据或发布细节。
4. 严格遵循指定的 JSON Schema 输出。"""


def build_selection_prompt(items_text: str, top_k: int) -> str:
    return (
        f"以下是今天抓取到的 AI 行业原始热点列表（带 0 开始的索引编号）。\n"
        f"请从中挑选出最具个人内容创作价值、最有行业认知深度的 {top_k} 个话题（避免重复主题）。\n\n"
        f"{items_text}"
    )


def build_analysis_prompt(source: str, title: str, url: str, summary: str) -> str:
    return (
        f"请深度拆解下面这条 AI 热点，并生成「小红书图文」「短视频口播脚本」「深度长文大纲」三套可直接二次加工的草稿：\n\n"
        f"- 来源：{source}\n"
        f"- 标题：{title}\n"
        f"- 链接：{url}\n"
        f"- 摘要：{summary}\n\n"
        f"要求：\n"
        f"1. short_slug 简短清晰（不超过18字，不含斜杠/特殊符号），用于 Obsidian 文件名。\n"
        f"2. deep_insight 必须给出具体、犀利、有判断力的行业认知，不要泛泛而谈。\n"
        f"3. 口播脚本请模仿高认知科普博主的节奏，包含【黄金3秒钩子】和【画面/PPT提示】。\n"
    )
