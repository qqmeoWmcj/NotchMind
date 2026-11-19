from __future__ import annotations

import os
from pathlib import Path

from src.agent.engine import (
    get_current_model,
    get_model_alias,
    resolve_model_name,
    switch_default_model,
)
from src.companion import (
    XHS_AD_KEYWORDS,
    ClipboardWatcher,
    classify_clipboard_content,
    evaluate_xhs_quality,
    extract_bilibili_bvid,
    process_xhs_url,
    select_non_mcdn_url,
)
from src.exporters import (
    create_project_idea,
    ensure_vault_initialized,
    export_notebooklm_source,
    list_knowledge_entries,
    list_projects,
    save_knowledge_entry,
)
from src.memory import TopicMemory
from src.models import DOMAINS, LADDER_HEADINGS, KnowledgeEntry, RawItem

PROJECT_ROOT = Path(__file__).resolve().parent.parent


class _StubExtractionAgent:
    """Deterministic local extractor returning a valid KnowledgeEntry without external API calls."""

    def __init__(self, domain: str = "02-AI学习与教程", ladder_level: str = "L1基础教程") -> None:
        self.domain = domain
        self.ladder_level = ladder_level
        self.calls: list[dict] = []

    def analyze_content(self, **kwargs) -> KnowledgeEntry:
        self.calls.append(kwargs)
        return KnowledgeEntry(
            title=kwargs.get("title") or "提炼条目",
            source=kwargs.get("source") or "测试",
            url=kwargs.get("url") or "",
            domain=self.domain,
            ladder_level=self.ladder_level,
            matched_project=(kwargs.get("project_names") or [None])[0],
            one_line_essence="提炼后的核心结论，可直接一键复制。",
            how_to_apply="按步骤接入本地工作流并验证输出。",
            deep_insight="只保留可复用参数与校验闭环，剥离情绪话术。",
        )


def test_sqlite_memory_persists_and_deduplicates(tmp_path: Path) -> None:
    db_path = tmp_path / "memory.db"
    memory = TopicMemory(db_path)

    item_a = RawItem(source="HN", title="Agent Memory", url="https://example.com/a", score=100)
    item_a_dup = RawItem(source="HN", title="Agent Memory", url="https://example.com/a", score=100)
    item_b = RawItem(source="GitHub", title="MCP Server", url="https://example.com/b", score=200)

    unseen_first = memory.filter_unseen([item_a, item_a_dup, item_b])
    assert len(unseen_first) == 2

    inserted = memory.mark_seen([item_a])
    assert inserted == 1

    reloaded = TopicMemory(db_path)
    unseen_second = reloaded.filter_unseen([item_a, item_b])
    assert [i.url for i in unseen_second] == ["https://example.com/b"]


def test_minimal_vault_single_domain_file_and_console_update(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    data_dir = tmp_path / "data"
    ensure_vault_initialized(vault, data_dir)

    e1 = KnowledgeEntry(
        title="Blender 几何节点参数化建模基础",
        source="B站视频",
        url="https://www.bilibili.com/video/BV1xx411c7mD",
        domain="03-AI创作与3D工具",
        ladder_level="L1基础教程",
        matched_project="Blender一站式AI建模",
        one_line_essence="用可复用节点组替代手工调点，降低后续脚本控制难度。",
        how_to_apply="先沉淀 3 套基础几何节点模板再接大模型。",
        deep_insight="参数化结构是 AI 稳定输出三维资产的前提。",
    )
    e2 = KnowledgeEntry(
        title="Blender MCP 双向三视图渲染校准",
        source="小红书",
        url="https://www.xiaohongshu.com/explore/note001",
        domain="03-AI创作与3D工具",
        ladder_level="L2工具与AI联动",
        matched_project="Blender一站式AI建模",
        one_line_essence="通过本地 Socket 回传正侧顶渲染图，让模型迭代修材质。",
        how_to_apply="启动 blender-mcp 服务并把三视图截图回喂 Gemini。",
        deep_insight="没有视觉回传闭环的单向建模脚本很难一次达标。",
    )
    e3 = KnowledgeEntry(
        title="开源推理模型长上下文压测结论",
        source="HackerNews",
        url="https://example.com/llm-bench",
        domain="01-LLM与新模型",
        ladder_level="L1基础教程",
        matched_project=None,
        one_line_essence="长上下文下结构化 JSON 稳定度比单纯跑分更影响 Agent 成功率。",
        how_to_apply="本地抽取流水线统一加 schema 校验与指数退避重试。",
        deep_insight="个人工作流优先选稳定可复现的模型，而不是峰值指标。",
    )

    save_knowledge_entry(vault, data_dir, e1)
    save_knowledge_entry(vault, data_dir, e2)
    save_knowledge_entry(vault, data_dir, e2)  # duplicate must be ignored cleanly
    save_knowledge_entry(vault, data_dir, e3)

    # Strict 5 fixed root .md files + 1 project incubator folder (no date folders!)
    root_names = sorted(p.name for p in vault.iterdir())
    assert root_names == [
        "00-控制台与速览.md",
        "01-LLM与新模型.md",
        "02-AI学习与教程.md",
        "03-AI创作与3D工具.md",
        "04-行业深度认知.md",
        "05-项目孵化池",
    ]

    # Both 3D entries live inside ONE domain file, newest prepended before older
    domain_text = (vault / "03-AI创作与3D工具.md").read_text(encoding="utf-8")
    assert domain_text.count(f"<!-- entry-id:{e2.id} -->") == 1
    assert domain_text.count(f"<!-- entry-id:{e1.id} -->") == 1
    assert domain_text.index(e2.title) < domain_text.index(e1.title)

    # Console file contains action trigger links and all 3 entries
    console_text = (vault / "00-控制台与速览.md").read_text(encoding="utf-8")
    assert "http://127.0.0.1:8765/api/trigger/sync" in console_text
    assert "http://127.0.0.1:8765/api/trigger/toggle-clipboard" in console_text
    assert "http://127.0.0.1:8765/api/trigger/toggle-companion" in console_text
    for title in (e1.title, e2.title, e3.title):
        assert title in console_text

    # Structured JSON index filtering works with both full domain and short alias
    all_entries = list_knowledge_entries(data_dir)
    assert len(all_entries) == 3
    assert len(list_knowledge_entries(data_dir, domain="AI创作与3D工具")) == 2
    assert len(list_knowledge_entries(data_dir, project="Blender一站式AI建模")) == 2


def test_project_incubator_mounts_entries_into_l1_l2_l3_sections(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    data_dir = tmp_path / "data"
    ensure_vault_initialized(vault, data_dir)

    created = create_project_idea(
        vault, data_dir, "AI短视频工作流", "从脚本拆解到多模态自动成片的个人内容管线"
    )
    assert created["name"] == "AI短视频工作流"
    proj_file = vault / "05-项目孵化池" / "AI短视频工作流.md"
    assert proj_file.exists()

    entries = [
        KnowledgeEntry(
            title="L1条目A：分镜基础语法",
            source="B站视频",
            url="https://example.com/l1a",
            domain="02-AI学习与教程",
            ladder_level="L1基础教程",
            matched_project="AI短视频工作流",
            one_line_essence="先固定 3 秒钩子与核心结论，再补画面。",
            how_to_apply="每条草稿先写 30 字钩子再展开正文。",
            deep_insight="结构决定完播率，特效只是放大器。",
        ),
        KnowledgeEntry(
            title="L1条目B：收音降噪基础",
            source="小红书",
            url="https://example.com/l1b",
            domain="03-AI创作与3D工具",
            ladder_level="L1基础教程",
            matched_project="AI短视频工作流",
            one_line_essence="16kHz 单声道足够清晰识别口播并减小体积。",
            how_to_apply="ffmpeg 统一转 16kHz mono mp3。",
            deep_insight="音频信噪比直接决定多模态总结精度。",
        ),
        KnowledgeEntry(
            title="L2条目：TTS 与字幕时间轴联动",
            source="GitHub",
            url="https://example.com/l2",
            domain="03-AI创作与3D工具",
            ladder_level="L2工具与AI联动",
            matched_project="AI短视频工作流",
            one_line_essence="用脚本自动对齐语音停顿与字幕切片。",
            how_to_apply="将脚本接入本地剪辑导出流程。",
            deep_insight="半自动脚本解决 80% 机械对齐时间。",
        ),
        KnowledgeEntry(
            title="L3条目：全自动素材抓取到成片发布闭环",
            source="HackerNews",
            url="https://example.com/l3",
            domain="02-AI学习与教程",
            ladder_level="L3一站式自动化",
            matched_project="AI短视频工作流",
            one_line_essence="把质量校验阈值写进流水线实现无人值守生成。",
            how_to_apply="加入自动质检节点，不达标则重试生成。",
            deep_insight="L3 的核心是自动验收而非盲目堆步骤。",
        ),
    ]
    for entry in entries:
        save_knowledge_entry(vault, data_dir, entry)

    text = proj_file.read_text(encoding="utf-8")
    h1 = text.index(LADDER_HEADINGS["L1基础教程"])
    h2 = text.index(LADDER_HEADINGS["L2工具与AI联动"])
    h3 = text.index(LADDER_HEADINGS["L3一站式自动化"])

    assert h1 < text.index("L1条目A：分镜基础语法") < text.index("L1条目B：收音降噪基础") < h2
    assert h2 < text.index("L2条目：TTS 与字幕时间轴联动") < h3
    assert h3 < text.index("L3条目：全自动素材抓取到成片发布闭环")

    projects = list_projects(vault, data_dir)
    target = next(p for p in projects if p["name"] == "AI短视频工作流")
    assert target["entry_count"] == 4
    assert len(target["ladder"]["L1基础教程"]) == 2
    assert len(target["ladder"]["L2工具与AI联动"]) == 1
    assert len(target["ladder"]["L3一站式自动化"]) == 1


def test_notebooklm_export_writes_outside_vault(tmp_path: Path) -> None:
    nlm_dir = tmp_path / "data" / "notebooklm"
    entry = KnowledgeEntry(
        title="端侧小模型工具调用评测",
        source="HuggingFace",
        url="https://example.com/hf",
        domain="01-LLM与新模型",
        ladder_level="L2工具与AI联动",
        one_line_essence="7B 量化模型在受限 schema 下已可承担初筛任务。",
        how_to_apply="把低成本初筛放在本地，深度综合交给大模型。",
        deep_insight="分层路由比单一超大模型更省时间与配额。",
    )
    out = export_notebooklm_source(nlm_dir, "2026-11-19", [entry])
    assert out.exists()
    content = out.read_text(encoding="utf-8")
    assert "NotebookLM" in content
    assert entry.how_to_apply in content
    assert entry.deep_insight in content


def test_model_alias_resolution_and_env_switch(tmp_path: Path, monkeypatch) -> None:
    assert resolve_model_name("3.8f") == "gemini-3.8-flash"
    assert resolve_model_name("4h") == "gemini-4-hydrogen"
    assert resolve_model_name("4a") == "gemini-4-argon"
    assert resolve_model_name("custom-model") == "custom-model"
    assert get_model_alias("gemini-4-hydrogen") == "4h"

    monkeypatch.setenv("GEMINI_MODEL", "gemini-3.8-flash")
    env_file = tmp_path / ".env"
    env_file.write_text("GEMINI_API_KEY=demo\nGEMINI_MODEL=gemini-3.8-flash\n", encoding="utf-8")

    resolved = switch_default_model("4h", env_path=env_file)
    assert resolved == "gemini-4-hydrogen"
    assert os.environ["GEMINI_MODEL"] == "gemini-4-hydrogen"
    assert get_current_model(env_path=env_file) == ("gemini-4-hydrogen", "4h")


def test_xhs_three_tier_anti_ad_filter_and_processing(tmp_path: Path) -> None:
    # Tier 1: blocks low collect/like ratio (< 50%)
    ok, reason = evaluate_xhs_quality("AI 效率工具分享", "亲测好用的本地脚本步骤", likes=200, collects=80)
    assert not ok
    assert "收藏/点赞比" in reason

    ok_cn, _ = evaluate_xhs_quality("大模型对比", "实测参数对比", likes="1万", collects="2千")
    assert not ok_cn

    # Tier 2: blocks ad/lead-gen keywords even with high collect ratio
    for kw in ("扣1", "私信领", "卖课", "训练营", "加V", "加微", "限时免费领", "评论区领", "无偿分享"):
        assert kw in XHS_AD_KEYWORDS
        passed, msg = evaluate_xhs_quality(
            "AI 自动化教程", f"想要完整资料请{kw}获取", likes=100, collects=300
        )
        assert not passed, f"Expected keyword {kw!r} to be blocked"
        assert "黑名单" in msg

    # Whitespace/case obfuscation also blocked
    passed_obf, _ = evaluate_xhs_quality("干货", "评论区 扣 1 领取", likes=100, collects=200)
    assert not passed_obf

    # High-save tutorials pass (exact 50% boundary & > 100% high-save)
    passed_edge, _ = evaluate_xhs_quality("Blender 材质节点教程", "完整节点连线参数清单", likes=100, collects=50)
    assert passed_edge
    passed_high, _ = evaluate_xhs_quality("Obsidian 工作流配置", "无废话三步配置指南", likes=300, collects=720)
    assert passed_high

    # process_xhs_url must short-circuit before calling Gemini when filtered
    class _FailIfCalledAgent:
        def analyze_content(self, **kwargs):
            raise AssertionError("Filtered ad post must never call Gemini agent")

    blocked = process_xhs_url(
        "https://www.xiaohongshu.com/explore/ad001",
        _FailIfCalledAgent(),
        tmp_path / "vault",
        tmp_path / "data",
        title="三天 AI 变现",
        text="想要工具包评论区扣1私信领",
        likes=50,
        collects=100,
    )
    assert blocked["ok"] is False
    assert blocked["filtered"] is True

    # High-save tutorial proceeds to agent and saves into real vault
    stub = _StubExtractionAgent(domain="03-AI创作与3D工具", ladder_level="L2工具与AI联动")
    saved = process_xhs_url(
        "https://www.xiaohongshu.com/explore/good001",
        stub,
        tmp_path / "vault",
        tmp_path / "data",
        title="Blender MCP 自动打光参数",
        text="三点布光具体数值与脚本配置详解",
        likes=120,
        collects=260,
    )
    assert saved["ok"] is True
    assert saved["filtered"] is False
    assert len(stub.calls) == 1
    assert len(list_knowledge_entries(tmp_path / "data")) == 1


def test_bilibili_bvid_extraction_and_non_mcdn_selection() -> None:
    assert extract_bilibili_bvid("https://www.bilibili.com/video/BV1xx411c7mD/?spm_id_from=333") == "BV1xx411c7mD"
    assert extract_bilibili_bvid("【硬核教程】https://m.bilibili.com/video/BV1Ab4y1z7Kq 推荐看") == "BV1Ab4y1z7Kq"
    assert extract_bilibili_bvid("BV1Q541167Qg") == "BV1Q541167Qg"
    assert extract_bilibili_bvid("not-a-bvid BV12345 BV1xx411c7mDEXTRA") is None

    selected = select_non_mcdn_url(
        {
            "url": "https://xy123.mcdn.bilivideo.cn:4483/video.mp4",
            "backup_url": [
                "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/demo.mp4",
                "https://xy999.mcdn.bilivideo.cn:4483/video.mp4",
            ],
        }
    )
    assert selected == "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/demo.mp4"


def test_clipboard_classification_and_sha256_dedup(tmp_path: Path) -> None:
    c_bili = classify_clipboard_content("看看这个视频 https://www.bilibili.com/video/BV1xx411c7mD?p=1")
    assert c_bili["kind"] == "bilibili"
    assert c_bili["bvid"] == "BV1xx411c7mD"

    c_b23 = classify_clipboard_content("https://b23.tv/abc123X")
    assert c_b23["kind"] == "bilibili"

    c_xhs = classify_clipboard_content("超实用教程 http://xhslink.com/a/XYZ123 复制本条信息打开小红书")
    assert c_xhs["kind"] == "xiaohongshu"
    assert c_xhs["url"] == "http://xhslink.com/a/XYZ123"

    c_ai = classify_clipboard_content("https://github.com/modelcontextprotocol/servers")
    assert c_ai["kind"] == "web_url"
    assert c_ai["is_ai_url"] is True

    c_non_ai = classify_clipboard_content("https://example.com/pasta-recipe")
    assert c_non_ai["kind"] == "web_url"
    assert c_non_ai["is_ai_url"] is False

    c_local = classify_clipboard_content("http://127.0.0.1:8765/")
    assert c_local["kind"] == "ignored"

    c_plain = classify_clipboard_content("使用 Gemini 多模态分析关键帧联系表")
    assert c_plain["kind"] == "plain_text"
    assert c_plain["is_ai_url"] is True

    assert classify_clipboard_content("   ")["kind"] == "empty"

    # Real ClipboardWatcher SHA256 deduplication writing to real vault
    stub = _StubExtractionAgent(domain="02-AI学习与教程", ladder_level="L1基础教程")
    watcher = ClipboardWatcher(
        vault_root=tmp_path / "vault",
        data_dir=tmp_path / "data",
        agent_factory=lambda: stub,
        capture_plain_text=True,
        clipboard_reader=lambda: "",
    )
    first = watcher.process_text("笔记：多模态拆解视频要配 2x3 联系表与 16kHz 音轨")
    second = watcher.process_text("笔记：多模态拆解视频要配 2x3 联系表与 16kHz 音轨")
    assert first["ok"] is True
    assert second["skipped"] is True
    assert second["duplicate"] is True
    assert watcher.status()["processed_count"] == 1
    assert len(stub.calls) == 1


def test_live_workspace_vault_keeps_strict_minimal_layout() -> None:
    live_vault = PROJECT_ROOT / "vault"
    assert live_vault.exists()
    root_items = sorted(p.name for p in live_vault.iterdir() if p.name != ".DS_Store")
    expected = ["00-控制台与速览.md", *[f"{d}.md" for d in DOMAINS], "05-项目孵化池"]
    assert root_items == expected
    projects_dir = live_vault / "05-项目孵化池"
    assert projects_dir.is_dir()
    assert list(projects_dir.glob("*.md")), "05-项目孵化池/ should contain at least one project note"
