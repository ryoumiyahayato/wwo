from collections import Counter
import csv
from pathlib import Path
import zipfile

root = Path(__file__).parent
out = Path.cwd() / 'docs/RUST_TERRAIN_Z7_VISUAL.md'
archive = root / 'archive'
url = 'https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115'
report = (root / 'report-template.md').read_text(encoding='utf-8')
with (archive / 'z7-visual-global-pages.csv').open(encoding='utf-8', newline='') as file:
    pages = list(csv.DictReader(file))
stats = Counter(row['visual_status'] for row in pages)
completed = sum(stats[status] for status in ('PASS', 'FAIL', 'SOURCE_UNCERTAIN'))
n_complete = sum(row['capture_state'] == 'COMPLETE' for row in pages)
images = sum(1 for path in (root / 'page-results' / 'batch-y000-x000').glob('*.png') if path.is_file())
reviewed = [row for row in pages if row['visual_status'] in ('PASS', 'FAIL', 'SOURCE_UNCERTAIN')]
report = report.replace('@@DATA@@', '''完整候选 `SCAR-ADD-7.13-z7-v3` 共 1,607,880,698 字节。32,768 份压缩高程帧与原版一致，32,768 张的 BC7 解码水域通道与原版完全一致。原版相比有 818 张改色，PR #152 相比有 723 张改变颜色记录。65,280 条共享边通过，包含反经线。共享高程最大差 0 米，Z6 父层最大降采样差 0.75 米。Z6 继续使用 PR #153 候选。''')
report = report.replace('@@VISUAL@@', f'''罗斯内侧暗线减弱，例像素 RGB 从 (171,192,191) 变为 (202,217,209)。龙尼顶部狭缝和埃默里两处蓝孔消失，罗斯外缘切口及已核验的开阔水保留。局部淡色轮廓、短线和南极放射细纹仍待定位。固定 Z7 专项的全页目视结论保留在逐页表之外。

| 连续路径 | 候选帧 | GPU 回读与实绘 | 录像 |
| --- | ---: | --- | --- |
| 阿尔卑斯 530→970 米／像素，回放含返回 | 64 | 同一帧九点 Z7 权重一致，沿轮次 1→0 | [前]({url}/z7-visual-alps-530-970-pr152.mp4) · [后]({url}/z7-visual-alps-530-970.mp4) |
| 罗斯外缘冷暖间的自动 LOD 边界取景 | 70 | 视口 Z7 需求峰值 74 页，Z6/Z7 实绘切换 | [前]({url}/z7-visual-ross-front-pr152.mp4) · [后]({url}/z7-visual-ross-front.mp4) |
| 反经线，往返 | 48 | 实绘 Z6/Z7，九点混合一致 | [MP4]({url}/z7-visual-dateline.mp4) |
| 高纬视口，超预算 | 53 | Z7 可见需求峰值 512，256 页图集内实绘 Z6 | [MP4]({url}/z7-visual-polar-budget.mp4) |
| 同时缩放、平移、旋转 | 116 | 实绘 Z6/Z7，九点混合一致 | [MP4]({url}/z7-visual-zoom-pan-rotate.mp4) |
| 冷缓存连续放大 | 59 | 按页就绪从 Z4 向 Z7 切换 | [MP4]({url}/z7-visual-cold-alps.mp4) |
| 固定 Z7，罗斯冰面跨页及角点 | 32 | 实绘 Z7、权重 1 | [MP4]({url}/z7-visual-ross-ice-corner.mp4) |

442 帧候选和 267 帧对照由同一 Rust/wgpu 离屏管线采集。实拍复核片段未见逐块矩形淡入或缺页黑块。超预算路径整幅退到 Z6，清晰度变化可见。阿尔卑斯候选的离屏相邻捕获间隔 p50／p95 为 44.08／45.41 ms，对照为 40.96／44.81 ms。此路径包含 GPU 回读；正式游戏 FPS、专用显存和前台性能本轮为 NOT_RUN。发布录像用 20 FPS 顺序编码，无插帧。原帧的捕获时间、机位、视口需求、页状态、可见贡献和九点采样见 [连续帧回执]({url}/z7-visual-motion.json.gz)。'''.replace('罗斯外缘冷暖间的自动 LOD 边界取景','罗斯外缘自动 LOD 往返'))
report = report.replace('@@BATCH@@', f'''首批 `X=0…7, Y=0…7`。GPU 已取得两档完整覆盖 {n_complete} 页，{images} 张页专属 PNG，另有南北极各两档。实际逐页目视完成 **{completed}／32,768（{completed/32768:.3%}）**。PASS {stats['PASS']}，FAIL {stats['FAIL']}，SOURCE_UNCERTAIN {stats['SOURCE_UNCERTAIN']}，NOT_RENDERED {stats['NOT_RENDERED']:,}，PENDING {stats['PENDING']}，REVIEW_INCOMPLETE {stats['REVIEW_INCOMPLETE']}。尚未完成逐页目视 {32768-completed:,} 页。

本批 64 页均已逐张判读。北极辅助图覆盖常规视角最北端的窄带，共用原图在每个相关页记录中明确列出。北冰洋 `7/0–3/0` 在区域 02/05 与近景 04/08 等镜有淡细纹，`7/2–3/3` 的重叠近景 00 有短纵暗纹。均登记 SOURCE_UNCERTAIN。经纬度、原始 PNG 和复核人见 CSV。下一批按 `X=8…15, Y=0…7` 续审。

![首批 64 页导航](terrain-z7-visual/batch-y000-x000.jpg)

续拍使用上一版本已验证的 Rust 宿主。先恢复本次索引指定的候选资源。每个取景保留实际 Z7 回执，逐张复核时从原图路径读图。重新索引应同时提供已经归档的上批 ZIP 和原有人工记录。

```text
python rust/strategic-host/tools/capture_z7_pages.py --exe <Rust宿主> --data <只读游戏数据> --terrain-candidate <候选目录> --program-revision <实际程序提交> --out <实拍目录> --batch-x 8 --batch-y 0
python rust/strategic-host/tools/index_z7_pages.py --captures <实拍目录> --out <归档目录> --review <已查看原图的记录.csv> --batch-x 8 --batch-y 0 --zip
```

[全球逐页 CSV]({url}/z7-visual-global-pages.csv) · [首批原始 PNG 及同帧坐标和状态]({url}/z7-visual-batch-y000-x000.zip) · [八个原坐标 24 张原图及两极图]({url}/z7-visual-site-png.zip)。''')
report = report.replace('@@RESTORE@@', f'''格陵兰、撒哈拉、博斯腾水线，马斯克林条带及南北极细纹仍有来源或根因留项。南极 v3 与 PR #153 Z6 的固定暖缓存专项已进行 GPU 衔接复验。Z5 沿用旧冰架材质，待下一层核对。Z7 全层视觉结论仍为未完成，正式地图待用户验收。

[完整候选]({url}/z7-visual-7.qpk) · [合用候选索引]({url}/z7-visual-index.json) · [全球层和受影响页记录]({url}/z7-visual-global.json) · [原始像素及位置]({url}/z7-visual-ice-gpu-points-local.json) · [SCAR 输入]({url}/z7-detail-scar-add-7.13.json.gz) · [PR #152 候选]({url}/z7-detail-7.qpk) · [原版回退]({url}/7.qpk)。

从原版 `7.qpk` 和解压的 SCAR 数据重建，按候选索引合用已有的 PR #153 Z6 与基础各层。

```text
python rust/strategic-host/tools/build_natural_terrain.py --refine-ice-shelf-edges --ice-shelf-candidate <原版7.qpk> <SCAR_ADD.json> <隔离目录/7.qpk>
```

{(root/'restore-report.md').read_text(encoding='utf-8').strip()}
''')
out.write_text(report, encoding='utf-8')



