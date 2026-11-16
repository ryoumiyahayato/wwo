# Z7 地貌与接缝验收

日期 2026-11-16。数据使用 PR #142 的 `worldcrs84quad-15s-v2/7.qpk`。程序基线为 PR #143，`main` 提交 `389c0da4`。运行时修正在 Z7 自动精度路径生效。Z7 的独立观察和 Z0–Z6 的数据与生成规则沿用原版。

## 全球数据

| 检查 | 结果 |
| --- | --- |
| 全层读取及解码 | 32,768 页，256 列 × 128 行，QPK 1,607,792,383 字节。142,737,408 个 BC7 块具有有效模式前缀。 |
| 同层边与四角 | 65,280 条共享边，含反经线。跨边重叠的高程最大差 0 m，BC7 块一致。65,024 组对角比较一致。比较包括真实 4 像素边缘填充和相邻的内部采样。 |
| 极区 | 512 张极边页的高程填充与极边采样一致。BC7 解码后极边填充最大 RGBA 差 2/3/2/1（8 位），与 BC7 压缩块的邻域差异相容。 |
| Z6 父层 | 依照相同格网做 2×2 高程缩减，最大差 0.75 m。本项仅为 Z7 的父子关系检查。 |

## 地理与画面

复用 [已冻结的七洲取景和专项画面](RUST_TERRAIN_LAYER_QUALITY.md)。2026-11-16 补充四个预定取景，实际绘制均为精确 Z7，九点无父层或缺页。坐标依次为经度、纬度，倍率单位为米／像素。

| 取景 | 瓦片 | 结果 |
| --- | --- | --- |
| 北美中部平原，−93.51 / 42.47 / 430 | `7/61/33` | 低缓起伏和成网排水可辨，未见矩形边。细河的季节性和历史水量待查。[USGS 地貌](https://pubs.usgs.gov/circ/circ1210/introduction.htm) |
| 格陵兰冰盖，−47.866 / 68.165 / 345 | `7/93/15` | 多条近等宽的高对比蓝线，部分连到冰缘及峡湾。区域存在实测夏季融水河，截图上的具体线段和常年蓝色着色仍待核实。[冰面河实测](https://www.cambridge.org/core/journals/journal-of-glaciology/article/seasonal-evolution-of-supraglacial-lakes-and-rivers-on-the-southwest-greenland-ice-sheet/A58F5C5FA511466BA1F55C5F8399FFDC) |
| 几内亚湾，−7.66 / −0.20 / 430 | `7/122/64` | 旧报告点位都在图内。本帧见淡色斑，未辨认出细直条或网纹。 |
| 马斯克林海台，61.80 / −17.90 / 430 | `7/171/76` | 左侧可见渐变色带。宽带与实测海台位置相容，旧报告的两处细条仍缺独立测线归因。[测深资料](https://nora.nerc.ac.uk/id/eprint/144020/) |

复核的既有取景包括阿尔卑斯、喜马拉雅与羌塘、北非沙漠、Óbidos 河谷、博斯腾湖、湄公河及密西西比三角洲、瓦登海、多佛海峡、科斯雷、南极半岛和开阔北太平洋。山脉、平原、河谷、岸线、海岛、主要湖盆与三角洲能够辨认。羌塘维持草地／岩土，喜马拉雅及南极有冰雪。撒哈拉北缘和博斯腾湖东侧的蓝线仍缺河段级来源与水期。河网筛选依据汇水面积或长期平均流量，固有线宽属视觉表达。[HydroRIVERS](https://www.hydrosheds.org/products/hydrorivers)

Z7 的每个采样间隔为 19.77539″，南北约 611 m，东西随纬度缩短。母源 SRTM15+ 的名义网格为 15″，海上含卫星推算。现有页不能验证细支流实际河宽、单个珊瑚礁或独立冰面河道的季节变化。Natural Earth 的 1:10m 水岸与冰川边界亦会概化。此轮保持母数据和材质。地表覆盖是现代 WorldCover 2021 v200，画面上的 1900 是游戏日期。历史海图可以核实部分主要河口分汊的存在。[SRTM15+](https://doi.org/10.1029/2019EA000658) · [WorldCover](https://esa-worldcover.org/en/data-access) · [湄公河旧图](https://humazur.univ-cotedazur.fr/s/henri_bosco/item/24387) · [密西西比旧图](https://louisianastatemuseum.org/map-collection/results-discharge-measurements-passes-mississippi-river)

## 同层接缝

锁定 Z7 连续采集 192 帧。阿尔卑斯、亚马孙、瓦登海和反经线各 35 帧，经过共同边和四角并缩放、平移和旋转。阿尔卑斯与瓦登海再各拍 26 帧倾斜取景，105 米／像素，倾角 15.23°。每帧九个点均为实绘 Z7，没有缺页。抽看的河谷、山脊及海岸未见明显硬直边、黑块或亮线。反经线取景经纬度为 179.9999 / 66.09375，接触 `7/{255,0}/{16,17}`。极区数值复核见上，真实画面复用精确 Z7 极区静帧。

QPK 高程用于地貌源和接缝数据验证。该观察入口以地球面渲染地貌材质。斜向帧验证的是地球面投影下的纹理、阴影和接缝。

## Z6 / Z7 跨层接缝与连续操作

基线在阿尔卑斯 11.25 / 46.40625 / 530 固定视角复现矩形贴片。帧号从 0 起。第 14 帧中心 `7/136/31` 权重 53.95%，`6/68/15` 权重 46.05%，其余八点均为 Z6。实际像素变化以瓦片边界呈 T 形展开。第 28 帧中央矩形仍有 7,593 像素与稳定帧不同。第 29 帧起抽查的同一区域与稳定帧一致。第 77 帧全部选中页就绪。原因是 Z7 页独立淡入，而页缘的 4% 混合只对齐边缘和角点。

修复让可见 Z7 和父层准备好后使用同一个全视口权重。利用已有预取范围提前降权。单个后台线程仍逐页读取，每帧最多发出三项请求。图集容量仍为 256 页。实际图集页索引、Z/X/Y、混合权重、回退与加载状态列于逐帧回执。在相同 530 米／像素取景，修改后第 9–22 帧中央像素一致，期间 Z7 驻留页增至 42 张。第 23–30 帧各点一起提升 Z7 权重，最终与精确 Z7 同取景中央区域逐通道一致。未复现 T 形覆盖。

候选实际离屏记录 746 帧自动 LOD，另有上述 192 帧精确 Z7。含冷缓存放大、暖缓存慢速缩放、快速反向、临界倍率往返、缩放同时拖动与旋转、反经线。自动回执的九点 Z7 权重在每一帧一致。938 帧中央地图区域未出现纯黑或诊断洋红像素。单帧 530 → 970 米／像素时需覆盖 122 张 Z7 页，当时缺 32 张，整体直接回退至 Z6。实帧可见伴随拉远的清晰度下降，抽看的连续帧未见黑亮闪或局部拼贴。此动作不具备连续淡出保证。

## 正式游戏加载与性能

同一 Windows 测试机，RTX 3050 Laptop GPU / Vulkan，1280×720。使用正式 Rust `--play --background`、独立配置及暂停的新会话。窗口实际呈现且未获得焦点。地理、政治、经济和军事地图均已切入并完成轮滚及拖动。帧间隔为此后台窗口的实际提交间隔，内存为 Windows 进程采样。

| 项目 | PR #143 | 本轮 |
| --- | ---: | ---: |
| 阿尔卑斯 1150 → 530，冷 Z7 全部选中页就绪 | 0.89 s | 0.64 s |
| 地理静止帧间隔 P95 | 7.40 ms | 7.40 ms |
| 地理操作帧间隔 P95 / 最大 | 7.39 / 8.92 ms | 7.38 / 11.16 ms |
| 地理操作后工作集 / 独立显存 | 345 / 469 MiB | 367 / 466 MiB |

候选其他三个专题的操作 P95 为 7.29–7.41 ms，工作集约 394 MiB，独立显存约 466 MiB。未验证玩家实况会话或更高分辨率。资源与正式切换保持独立。

## 归档

- 复用完整 [Z7 QPK](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/7.qpk) 与同发布的 `index.json`、Z6。正式回退归档为 [rust-native-windows-20261115](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115)。
- [同取景修复前后连续帧](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-seams-before-after.mp4) · [跨层和固定层连续帧](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-seams-motion.mp4) · [像素变化范围](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-seams-pixel-footprint.png) · [逐帧回执、全球检查及正式窗口帧时](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-seam-observations.json.gz)
- [格陵兰冰面](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-reference-greenland.png) · [马斯克林海台](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-reference-mascarene.png)

## 530 → 970 米／像素专项收尾

阿尔卑斯与瓦登海各以相同中心、无旋转、1280×720 连续比较自动 LOD、锁定 Z7 和锁定 Z6。锁层对照在先加载的 970 米／像素取景下准备好广域瓦片，再回到 530 执行相同输入。每条保留 64 个 GPU 帧。帧号从 0 起，第 11 帧为 530，第 12 帧跳至 970。

| 中央画面 960×450，8 位亮度值 | 阿尔卑斯 | 瓦登海 |
| --- | ---: | ---: |
| 自动 LOD，整个缩放的亮度平均绝对差 | 28.47 | 21.81 |
| 始终锁定 Z7，单纯缩放的亮度平均绝对差 | 29.69 | 22.26 |
| 同为 970，纯 Z7 与自动 Z6 的亮度平均绝对差 | 4.78 | 2.37 |
| 同为 970，LOD 单独造成的平均亮度偏移 | +0.10 | +0.06 |

自动第 12 帧的中央区域与相同倍率的纯 Z6 对照及自动第 13 帧逐像素一致。缩放扩大取景是明暗和颜色变化的主因；LOD 另有局部纹理阶跃。历史暖缓存缺 32 张，本次阿尔卑斯冷路线缺 58 张。单帧直接越过预取缓冲，推进前无法保证新视口所需瓦片齐备。现有整幅回退保留，弱化局部细节的变化仍发生在一帧。附 [同输入连续画面对照](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-fast-jump-comparison.mp4) 和 [回执](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/z7-fast-jump-frames.json.gz)。
