import Foundation

/// Generates and manages executable Blender Python (`bpy`) scripts that directly feed
/// extracted 3D/Blender knowledge into active local Blender projects.
public enum BlenderScriptGenerator {

    /// Returns the entry's custom script if present, or synthesizes a parameter-driven
    /// runnable `bpy` script based on the entry's extracted actionable steps and optimizations.
    public static func getOrGenerateScript(for entry: KnowledgeEntry) -> String {
        if let script = entry.blenderScript, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return script
        }
        return generateFallbackScript(for: entry)
    }

    /// Synthesizes a production-grade, safe Python `bpy` script tailored for Blender 4.x.
    public static func generateFallbackScript(for entry: KnowledgeEntry) -> String {
        let topicType = detectTopicType(entry: entry)
        var bodyLines: [String] = []

        switch topicType {
        case .shaderMaterial:
            bodyLines.append(contentsOf: generateShaderMaterialSnippet(for: entry))
        case .geometryNodesModifier:
            bodyLines.append(contentsOf: generateModifierSnippet(for: entry))
        case .lightingRender:
            bodyLines.append(contentsOf: generateLightingRenderSnippet(for: entry))
        case .modelingTopology:
            bodyLines.append(contentsOf: generateModelingSnippet(for: entry))
        case .general:
            bodyLines.append(contentsOf: generateGeneralSnippet(for: entry))
        }

        let script = """
        # ==============================================================================
        # NotchMind Blender 实操反哺脚本 (Blender 4.x Python / bpy)
        # 知识标题: \(entry.title)
        # 核心机理: \(entry.oneLineEssence)
        # 来源: \(entry.source) \(entry.url.isEmpty ? "" : "| " + entry.url)
        # 生成时间: \(entry.createdAt)
        # ==============================================================================
        # 使用方式：
        # 1. 打开 Blender，切换到「Scripting (脚本)」工作区；
        # 2. 点击「新建 (New)」，粘贴本脚本并点击「运行脚本 (Run Script / Alt+P)」；
        # 3. 脚本会自动安全检测当前场景活动物体，并注入实操参数。
        # ==============================================================================

        import bpy
        import math

        def run_notchmind_recipe():
            print("[NotchMind] 开始执行参数反哺脚本: \(entry.title)...")
            
            # 1. 确保在 Object 模式下进行参数配置
            if bpy.context.mode != 'OBJECT' and bpy.ops.object.mode_set.poll():
                bpy.ops.object.mode_set(mode='OBJECT')

            # 2. 获取或创建目标活动物体
            obj = bpy.context.active_object
            if obj is None:
                bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0, 0, 0))
                obj = bpy.context.active_object
                print(f"[NotchMind] 提示: 场景中未选中活动物体，已自动创建测试立方体 '{obj.name}'")
            else:
                print(f"[NotchMind] 选中目标物体: '{obj.name}' (类型: {obj.type})")

        \(indent(bodyLines.joined(separator: "\n"), spaces: 4))

            print("[NotchMind] ✅ 参数反哺执行完毕！请在 3D 视图中查看效果。")

        if __name__ == "__main__":
            run_notchmind_recipe()
        """
        return script
    }

    // MARK: - Snippet Generators by Topic

    private static func generateShaderMaterialSnippet(for entry: KnowledgeEntry) -> [String] {
        var lines: [String] = [
            "# --- 材质与 Principled BSDF 节点配置 ---",
            "mat_name = \"M_NotchMind_\" + obj.name",
            "mat = bpy.data.materials.get(mat_name) or bpy.data.materials.new(name=mat_name)",
            "mat.use_nodes = True",
            "nodes = mat.node_tree.nodes",
            "bsdf = nodes.get(\"Principled BSDF\")",
            "if not bsdf:",
            "    bsdf = nodes.new(type=\"ShaderNodeBsdfPrincipled\")",
            "",
            "if obj.data and hasattr(obj.data, 'materials'):",
            "    if len(obj.data.materials) == 0:",
            "        obj.data.materials.append(mat)",
            "    else:",
            "        obj.data.materials[0] = mat",
            "",
            "# 根据提取的参数调整着色器",
        ]

        let fullText = "\(entry.title) \(entry.oneLineEssence) \(entry.actionableSteps.joined()) \(entry.projectOptimizations.joined())".lowercased()
        if fullText.contains("subsurface") || fullText.contains("次表面") || fullText.contains("皮肤") {
            lines.append("if \"Subsurface Weight\" in bsdf.inputs:")
            lines.append("    bsdf.inputs[\"Subsurface Weight\"].default_value = 0.25")
            lines.append("if \"Subsurface Radius\" in bsdf.inputs:")
            lines.append("    bsdf.inputs[\"Subsurface Radius\"].default_value = (1.0, 0.2, 0.1)")
        }
        if fullText.contains("roughness") || fullText.contains("粗糙度") {
            lines.append("if \"Roughness\" in bsdf.inputs:")
            lines.append("    bsdf.inputs[\"Roughness\"].default_value = 0.28")
        }
        if fullText.contains("metallic") || fullText.contains("金属") {
            lines.append("if \"Metallic\" in bsdf.inputs:")
            lines.append("    bsdf.inputs[\"Metallic\"].default_value = 0.85")
        }

        appendComments(for: entry, into: &lines)
        return lines
    }

    private static func generateModifierSnippet(for entry: KnowledgeEntry) -> [String] {
        var lines: [String] = [
            "# --- 修改器 / 几何节点配置 ---",
        ]
        let fullText = "\(entry.title) \(entry.oneLineEssence) \(entry.actionableSteps.joined())".lowercased()
        if fullText.contains("subsurf") || fullText.contains("细分") {
            lines.append("mod = obj.modifiers.get(\"Subdivision\") or obj.modifiers.new(\"Subdivision\", type='SUBSURF')")
            lines.append("mod.levels = 2")
            lines.append("mod.render_levels = 3")
        } else if fullText.contains("bevel") || fullText.contains("倒角") {
            lines.append("mod = obj.modifiers.get(\"Bevel\") or obj.modifiers.new(\"Bevel\", type='BEVEL')")
            lines.append("mod.width = 0.02")
            lines.append("mod.segments = 3")
        } else {
            lines.append("# 添加通用表面细分保护拓扑")
            lines.append("mod = obj.modifiers.get(\"Subdivision\") or obj.modifiers.new(\"Subdivision\", type='SUBSURF')")
            lines.append("mod.levels = 1")
        }
        appendComments(for: entry, into: &lines)
        return lines
    }

    private static func generateLightingRenderSnippet(for entry: KnowledgeEntry) -> [String] {
        var lines: [String] = [
            "# --- 渲染引擎与三点布光设置 ---",
            "scene = bpy.context.scene",
        ]
        let fullText = "\(entry.title) \(entry.oneLineEssence)".lowercased()
        if fullText.contains("cycles") {
            lines.append("scene.render.engine = 'CYCLES'")
            lines.append("if hasattr(scene.cycles, 'samples'):")
            lines.append("    scene.cycles.samples = 256")
        } else {
            lines.append("scene.render.engine = 'BLENDER_EEVEE_NEXT' if hasattr(bpy.types, 'RenderSettings') else 'BLENDER_EEVEE'")
        }
        lines.append("")
        lines.append("# 添加主光源 (Key Light)")
        lines.append("light_data = bpy.data.lights.new(name=\"L_NotchMind_Key\", type='AREA')")
        lines.append("light_data.energy = 500.0")
        lines.append("light_data.size = 1.2")
        lines.append("light_obj = bpy.data.objects.new(name=\"L_NotchMind_Key\", object_data=light_data)")
        lines.append("bpy.context.collection.objects.link(light_obj)")
        lines.append("light_obj.location = (3.0, -3.0, 4.0)")

        appendComments(for: entry, into: &lines)
        return lines
    }

    private static func generateModelingSnippet(for entry: KnowledgeEntry) -> [String] {
        var lines: [String] = [
            "# --- 拓扑平滑与法线配置 ---",
            "if obj.type == 'MESH':",
            "    # 启用平滑着色",
            "    for poly in obj.data.polygons:",
            "        poly.use_smooth = True",
        ]
        appendComments(for: entry, into: &lines)
        return lines
    }

    private static func generateGeneralSnippet(for entry: KnowledgeEntry) -> [String] {
        var lines: [String] = [
            "# --- 通用实操与属性注入 ---",
            "# 记录 NotchMind 属性元数据",
            "obj[\"notchmind_source\"] = \"\(entry.title)\"",
            "obj[\"notchmind_essence\"] = \"\(entry.oneLineEssence.prefix(60))\"",
        ]
        appendComments(for: entry, into: &lines)
        return lines
    }

    private static func appendComments(for entry: KnowledgeEntry, into lines: inout [String]) {
        lines.append("")
        lines.append("# 实操优化项目列表:")
        for opt in entry.projectOptimizations.prefix(3) {
            lines.append("# - \(opt)")
        }
        for step in entry.actionableSteps.prefix(3) {
            lines.append("# [步骤] \(step)")
        }
        for snippet in entry.copyableSnippets.prefix(2) {
            let cleaned = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                lines.append("# [参考代码/命令]: \(cleaned)")
            }
        }
    }

    // MARK: - Topic Detection

    private enum TopicType {
        case shaderMaterial
        case geometryNodesModifier
        case lightingRender
        case modelingTopology
        case general
    }

    private static func detectTopicType(entry: KnowledgeEntry) -> TopicType {
        let text = "\(entry.title) \(entry.oneLineEssence) \(entry.actionableSteps.joined())".lowercased()
        if text.contains("shader") || text.contains("材质") || text.contains("节点") || text.contains("bsdf") || text.contains("贴图") || text.contains("次表面") || text.contains("粗糙度") {
            return .shaderMaterial
        }
        if text.contains("修改器") || text.contains("modifier") || text.contains("几何节点") || text.contains("geometry node") || text.contains("subsurf") || text.contains("细分") || text.contains("bevel") || text.contains("倒角") {
            return .geometryNodesModifier
        }
        if text.contains("光") || text.contains("渲染") || text.contains("cycles") || text.contains("eevee") || text.contains("render") || text.contains("采样") || text.contains("布光") {
            return .lightingRender
        }
        if text.contains("建模") || text.contains("拓扑") || text.contains("雕刻") || text.contains("mesh") || text.contains("布线") || text.contains("模型") {
            return .modelingTopology
        }
        return .general
    }

    private static func indent(_ string: String, spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return string.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.isEmpty ? "" : prefix + line }
            .joined(separator: "\n")
    }
}
