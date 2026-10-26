# 虚构训练地形：分层观察最小资源 v1

本目录按需复用原归档字节，不重新生成地形，也不恢复完整军事运行时。
地形全部为虚构训练场景，**不是历史测绘或正式世界地理事实**。主仓用于分层训练/观察，并有基于局部地形真实碰撞的步行交互；局部碰撞步行不等于恢复军事实体、策略、AI、战斗、车辆或权威世界状态。
本资源包只交付下列 24 个原文件及来源、说明；交互代码与 Godot 导入设置由主仓提供，不包含在附件里。

## 已恢复内容

保留原运行时的路径子目录和文件字节。24 个资产合计 **13,178,169 字节（12.568 MiB）**。

```text
continuous/assets/
  height_50m.f32                 4,008,004 字节
  region.json                      40,702 字节
  region_color.png                284,891 字节
  region_normal.png               104,062 字节
ridgevale/assets/
  height_4m.f32                  6,260,004 字节
  map.json                         40,494 字节
  land_color.png                1,109,166 字节
  land_control.png                 38,273 字节
cedar/assets/
  grass_detail.png                406,083 字节
  soil_detail.png                 373,041 字节
  stone_detail.png                301,833 字节
  barn.glb / chapel.glb / hay_roll.glb
  house_0.glb / house_1.glb / house_2.glb
  rock_0.glb / rock_1.glb / rock_2.glb
  tree_0.glb / tree_1.glb / tree_2.glb
  wall_4m.glb                     13 个模型合计 211,616 字节
```

13 个 GLB 的原始 JSON 块均为单个 mesh，未引用外部 buffer 或 image URI。模型不是占位几何。Ridgevale 原地图的 186 个 placement 所引用的 11 种模型均已包含；另附极小的 chapel 和 hay_roll。

**命名差异：**所请求的 `cedar/assets/rock_detail.png` 不存在于当前运行时 manifest；原材质实际使用 `cedar/assets/stone_detail.png`。恢复使用真实名称，未伪造、复制或改名为缺失文件。原 Ridgevale 材质需要的 land_color 也已恢复。

## 读取约定

- Continuous：50,000 × 50,000 米；XZ 边界 `[-22500, -22500, 27500, 27500]`。高度网格 `1001 × 1001`，间隔 50 米，little-endian float32，按 Z 行、X 列排列。
- Ridgevale：5,000 × 5,000 米；XZ 边界 `[-2500, -2500, 2500, 2500]`。高度网格 `1251 × 1251`，间隔 4 米，little-endian float32，按 Z 行、X 列排列。
- Continuous 原文标明 `training_only: true`。Ridgevale 是原生细地形子区；不是用虚构记录替代真实世界地点。
- 原元数据中的 `res://cedar/assets/` 是归档运行时路径。主仓观察层需解析为本目录下的对应子路径；未修改原始 JSON。
- 未恢复原运行时的整套 terrain GLB tiles、Godot 导入缓存、场景、着色器或脚本。不能将本目录描述为完整可直接启动的军事工程。主仓观察层可由两个原始高度场按需建立显示网格及局部碰撞。
- Rivergate、Cedar 和 Atlas15 **均未完整恢复**。这里的 Cedar 仅为列出的材质和 13 个模型，不代表整个 Cedar 场景、地形或军事实体齐备。

## 云附件安装

版本附件名：`wwo-region-slice-ridgevale-v1.zip`，存放于同一用户既有的 [WWO 草稿资源 Release](<https://github.com/ryoumiyahayato/wwo/releases/tag/untagged-75a9dbc800223cbf8a18>)（id `422607066`）。这是资源附件，不是游戏导出；保持草稿，不发布或 promote。

在主仓根目录执行，需 Python 3 与已登录且可访问该草稿的 `gh`。安装器只下载此版本附件，不下载原来的大型分卷归档：

```powershell
python tools/map/install_region_slice.py
```

本机指定解释器与离线复用方式：

```powershell
& "C:/Users/agcrf/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/python.exe" -B tools/map/install_region_slice.py --from-zip local-artifacts/region-resource-package/wwo-region-slice-ridgevale-v1.zip
```

包内相对路径直接对应本目录：24 个原资产、未经改写的来源记录和本说明，共 26 个文件；不含 `.import`、导入缓存或新摘要清单。附件与解压范围均小于 20 MiB。原 `*.f32`、`*.png`、`*.glb` 通过云附件交付；主仓保留元数据及导入设置。

安装器按来源记录的真实顶层 `source_archive_commit` 及 `files[].relative_path` / `files[].bytes` 读取。已有同字节文件直接复用；任一现存文件不同即停止，不覆盖。缺失文件排它新建，只写包内原字节，不计算 SHA、MD5 或其他指纹。安装不会运行 Godot、build、测试或导出。

## 归档来源与传输边界

- 原仓：`ryoumiyahayato/wwo`。
- 原草稿 Release id：`422607066`；实际 tag：`untagged-75a9dbc800223cbf8a18`。
- 原归档提交：`3c48266b335cfa448953d26b9698abb6dd207a34`。
- manifest 只读来源：军事仓固定提交 `44c8f3d0639f7b84a0053d7edfa76641cb8a50d7`，路径 `provenance/archive/manifest.json.gz`；以 Git 输出流在内存解压，未改军事仓。
- 原路径前缀：`formal-combat-authority-20261024/runtime/`。
- 唯一 ZIP：`military-current-0001.zip`（443,505,922 字节）。只读 part001、part002 的必要数据段与 part007 的 ZIP 尾部/中央目录。
- 首先用尾部请求确认 HTTP Range：返回精确 `206` 与 `Content-Range`，之后才读取中央目录并定位原有对象条目。
- HTTP 响应体实际传输 **12,123,525 字节（11.562 MiB）**。未下载任一完整 part，未下载整个 ZIP 或 7.2GB 附件集合。临时二进制下载落盘 **0**。传输与资产均小于 20 MiB 预算；临时目录只含恢复脚本、选择 recipe、原路径列表和范围请求记录。

详细原路径、既有 ZIP 条目名、局部头/压缩数据偏移、压缩/解压字节、附件 id 和 HTTP 范围记录见随包保留的 [RECOVERY_SOURCE.json](<RECOVERY_SOURCE.json>)。该记录描述原始恢复过程，未为云交付改写。

原恢复未主动计算 SHA、MD5、ZIP CRC 或其他摘要；没有生成指纹清单。记录中的 ZIP 对象条目名直接来自原 manifest，用于定位数据，不是本次计算结果。恢复范围确认仅包括 HTTP 范围、ZIP 元数据、成功解压与原 manifest 的字节长度。v1 只以标准 ZIP 重新封装原字节和说明，不另建 hash 或指纹；ZIP 格式自带的校验字段不是新来源清单。**本次云资源交付未启 Godot，未运行引擎验证、测试、审计、build 或游戏导出，未执行 Git 操作；安装实测不等于实机验收。**
