# 分层军事地貌与原生隔离训练

## 范围与原入口

原菜单“开始”→合法人物→原正式世界→地图模式“军事地貌 · 50 / 25 / 5 km”。仍是原 FormalWorldApplication；观察层暂停正式时间、隐藏旧视口和输入，返回恢复同一 WorldState、人物、地图相机与选择。不另建正式世界、时钟、存档或正式单位。

唯一安装地区为 **Continuous 50×50km + Ridgevale 原生5×5km**。外围高度源50m、原生高度源4m；25km是同源缩放，不是第二份地区。虚构训练数据尚无历史地理配准。村庄细资产集中中央约800m；河流在外围，不宣称原生村内有河。显示细化与原生运行时的1m插值都不是新增测绘精度。

正式军事绑定未完成不再阻止隔离玩法：本次接回原坦克、五人车组、上下车、有限弹药、火控、实体炮弹与原装甲/人员伤损。**隔离训练身份不是所选正式人物，结果不写正式存档，不生成正式军队或经济事实。**

## 安装及资源预算

沿用[原安装器](../../tools/map/install_region_slice.py)与已认证的 GitHub CLI：

```powershell
python tools/map/install_region_slice.py --with-training
# 已有本地附件时，不重复下载：
python tools/map/install_region_slice.py --from-zip TERRAIN.zip --training-from-zip MODELS.zip
# 只装原训练模型，不触发地形下载：
python tools/map/install_region_slice.py --training-from-zip MODELS.zip
```

不带新参数的旧用法仍只安装地形。相同目的文件逐字节复用，不同文件拒绝覆盖；原资源与有效Godot缓存不清理。首次用Godot4.6.3导入PNG/GLB后从原入口运行。

- 地形：既有草稿资源归档 tag `untagged-75a9dbc800223cbf8a18`，附件 [wwo-region-slice-ridgevale-v1.zip](https://github.com/ryoumiyahayato/wwo/releases/download/untagged-75a9dbc800223cbf8a18/wwo-region-slice-ridgevale-v1.zip)，asset **677929012**，11,756,695B；24个原资产13,178,169B，未重打包。
- 训练：同一既有草稿中新增 [wwo-native-training-models-v1.zip](https://github.com/ryoumiyahayato/wwo/releases/download/untagged-75a9dbc800223cbf8a18/wwo-native-training-models-v1.zip)，asset **678390340**，460,008B；8个原GLB共2,855,928B，连来源说明解包2,863,130B。压缩包和解包均限4MiB，固定8路径白名单；9个原小JSON以源码交付。该上传不是游戏Release发布。
- 本轮17个必要原资产由既有归档范围读取恢复：18次206响应合计868,080B，原文件合计2,995,531B；没有下载完整大分卷或恢复全部地图/车型。沿用[原来源及范围记录](../../military_runtime/TRAINING_ASSETS.json)，未新增摘要清单。

原始GLB仍须可被FileAccess读取，供原 armor_collision 来源检查使用；不能只留Godot imported remap。导出过滤只为native命名空间保留原GLB，本轮**未执行导出**。其余未恢复车型、换靶、重建场景及弹药恢复入口锁定，不能用选择器补满状态。

## 实际控制

- 50km选5km格，25km/滚轮连续缩放；左拖平移、右拖旋转、WASD移动观察相机。只有标注已安装的Ridgevale可进原生细区，其它格不冒充精细地图。
- “村庄 / 道路”观察原房屋、石墙、树和地表语义。“步行观察（隔离）”是无武装CharacterBody3D，用真实局部地形/建筑碰撞；不是正式人物移动。
- “原生坦克训练（隔离）”进入原军事控制器。WASD实际驱动车体/履带并转向、松键制动；空白区域左拖看向，右键使用原瞄具，Space或原“开火”按钮走主炮规则。原机枪沿用原hitscan，不将它称为实体炮弹。
- 原右上角军事菜单保留车组及瞄具控制；右下角原出入车图标供车长下车/返车。下车须车速合规且真实出口安全；返车须原空座、距离、活人及LOS合规。不能直接转移人物位置或补伤弹。
- 主机“暂停并观察 / Esc”或原军事菜单“返回观察”暂停同一训练会话；“恢复原训练”保留原车、车组、弹药及靶损。**“返回正式世界”明确结束该隔离会话**，不是免费重置正式单位。
- F12记录实际活动相机、地区及训练状态；不把隐藏球形相机当当前视图。没有自动保存。

## 问题、根因与针对性改动

[高度源](../../scripts/presentation/terrain/terrain_height_source.gd)、[分层节点](../../scripts/presentation/terrain/layered_terrain.gd)与[共同地表shader](../../shaders/presentation/terrain/layered_ground.gdshader)共用原数据。

1. **不是原高程的大断层。** 原生4m与外围50m在边界原采样最大差约0.02355m；250m显示边相对原生最大约0.58m。主要可见方块来自不同albedo/法线解释、旧额外山体明暗和无mipmap纹理，以及显示拓扑交界。没有抬平原生4m高度来遮缝。
2. **共用连续世界尺度外观。** 原Y-up区域法线按原RGB解释，不当切线蓝法线；移除旧5倍法线起伏与额外hillshade，区域macro连续覆盖各层级。七张原纹理开启mipmap，细粒纹/控制语义按屏幕导数渐入，原生边缘128m渐变；不加全局雾或整图模糊。控制图8–64m/px渐入使5km仍可辨中央道路/围合，不以统一草色删除其语义。
3. **不是用新裙边遮本组件接缝。** 粗侧边加细分顶点与扇形三角连接20m/4m、250m/原生边界；保留原4m顶点和b-c对角，不改碰撞高程。原生20m概览拆100个500m块并跨视距保留，不在8500m处整块替换；近景最多9块改为4m，准备好才原子替换。
4. **有界安装，不宣称消灭所有尖峰。** 单工作线程；每帧最多一个mesh安装。观察碰撞只为焦点±64m生成最多9个100m块，使用原4m、25×25格及同b-c三角；不从GPU mesh读回构造碰撞，不建整50km或整5km碰撞。last/max计时是对应CPU调用区间墙钟，不是GPU执行时间。
5. **原生训练只保留一个活动近景owner。** 训练使用原 Ridgevale/streamed_battle_terrain 的编辑、support、碰撞与事务；原4m场双线性生成其原1m网格，采样与该碰撞约定一致。观察节点让出近景；暂停清零native碰撞layer/mask后交回观察，恢复反向交接。同一观察SubViewport/World3D/环境/灯光，不安装第二套World3D或改全局物理频率。训练编辑只保留于该会话，不写回原资源/正式世界。
6. **生命周期及原权威不变。** 原default_request只安装一次；五个稳定person_id，车长HP7/左臂injured，原主炮40发已耗AP6/HE2/SMK1、余31。射击由原炮口、炮手、装填、弹药提交、实体飞行/接触与装甲/人员规则执行；没有强制命中、修改forced_roll、免费补弹或治疗。静止按需UPDATE_ONCE，移动、装填、弹丸、VFX和地形工作请求帧；不隐藏常跑原球形视口。

军事仓[PR3](https://github.com/ryoumiyahayato/wwo-military/pull/3)保留独立可复用模块；主仓[PR126](https://github.com/ryoumiyahayato/wwo/pull/126)负责嵌入。原运行码只作受控namespace/resource适配，新增适配边界见[原生训练API](../../military_runtime/native/modules/isolated_training/README.md)。军事源码库无独立完整main/全部原资产，不把主宿主验证写成该库独立启动通过。

## 已运行的有限真实窗口与仍未关闭的性能问题

2026-10-26，Godot4.6.3标准版、Compatibility/OpenGL、RTX3050 Laptop、1280×720无焦点原生窗口。使用PR126的main基线临时检出和原有资源，避免共享经济工作树的未完成UI改动；不新建演示main场景。正常菜单→合法人物→原正式世界→50/25/5km→村庄→物理步行→原坦克→原车长往返→观察/区域/正式世界，末轮退出0。

- 实际驾驶25.843m，原地面support已加载。两发AP余弹31→30→29；第一发真实飞行0.03746s撞左侧50mm装甲未穿透；第二发0.04712s、7.540m撞背面35mm并穿透。rear完整度100→85而厚度仍35；靶三乘员HP10/10/10→7/6/8，均存活且有原伤损。没有强制成功。
- 同一原车长下车实走3.446m，离车曾6.310m，按原入口返原seat0；HP7/左臂伤及有限弹药未恢复。装填剩时正常推进，不声称所有弹药字段静止。
- 原driver比较报告sameActor、sameVehicle、sameSession、暂停前后状态、正式世界实例/完整快照/人物/相机选择保持；正式分钟0。它没有内嵌所有前后raw快照或instance数值，不夸为独立重算全部裁决。

下表区分同机修前基线、实施后首轮与末轮，不挑最快一轮冒充稳定结果：

| 阶段 | 修前 P95 / max，ms | 实施后首轮 | 实施后末轮 |
|---|---:|---:|---:|
| 5km静止 | 18.074 / 19.737 | 17.906 / 18.861 | 17.661 / 18.251 |
| 进入村庄细节 | 17.910 / 55.443 | 17.602 / 18.177 | 33.405 / 55.900 |
| 步行运动 | 17.751 / 21.701 | 17.896 / 152.532 | 34.140 / 167.555 |
| 训练驾驶 | 未接通 | 19.252 / 25.131 | 35.486 / 37.884 |
| 暂停训练观察 | 未接通 | 17.825 / 18.320 | 18.228 / 33.506 |

**尖峰未解决。** 末轮mesh安装生命周期max2.243ms，碰撞安装区间max51.777ms；没有时刻对齐，不能说后者就是167.555ms的根因，也不能用last约2ms排除碰撞。活动阶段一起变慢，不能无证据归因shader、LOD或硬件。帧间隔包含等待；process/draw计数仅阶段末快照，不是峰值帧调用栈。CPU约1秒、GPU约2秒稀疏采样，整GPU包含桌面负载，不能叫纯游戏GPU时间或长期功耗。首轮观察工作集约1.15–1.25GiB，训练约1.30GiB；末轮步行约1.15GiB且短窗基本稳定，不外推其它机器或长时场景。

原记录保留在本地 `local-artifacts/layered-battle-20261026-before/`、`local-artifacts/battle-main-review/`、`local-artifacts/battle-main-final/`。失败的共享工作树启动（经济UI未编译）、被其它Godot进程占用而拒绝启动的尝试，均未计通过。两轮成功日志无SCRIPT ERROR/ERROR，仍有原globe锚点及SubViewport/get_screen_transform警告，不宣称无警告。

### 2026-10-27 菜单避让复核

发现主机暂停按钮覆盖原军事菜单中心，已只向左避让；车长离车时横幅不再误显示车速。原窗口再次走完同一玩法路径，实际点击原军事菜单、主机暂停按钮、恢复按钮和原菜单返回观察，均由原UI完成，退出0。新安装器在Git规范换行的检出中复用全部8个GLB（Installed0/reused8），未覆盖文件。

该轮步行P95/max为17.895/42.537ms，驾驶19.471/24.484ms，转向19.700/24.004ms；mesh/shape安装生命周期max4.310/6.513ms。**没有实施新的性能修复，不能把更快的一轮解释为167ms尖峰已被消除**，也不覆盖前轮退化事实。记录保留在本地 `local-artifacts/battle-ui-20261027/`，仍有上述两类警告。

## 明确未完成

- 同步碰撞安装慢区间、活动帧节奏下降、步行167.555ms尖峰的根因及修复仍未关闭；上述实机功能通过不等于性能验收或用户接受。
- 未本轮实测HE/SMK/MG、来袭伤害、受阻/移动车上下车拒绝、其它座位多人转移、长距离坡障、移动端/多分辨率、长时功耗、保存重载或正式部署。沿用原规则不等于这些分支已通过。
- 没有历史地理配准、正式军事实体/控制权绑定、完整Cedar/Rivergate/Atlas15、全局军事或经济AI扩建。原程序化低面数art仍未达商业战争游戏美术质量。
- 没有全仓回归、Windows导出、游戏Release发布/promote、PR合并或原资料清理。素材权利按原来源保留，不据此宣称全部开源。
