# NotchMind 架构与产品决策记录（Decisions Log）

- **日期**：2026-11-19
- **应用名称**：`NotchMind`（Bundle ID: `com.jackma.notchmind`）
- **最低系统版本**：**macOS 26+**（优先适配原生 Liquid Glass `.glassEffect()`，后续再评估向后兼容旧版 macOS）

## 已确定核心决策

1. **纯原生 Swift 6 单一 `.app`（`.dmg` 分发）**
   - 将窗口监测、截屏、剪贴板监听、B 站/网页元数据拉取、Gemini REST 调用、SQLite 去重与 Obsidian 导出全部收敛至单一原生可执行文件，零 Python/Node/CLI 子进程，macOS 隐私权限 **100% 仅出现 `NotchMind` 一个软件名**。
2. **彻底根治误抓与重复写入**
   - **单窗口精准抓拍**：`ScreenCaptureKit` `SCContentFilter(desktopIndependentWindow:)` 按目标 `CGWindowID` 截屏，**彻底移除全屏静默回退**；`NSPanel.sharingType = .none` 作为附加保险。
   - **严格白名单**：仅当前台确为 `PiliPlus` 或前台浏览器标题匹配白名单站点（默认 B 站、YouTube）时自动伴随；切至微信、IDE、本地地址或其他网页自动休眠；支持全局快捷键（`⌘⇧S`）随时手动抓拍当前前景窗口。
   - **强去重**：SQLite `data/notchmind.db` 按规范化 URL / BVID 与画面帧哈希去重，叠加内存 in-flight 并发锁，杜绝同链接双写。
3. **视觉与交互（A′ 灵动岛纯黑 + Apple Liquid Glass）**
   - 详见 [DESIGN.md](../DESIGN.md)：刘海屏空闲完全隐身、工作时弹簧伸耳、悬停展开纯黑面板且内部控件层使用 Liquid Glass；外接屏悬浮胶囊支持「纯黑」与「液态玻璃」双外观切换；严格黑白灰，仅错误提示使用系统红；独立原生设置窗跟随系统深浅色。
4. **v1 MVP 交付范围**
   - 纯原生 Swift `NotchMind.app` + `dist/NotchMind.dmg`。
   - 精准伴随抓拍 + 全局快捷键 + 剪贴板/手动链接精拆（B 站/网页）+ 写入现有 Obsidian 单领域单文档（`00-控制台与速览.md` 与 `01~04`）+ 同步 `data/entries.json`。
   - 真实行为单测（`swift test`）验证去重、白名单、URL 规范化与 Obsidian 写入。

5. **设置窗口独立调起与置顶聚焦（2026-11-20 迭代）**
   - **痛点**：在 `.nonactivatingPanel` 属性的 HUDPanel 中点击设置齿轮时，因 app 为 `.accessory` 后台型且面板不激活应用，导致设置窗无法被置顶或捕获键盘焦点。
   - **解法**：点击时临时提升为 `NSApp.setActivationPolicy(.regular)`，配合 `window.orderFrontRegardless()`、`window.level = .floating` 和 `NSApp.activate(ignoringOtherApps: true)` 确保必达置顶与焦点；设置窗口关闭时由 `NSWindowDelegate` 还原回 `.accessory`，收回 Dock 占用。
   - **命中区域加固**：齿轮与目标行全量绑定 `.contentShape(Rectangle())`，消除薄线 SF Symbol 击穿失灵。

6. **外接显示器挂载与多比例自适应布局（2026-11-20 迭代）**
   - **痛点**：原实现硬编码在右上角，遮挡 macOS 菜单栏控制中心、时钟与通知。
   - **解法**：重构挂载策略为「顶部居中悬浮胶囊」（对标 TokenMonitor / Dynamic Island），默认置于水平中轴并留出 6pt 菜单栏间隙；自动识别当前显示器比例（16:9 标准宽屏、16:10 生产力屏、21:9 超宽带鱼屏）；提供「顶部偏左」、「顶部避让右侧」及「自由拖拽停靠记忆」选项。

7. **原生液态玻璃 3 档精准色调（2026-11-20 迭代）**
   - **痛点**：原连续滑动条仅改变极淡的黑衬底透明度，视觉上无感知。
   - **解法**：对齐 macOS 系统外观标准，划定立竿见影的 3 档调节：
     1. **最玻璃 (Clear Glass)**：通透水晶质感（`.clear` glass 材质），极低衬底（12%），明亮高光边框（36%），透视壁纸底色；
     2. **默认中间档 (Regular Glass)**：标准原生液态玻璃，质感与 4.5:1 对比度平衡；
     3. **色调/显毛玻璃 (Tinted Frosted)**：丰富磨砂毛玻璃层（68% 衬底 + 柔雾漫反射），高文字对比与厚重磨砂质感。
   - **反哺闭环保护**：默认反哺路径修正为 `vault/05-项目孵化池/99-项目反哺清单.md`，彻底守住 Obsidian 根目录极简布局规范。
