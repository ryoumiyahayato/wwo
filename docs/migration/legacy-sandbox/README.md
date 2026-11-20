# 旧军事沙盒：可复用资料与 Rust 迁移验收清单

审查基线：WWO main `f499a6f0b7774a628c0025aec9d7fb3d12107e32`；旧军事 main `44c8f3d0639f7b84a0053d7edfa76641cb8a50d7`；旧区域观察分支 `1be636748535feaeae694cbd12584e3346d5da9e`。本分支不改 Rust 宿主，不引入 Godot 运行依赖，不代表已经集成。reference/ 的文件仅用于查阅，其余旧历史不在本分支。

## 保留与优先顺序

1. **素材验收。** Cedar 旧工具按固定地图清单核对 GLB 自包含、几何有效性、三角数、尺寸与碰撞引用。旧工具依赖原素材、第三方 Python 库和旧目录，不在主仓直接执行。Rust 可复用检查要求：同名文件换版、漏贴图、越界索引、NaN 顶点、碰撞形体漏引必须失败；游戏导入和实际接触另验。
2. **区域观察和地面交接。** 独有分支有分层地面材质、布景、只读高程源。主仓 `rust/strategic-host/src/battlefield_terrain.rs` 已实现 50 m/4 m 采样与旧网格三角边界；不要换回旧插值。新增验收：跨 25×25/50×50 近景边界时，视觉与碰撞用同一高程，任一时刻只有一个近景地面碰撞所有者；切换时保留外围缓存，不重复提交、不出现空洞。可编辑会话与只读观察对象分开。
3. **移动端渲染。** 旧实现分离 3D 渲染像素预算与 2D 原生分辨率。Rust 端按手机体验移植时，可分别测试同帧 UI 可读性、3D 掉帧、预算切换与偏好持久化。不要依据 CPU 卡顿自动模糊画面。
4. **存档、时钟与人物视图。** 从旧 m-v9 保留引擎无关的验收要求：分段和一次推进的同输入结果等价；暂停与预算耗尽不发布未提交状态；只读查询不推进、不改随机状态；同会话同请求 ID 重放返回原回执，新内容复用 ID 必须拒绝；控制角色切换不复制状态；只读视图与测试诊断隔离。未跑完就标 NOT RUN 或失败，历史 Godot 测试不是 Rust 验收。

## 文件来源（Git blob）

- `validate_cedar_assets.py.txt` ← `44c8f3d0639f7b84a0053d7edfa76641cb8a50d7` / `military-godot/cedar/tools/validate_cedar_assets.py` / `53964b7f83b60712585fcb015bbcff2fdd81e1bc`
- `mobile_render_budget.gd.txt` ← `44c8f3d0639f7b84a0053d7edfa76641cb8a50d7` / `military-godot/scripts/mobile_render_budget.gd` / `3bc8bfbb21c79c746d6e66a114720f4ceedbb937`
- `README.md.txt` ← `1be636748535feaeae694cbd12584e3346d5da9e` / `military-godot/modules/region_observation/README.md` / `6a5b0a21a85b0bae43b26fc0070374fa48596f09`
- `layered_ground.gdshader.txt` ← `1be636748535feaeae694cbd12584e3346d5da9e` / `military-godot/modules/region_observation/layered_ground.gdshader` / `6966ad714be43c9a7446467305ed64367741738c`
- `layered_terrain.gd.txt` ← `1be636748535feaeae694cbd12584e3346d5da9e` / `military-godot/modules/region_observation/layered_terrain.gd` / `ea62026718bb075f43eafdd520991a4b8df60c00`
- `scenery_placement.gd.txt` ← `1be636748535feaeae694cbd12584e3346d5da9e` / `military-godot/modules/region_observation/scenery_placement.gd` / `b33e5ad15c41620ffa54382782c3a4eefb679afc`
- `terrain_height_source.gd.txt` ← `1be636748535feaeae694cbd12584e3346d5da9e` / `military-godot/modules/region_observation/terrain_height_source.gd` / `897da009b353ddcd4718fb0ed8e4386fff852293`

## 删除旧库之前

旧区块观察分支领先旧 main 36 个提交；本分支只取相关参考资料，不完整保存该分支及历史。旧军事库本身也不是最近 30 架飞机的归档：未找到对应的机型/训练入口完整内容。主仓已有的旧军事归档分支也不等价于这次抽取。删除前需另存完整分支历史和任何所需发布附件；本分支不是完整备份。
