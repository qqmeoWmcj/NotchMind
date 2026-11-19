from __future__ import annotations

from src.models import DOMAINS, LADDER_LEVELS

SYSTEM_INSTRUCTION = """你是一位深耕 AI 行业与个人工作流工程化的知识总编。
你的核心原则：
1. 聚焦高密度认知、架构演进、实操方法论与可落地的个人应用，拒绝空洞套话与营销水分。
2. 彻底去 AI 味：禁止使用「赋能、抓手、颠覆、众所周知、总而言之、不仅如此」等空话；用克制、直接、像高手复盘笔记一样的语言输出。
3. 所有提取必须忠实于提供的文本、音频或画面，不编造未出现的参数、工具名或数据。
4. 严格遵循指定的 JSON Schema 输出。"""


def build_selection_prompt(items_text: str, top_k: int) -> str:
    return (
        f"以下是今天抓取到的 AI 行业原始热点列表（带 0 开始的索引编号）。\n"
        f"请从中挑选出最具学习价值、实操启发或行业认知深度的 {top_k} 个话题（避免重复主题）。\n\n"
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
    domains_block = "\n".join(f"- {d}" for d in DOMAINS)
    ladders_block = (
        f"- {LADDER_LEVELS[0]}：基础概念、入门教程、单一功能或基础认知\n"
        f"- {LADDER_LEVELS[1]}：把 AI / MCP / 插件 / 脚本接入具体工具或工作流\n"
        f"- {LADDER_LEVELS[2]}：端到端一站式自动化流水线、多步骤编排或无人值守闭环"
    )
    if project_names:
        projects_hint = (
            "当前 05-项目孵化池 中已立项的项目列表："
            + "、".join(project_names)
            + "。\n"
            "仅当素材与上述某个项目直接相关、能作为该项目的实操参考时，才将 matched_project 设为该项目的精确名称；"
            "否则必须返回 null，严禁自造新项目名。"
        )
    else:
        projects_hint = "当前没有待匹配项目，matched_project 请直接返回 null。"

    media_hint = (
        "\n注意：随附了音频或画面截图，请优先结合听到的关键步骤/口播要点与看到的界面参数/节点/命令进行提炼。"
        if has_media
        else ""
    )

    body = text.strip()[:12000] if text else "（无补充正文，请结合标题、链接及附带多模态素材分析）"
    return (
        f"请分析以下素材，提炼为一条高密度结构化知识条目：\n\n"
        f"- 来源：{source}\n"
        f"- 原始标题：{title or '未提供'}\n"
        f"- 链接：{url or '无'}\n"
        f"- 正文/摘要：\n{body}\n"
        f"{media_hint}\n\n"
        f"分类要求：\n"
        f"1. domain 必须严格从以下 4 个领域中选 1 个：\n{domains_block}\n"
        f"   - 01-LLM与新模型：大模型发布、架构、推理、基准评测、开源权重、API 演进\n"
        f"   - 02-AI学习与教程：Prompt、Agent 开发教程、MCP/Skills、编程效率、学习路线\n"
        f"   - 03-AI创作与3D工具：Blender/三维建模、图像视频音频生成、设计/剪辑与 AI 创作工具\n"
        f"   - 04-行业深度认知：商业模式、职场演变、产品战略、反共识行业判断\n"
        f"2. ladder_level 必须严格从以下 3 个阶段中选 1 个：\n{ladders_block}\n"
        f"3. {projects_hint}\n"
        f"4. one_line_essence：一句话说清核心事实或结论（适合一键复制速览）。\n"
        f"5. how_to_apply：直接回答「我可以怎么用」，给出具体可执行的动作、命令、Prompt 思路或接入步骤。\n"
        f"6. deep_insight：给出犀利、具体、去 AI 味的深层判断或避坑提醒。\n"
    )
