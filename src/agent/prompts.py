from __future__ import annotations

from src.models import DOMAINS, LADDER_LEVELS

SYSTEM_INSTRUCTION = """你是个人技能猎手（Skill Hunter），专门从互联网素材与视频画面中挖掘用户能立刻拿去用的技能（Skill）。

核心信条：
1. 每一条技能，用户必须能在 5 分钟内直接复制并运行生效。做不到这点的不叫技能，叫废话。
2. Prompt、脚本、命令、参数配方——这些是用户真正要的原始载荷。逐字录入原文（放入 copy_ready_payloads），不改写、不缩写、不概括。
3. 外链是宝藏：帖子里提到的每一个工具、插件、GitHub 仓库链接都要挖出来（放入 treasure_links），一条都不能漏。
4. 彻底去 AI 味：禁止使用「赋能、抓手、颠覆、众所周知、未来可期」等空话；用克制、直接、像资深玩家笔记一样的语言输出。
5. 忠实于素材：所有提取必须忠实于提供的文本、音频或画面，不编造未出现的参数、工具名或数据。
6. 严格遵循指定的 JSON Schema 输出。"""


def detect_source_type(source: str = "", url: str = "", text: str = "") -> str:
    combined = f"{source} {url} {text[:300]}".lower()
    if any(k in combined for k in ("x.com", "twitter.com", "t.co", "推特", "tweet")):
        return "x_post"
    if any(k in combined for k in ("github.com", "gitee.com", "git repository")):
        return "github"
    if any(k in combined for k in ("blender", "bpy", "3d建模", "着色器", "cycles", "eevee", "几何节点")):
        return "blender_tutorial"
    return "general"


def build_selection_prompt(items_text: str, top_k: int) -> str:
    return (
        f"以下是今天抓取到的 AI 行业原始素材列表（带 0 开始的索引编号）。\n"
        f"请从中挑选出最具实操技能价值、Prompt 灵感、开源神器或认知突破的 {top_k} 个话题（避免重复主题）。\n\n"
        f"{items_text}"
    )


def build_knowledge_prompt(
    *,
    source: str,
    title: str = "",
    url: str = "",
    text: str = "",
    project_names: list[str] | None = None,
    has_media: bool = False,
) -> str:
    stype = detect_source_type(source, url, text)
    domains_block = "\n".join(f"- {d}" for d in DOMAINS)
    ladders_block = (
        f"- {LADDER_LEVELS[0]}：基础概念、入门技巧、单点 Prompt 或基础认知\n"
        f"- {LADDER_LEVELS[1]}：把 AI / MCP / 插件 / 脚本接入具体工具或创作工作流\n"
        f"- {LADDER_LEVELS[2]}：端到端一站式自动化流水线、多步骤编排或开箱即用闭环"
    )

    if project_names:
        projects_hint = (
            "当前 05-项目孵化池 中已立项的项目列表："
            + "、".join(project_names)
            + "。\n"
            "仅当素材能作为上述某个项目的实操参考时，将 matched_project 设为精确项目名，"
            "并在 project_optimizations 中给出明确可在项目中落地的待办；否则必须设为 null。"
        )
    else:
        projects_hint = "当前没有待匹配项目，matched_project 请直接返回 null。"

    media_hint = (
        "\n注意：随附了画面截图，请优先结合看到的界面节点、参数滑杆、代码、快捷键进行提取。"
        if has_media
        else ""
    )

    guidance = ""
    if stype == "x_post":
        guidance = (
            "【X 帖子/评论区提取重点】：\n"
            "1. skill_name：提取该推文教的核心技能名（≤12字，如「Cursor自定义Rules加速」）。\n"
            "2. pain_point：说明不会这个技巧前，创作者在什么场景抓狂（一句话）。\n"
            "3. copy_ready_payloads：若帖子包含 Prompt 原文或工作流，完整逐字收录，不缩写；评论区补充的优质 Prompt 亦一并收录。\n"
            "4. treasure_links：逐条列出帖子中提到的外部工具、演示网页、插件或仓库链接。"
        )
    elif stype == "github":
        guidance = (
            "【GitHub 开源神器提取重点】：\n"
            "1. skill_name：提炼神器/工具中文名（≤12字）。\n"
            "2. pain_point：没有这个神器前，用户要手动做哪些繁重痛苦的事情。\n"
            "3. copy_ready_payloads：录入一键安装命令、最小配置 YAML/ENV、或者一行 Hello World 命令。\n"
            "4. treasure_links：收录该仓库地址及其推荐的相关生态链接。"
        )
    elif stype == "blender_tutorial":
        guidance = (
            "【Blender 3D 技巧提取重点】：\n"
            "1. skill_name：提炼三维技法名（≤12字，如「Cycles清漆消除萤火虫」）。\n"
            "2. pain_point：说明为什么模型/材质发灰或报错，痛点是什么。\n"
            "3. copy_ready_payloads：收录 Principled BSDF / 几何节点连接配方与快捷键序列。\n"
            "4. blender_script：若可代码化，输出可直接在 Blender Scripting 运行的完整 Python (bpy) 脚本。"
        )
    else:
        guidance = (
            "【通用深度认知提取重点】：\n"
            "1. skill_name：概括核心认知点（≤12字）。\n"
            "2. pain_point：直击认知误区或行业痛点。\n"
            "3. copy_ready_payloads：若有可落地的动作录入步骤，若为纯认知可为空数组。"
        )

    body = text.strip()[:12000] if text else "（无补充正文，请结合标题、链接及画面多模态素材分析）"
    return (
        f"请从以下素材中挖掘出用户能立刻拿去用的个人技能（Skill），拒绝劣质空泛概括：\n\n"
        f"- 来源：{source}（识别类型：{stype}）\n"
        f"- 原始标题：{title or '未提供'}\n"
        f"- 链接：{url or '无'}\n"
        f"- 正文/摘要：\n{body}\n"
        f"{media_hint}\n\n"
        f"{guidance}\n\n"
        f"分类与字段规范：\n"
        f"1. domain 必须严格从以下 4 个领域中选 1 个：\n{domains_block}\n"
        f"2. ladder_level 必须严格从以下 3 个阶段中选 1 个：\n{ladders_block}\n"
        f"3. source_type 填入 '{stype}'\n"
        f"4. skill_name：极简有力，≤12 字中文，小白一眼看懂。\n"
        f"5. pain_point：一句话说明它解决了什么痛点，拒绝废话。\n"
        f"6. one_line_essence：一句话核心机理（高密度硬核事实）。\n"
        f"7. how_to_apply：回答「我可以怎么用」，提供具体可执行动作。\n"
        f"8. copy_ready_payloads：即插即用载荷数组 [{{type: 'prompt'|'script'|'command'|'params', label: str, content: str, source_note: str}}]，content 必须为用户直接粘贴即可生效的原文！\n"
        f"9. treasure_links：挖掘出的宝藏工具、外链 [{{title: str, url: str, why: str}}]。\n"
        f"10. gotchas：小白实操避坑清单（每条写明避开什么坑）。\n"
        f"11. actionable_steps：有序实操步骤清单。\n"
        f"12. {projects_hint}\n"
        f"13. concept_breakdown：底层技术概念直觉拆解 [{{concept, intuition, analogy}}]。\n"
        f"14. blender_script：若涉及 Blender 3D 操作且可脚本化，输出完整 Python (bpy) 代码，否则为 null。\n"
    )
