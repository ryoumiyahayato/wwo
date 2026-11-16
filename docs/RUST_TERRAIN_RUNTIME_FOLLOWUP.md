# 全球地貌运行回归

基线为 [PR #142](https://github.com/ryoumiyahayato/wwo/pull/142) 和已从 GitHub 恢复的 `terrain-surface-20261115/worldcrs84quad-15s-v2`。Z0–Z7 QPK、索引和河网沿用该候选。分层画质和全球数据验收见[逐层记录](RUST_TERRAIN_LAYER_QUALITY.md)。本轮测试运行时，正式资源切换待确认。

## 连续缩放与页预算

阿尔卑斯取景中心为 11.25°E、46.4°N，1280×720。先在 5,200 米/像素建立 Z4，再重新定位到 5,750 米/像素，进入正射投影。随后用原生滚轮缩放函数四次往返 5,750 和 6,200 米/像素，最后停在 6,200。两版各连续读回 86 个实际 Vulkan 渲染帧，每帧记录已提交页表。固定 30 帧/秒视频用于查阅。性能另在正式窗口测量。

| 6,200 米/像素 | 目标 | 视口包围页 | 含预取页 | 页预算 | 实际中心 |
| --- | --- | ---: | ---: | ---: | --- |
| PR #142 正射 | Z4 | — | 262 | 256 | Z3 |
| 修复后正射 | Z4 | 188 | 262 | 256 | Z4 `4/17/3`，权重 1 |
| 修复后纯滚轮，区域投影 | Z4 | 154 | 209 | 256 | 保持 Z4 视图 |

旧版在 86 帧内出现五次 Z4→Z3 和四次 Z3→Z4，目标一直为 Z4。新版本先调度视口覆盖页和父页，再将余下页用于预取。视口包围范围确实超预算时使用能完整覆盖视口的父层。强制单层观察沿用原优先级和缺页诊断。页预算仍为 256。视口包围范围可能含边角外的页。相邻页未就绪时，少量边缘像素仍按现有规则与父层混合。

修复后补测阿尔卑斯、羌塘 89°E、33°N、南太平洋反经线 179.85°E、17.5°S，以及 179.8°E 的南北纬 89.5°。五处各 73 个连续帧，由 28,500 缩到 360 米/像素并三次反向。三个非极区取景的视图上限跟随目标层，两极各有 23 帧因真实超预算使用较粗完整层。快速经过 Z7 适用倍率时，中心仍由已加载的父层绘制。修复后 451 帧全图无品红诊断像素。6,500 米/像素及以内的地图内部检查区域（880×485 像素）无纯黑像素。抽看转换前后，未见黑块、矩形闪烁或回落后立即反跳。结果适用于上述取景和输入。

[正射 Z4 修复前后连续帧](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/terrain-runtime-z4.mp4) · [五处快速缩放](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/terrain-runtime-rapid.mp4) · [取景和逐帧诊断摘要](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/terrain-runtime-zoom.json)

## 正式 Rust 游戏

同一 Release 模式 EXE 以 `--play --background` 串行打开隔离法国新局。原版使用默认 `worldcrs84quad-z4-v3`，候选显式指定完整 v2。测量局以 1900-01-01 暂停，保留窗口 Vulkan surface，采样时窗口未聚焦。地理、政治、经济和军事地图均完成 20 次滚轮输入。已观察到政治边界、经济就业结构图例以及军事方格开关后的叠加方格。结束时各模式所需基础地图页均为 73/73。候选地貌颜色帧解压 P95 为 0.150–0.172 ms，单次最大 0.499 ms。基础地图请求至工作线程返回最长 62.3 ms。

专项目标为阿尔卑斯。从已就绪的 720 米/像素 Z6 滚动进入 360 米/像素，约 0.67 秒后观察到 Z7 和 65 个选中页全部就绪。该时长含输入及观察回执轮询。

| 1280×720，RTX 3050 Laptop Vulkan | 原版 | 候选 |
| --- | ---: | ---: |
| 静止地理图，呈现间隔 P95 | 7.78 ms | 7.85 ms |
| 缩放，四模式呈现间隔 P95 | 7.52–7.72 ms | 7.62–8.33 ms |
| 缩放，最大呈现间隔 | 10.65 ms | 12.06 ms |
| 进程工作集 | 338–342 MiB | 336–350 MiB |
| 进程私有内存 | 744–780 MiB | 753–832 MiB |
| WDDM 专用显存 | 425 MiB | 422–454 MiB |
| WDDM 共享内存 | 104–108 MiB | 105–108 MiB |

每版缩放记录约 1,534 次窗口呈现，测时期间不截图。内存为每种模式缩放结束后的采样。该测试未覆盖长时间世界推进和军事 3D。后台异常使用观察目录记录启动错误。

[正式地图三种专题画面](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/terrain-runtime-thematic.jpg) · [正式窗口实测记录](https://github.com/ryoumiyahayato/wwo/releases/download/terrain-surface-20261115/terrain-runtime-formal.json)

## 地理来源复核

- 撒哈拉蓝线 Z5。西南利比亚野外测绘记录间歇洪流，1912 年 Ghat 谷地耕作图作历史旁证。`14.6886,27.1386`、`13.6915,25.9820`、`10.9043,25.1820` 三处的 HydroRIVERS 河段 ID 和约 1900 年水期待核对。现行全球样式用汇水面积和长期平均流量选线，常流、间歇径流共用蓝色。GIRES 可用 `HYRIV_ID` 补充现代河段分类，需核对干旱区样本限制。[测绘论文](https://doi.org/10.1080/17445647.2014.955891) · [1912 年地图图 2](https://www.cambridge.org/core/journals/antiquity/article/landuse-and-cultivation-in-the-etaghas-of-the-tadrart-acacus-southwest-libya-the-dawn-of-saharan-agriculture/BB05D0F6AAF940C5FDB8C1F58C5009C2) · [GIRES](https://www.nature.com/articles/s41586-021-03565-5)
- 格陵兰冰面河线 Z4。四处截图样本在现代冰川掩模内。遥感观测证实西南冰盖存在夏季冰面河流。具体蓝线与观测河段的对应仍待核对。当前保留河网。如果证据支持修改统一水系样式，影响范围为 Z0–Z7。[西南格陵兰季节性冰面河流观测](https://www.cambridge.org/core/journals/journal-of-glaciology/article/seasonal-evolution-of-supraglacial-lakes-and-rivers-on-the-southwest-greenland-ice-sheet/A58F5C5FA511466BA1F55C5F8399FFDC)
- 外海条带。查询 SRTM15+ v2.5.5 同版 15″ 测深来源索引，每点读取 21×21 格。几内亚湾三点位于 7.66°W、0.06°N 至 0.46°S，中心 `SID=0`，邻域分别有 21、17、2 格带来源标识。马达加斯加以东 61.8°E、17.7°S 与 18.1°S 两处细条带邻域共 882 格 `SID=0`。这一结果表示缺少原始测深来源标识。宽亮带与有船测记录的马斯克林海台相符。细带保留，成因待经独立测线核实。海深着色规则若需修改，影响 Z0–Z7。[同版 SID](https://topex.ucsd.edu/pub/srtm15_plus/) · [SID 定义](https://doi.org/10.1029/2019EA000658) · [马斯克林海台测深](https://nora.nerc.ac.uk/id/eprint/144020/)
- ESA WorldCover 2021 v200 用于现代地表参照配色。1900 年专题使用各自历史来源，1900 年地表覆盖待历史考证。[ESA 数据说明](https://esa-worldcover.org/en/data-access)

## 恢复与切换

从[候选私有 Release](https://github.com/ryoumiyahayato/wwo/releases/tag/terrain-surface-20261115) 恢复 `0.qpk` 至 `7.qpk`、`index.json`、`river-topology.u32` 到独立目录，显式传入 `--terrain-candidate`。正式原版和回退保存在 [Windows 私有 Release](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115)。本地原始逐帧读回、隔离试运行档案和临时记录程序可重建，在 `offline-map-sources/migration-20261115/terrain-runtime-20261116`。城市 3D 接地、材质、CITY／LOCAL 观察为独立后续任务。
