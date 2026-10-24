# 当前版本：Ridgevale 已有村落细化 v2

当前继续细化已有C1村落，不生成新地图或新高度场。代表西院 house_02 组织成约27×35.6米的完整院落，22段院墙、宽主门和东北出口、集中5棵树及清晰地面边界；其余节点不再均匀加量。

相对原117个静物，净新增52段既有石墙、17棵既有树，总186个静物、113个批次。原117个物件、三条主路、全部房屋位置、高度数据及战斗/HUD/VFX生产代码保持不变。细节和复现入口见 [DETAIL_REFINEMENT_ZH.md](DETAIL_REFINEMENT_ZH.md)。

近景树条纹已通过树专用材质不接收投影的折中处理，保留对地投影、原模型和LOD；代价是树不接收其他物体阴影。可恢复点与对照证据见细化说明。

当前使用refine_existing_village.py重建细化，不要只运行原始基础生成器。实际图像评审和最新测试数字以review与上层本轮证据为准。

以下保留C1原始基线记录，原数量117及旧验收数字不是当前细化版统计。

# Ridgevale C1：干燥鞍部村落候选

2026-10-20。独立新地图，不覆盖 Cedar、Rivergate、现有战斗/AI或原始美术。原地图入口仍保留；本目录提供独立地图资源与接口。

## 本次范围

- 真实5×5公里世界，原点仍为(0,0)。1251×1251、4米间距、小端float32高度场，6,260,004字节。地形source_id：`ridgevale_5km_c1_20261020`。
- 重点布置约800×800米。东西两道干燥山脊、中央较低鞍部、三条贯通路线：10米中央路，8.5米西、东绕行侧路。
- 117处静态放置：12栋住宅、1栋谷仓、12段石墙、60棵疏树、32处岩石。外围5公里只提供连续地形和低密度地表，不能称全部达到村落美术密度。
- 保护原部署区x[-120,120]、z[-180,340]。静态检查不仅排除物件中心，也检查整个旋转后模型AABB不侵入该区域；原生检查另测现有生成公式产生的42处初始点及沿路车辆通道。
- 无水、无桥。道路是同一高度场上的烘焙缓坡与地表标识，没有独立道路碰撞，也不新增路面抓地、泥泞或掩蔽机制。建筑仍是封闭实心、不可进入/破坏的壳体。

## 资源与运行接口

`heightfield.gd`：加载本目录烘焙数据，拒绝尺寸错误、非有限数据；提供sample及normal_at。

`terrain.gd`：直接继承原`streamed_battle_terrain.gd`，不覆盖sample_height，不另造碰撞/地形编辑权威。保留原1米近处三角网格、分块碰撞、模拟锚点、持久稀疏修改、每帧分块预算和支撑缓存失效机制。远景仍是20米间距的整幅轮廓，覆盖掩码随真正加载的近处分块更新。

调用顺序：创建terrain并加入树，`terrain.configure(Vector3.ZERO, null)`成功后，再创建world并`world.build(terrain)`。World读取`terrain.ridge_field`、`assets/map.json`，schema为`ridgevale-map-c1`。

`world.gd`保留按100米格和种类组织MultiMesh的接口。`_mesh_for(kind)`直接引用Cedar已导入的原Mesh，没有重造ArrayMesh或丢弃其索引LOD；导入LOD与实际远距降低几何的证据在整包验收中另行记录。静态碰撞不因显示剔除消失。

本目录仅新增两张2048×2048语义图：land_color（干草/土/岩色）和land_control（R=土路，G=田地，B=岩）。复用Cedar着色器及草、土、石detail纹理。没有改写任何Cedar GLB或纹理。

## 可复现生成与检查

生成器依赖Python 3、numpy、scipy、Pillow。无需trimesh，也不会重新生成复用模型：

```sh
python ridgevale/tools/build_ridgevale_assets.py
python ridgevale/tools/validate_ridgevale_assets.py
python ridgevale/tools/build_ridgevale_assets.py --verify-rebuild  # 独立输出，不覆盖运行中的资产
```

生成器仅写本目录assets及review，固定seed=20261020；读取Cedar已有碰撞/资产统计。`review/generation_receipt.json`包含输出SHA256、复用模型SHA256、数量及实际烘焙坡度。`review/static_contract.json`是当前数据的静态结果。

原生检查（Godot4.6.x，先正常导入资源）：

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script ridgevale/tests/test_ridgevale_native.gd
```

建议在可写XDG_CONFIG_HOME、XDG_CACHE_HOME和XDG_DATA_HOME运行；只读主目录会产生Godot用户缓存告警。原生脚本有有限循环，可另加外部150秒超时。

测试覆盖：边界/唯一来源、原点及部署槽无新增障碍、三条路线2米间距坡度与实际形状探测、路线节点实际物理射线与生产rigid-track支撑、12条村屋侧向院落接近坡度、真实驱动地面组、流式加载和稀疏编辑跨卸载保持。详细结果见`review/native_contract.json`及日志。

## 本目录验证结果

- 静态507项通过。包含完整旋转模型包围盒对部署保护区的排除检查。
- Godot 4.6.3原生2,643项通过，0失败；455次静物通道形状探测、21处原生地面射线与生产履带支撑。
- 主路最大纵坡3.89%，西侧翼7.62%，东侧翼6.77%，三路线最大横坡均低于3%。这些是已烘焙数据的采样结果，不是美术预估。
- 最终资产与独立目录第二次完整重建的四个新资产SHA256一致，复用模型源文件哈希不变。见`review/reproducibility.json`。

## 已知边界

- 静态坡度检查不等价于AI寻路或玩家实驾。建筑平台之外的山坡可陡于道路，不能假定全图可直线通过。
- 原生测试独立创建地形与布景，不修改或替代战斗模拟，不证明10车/30兵完整战斗、枪炮、伤损或HUD压力回归通过。
- 本目录的原生检查不运行GUI、不导出APK；实际画面、LOD远距效果及整场压力测试在整包验收中单独记录。没有Android/手机FPS结论。
- 高度场生成器将场景保存为新的数据源，不能覆盖原图后称其仍为Cedar/Rivergate。若改变种子、道路、布景或高度场，需要重新生成并重跑两套检查。
