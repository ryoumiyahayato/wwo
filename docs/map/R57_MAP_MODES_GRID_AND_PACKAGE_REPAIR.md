# R57 地图模式、地貌接缝与包体整改

2026-10-21。**R57代数5交付记录；其后玩家动态验收未通过。** 代数6修复整组交接，同路径现为[代数7大陆基础续建候选](D:/programs/WWO/wwo/docs/map/R57_GLOBAL_REGION_FOUNDATION_AND_CONTINUITY.md)，仍为CANDIDATE；R56为ROLLBACK，未promote。动态故障帧及后续修复见[R57连续缩放交接报告](D:/programs/WWO/wwo/docs/map/R57_DYNAMIC_TERRAIN_HANDOFF_REPAIR.md)。下文保留代数5当时的检查结果，不代表瞬时闪动已验收。唯一[试玩EXE](D:/programs/WWO/wwo/builds/preview_2026-10-19_raster_r57/WWO_1900_Terrain_Raster_LOD_Integrity_R57_Preview.exe)。

## 画面改了什么

| 问题 | 已证实原因与处理 | 结果与边界 |
|---|---|---|
| 经济模式大片灰面，只余三角形地貌 | 未知国家统计以100%灰色覆盖有政治分区的陆地；无分区三角形保留地貌。现在无有效统计时覆盖权重为0，底图保留，并显示“数据不可用” | 原代数4的普通窗口已复现。初始每日统计为空，不能当成零满足率。没有禁用经济图或政治层 |
| 法国2度格线、深色直条 | 旧R48合成未正确使用部分来源的有效范围，又把明暗与覆盖相乘后重新当明暗读取。用现存R42/R46合法BIN重做两张受影响细片，颜色与覆盖分别处理 | 不下载DEM，不提高来源精度。保留旧BIN及替代关系。其余法国地区不能据此称为全部修复 |
| 法国250mpp崩溃 | 水文显示替换直接读取旧记录未声明的LOD字段。沿用该加载器其他位置已有的coarse/medium默认值 | 原EXE三次访问异常，工程调试窗口报出缺失字段；修复后可完成该窗口 |
| 俄国中距离比近距离显得清楚 | 500/250mpp实际选8度页，75mpp选真实2度细片。未发现粗片误覆盖。近档分类权重下降；政治着色此前未消费独立DEM明暗 | 政治墨色现在使用编码6的中性DEM明暗，地理RGB不重复加阴影。分类精度、平坦地形及粗海岸仍限制近景 |
| 历史行政线单列菜单 | 移除独立开关；政治模式自动请求既有行政显示，地理/经济模式不请求行政线 | 保留GIS、身份、拾取、视野/尺度准入和有界安装 |

法国只更换[2,48,4,50]、[4,48,6,50]两片。输出仍为1088²、编码5，11级Mip，217.178m南北格网。来源保留class10-only与全类别的原解释，不补造独立DEM通道。最大Mip量化误差约0.5/255。两片5,657,333B，较旧片少199,083B。

此前怀疑的额外内缘渐退不是这条烘焙直线的主因；最终保留原R57邻边与支持域规则。没有全局模糊、噪声、锐化或全球重制。

## 普通游戏窗口对照

均由正式菜单进入暂停的新世界，Godot4.6.3 Compatibility，1280×720，方位0，隔离用户目录。不是离线合成。最新用户截图未附在本条消息中，以下为本轮重新复现的画面，不声称还原了原截图相机。

法国中心2.3522E/48.8566N；圣彼得堡30.3351E/59.9343N。修复前经济/俄国来自R57代数4 EXE；法国250mpp来自加载故障修复后、地貌修复前的工程窗口，因为原EXE在该窗口崩溃。后图来自最终候选，均待玩家验收。

| 地点、尺度、模式 | 修复前 | 最终候选 |
|---|---|---|
| 法国500mpp，商品供应满足率 | ![灰面](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/before/france_500_fulfillment.png) | ![地理底图保留](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/final-mode-ui/france_500_fulfillment.png) |
| 法国250mpp，地理 | ![原深色直条](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/project-detail/france_250_geographic.png) | ![修复后](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/final/france_250_geographic.png) |
| 圣彼得堡500mpp，政治 | ![原500](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/before-russia/petersburg_500_political.png) | ![新500](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/final/petersburg_500_political.png) |
| 圣彼得堡75mpp，政治 | ![原75](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/before-russia/petersburg_75_political.png) | ![新75](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/final-mode-ui/petersburg_75_political.png) |

政治模式菜单：

![政治地图菜单](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/final-mode-ui/political_menu.png)

西班牙北部−7.5E/42.5N：500/250mpp选8度页，75mpp选原2度片。三个指定点的绑定及最终RGB均与代数4相同。[旧250mpp](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/before-russia/spain_250_geographic.png)／[新250mpp](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/final/spain_250_geographic.png)。**本轮没有关闭西班牙原截图中的全部网格问题。** 没有把尚未证实的规则块统一判为农田，也没有修改该地区资料。

俄国的视觉收益有限。圣彼得堡500mpp分类权重1，250mpp约0.402，75mpp约0.630；莫斯科指定点75mpp的旧粗分类权重为0，主要显示中性DEM。500/250mpp为869m输出，75mpp为217m输出；有效缩放下限约54.294mpp。没有增加放大倍率或伪造近景森林。

最终EXE完成5个地区、17次窗口观察，含地理模式往返，覆盖16种地点/模式/尺度组合；德国仅检查250mpp。地貌无读取错误，区域几何已发布。经济满足率与缺口均不再形成大片灰面；已结算统计的主题色阶未在本轮新世界中验证。

法国经济图与圣彼得堡75mpp政治图静止10/30秒，实际纹理实例、权重、指定像素均相同。连续8次切换模式，驻留纹理8、区域批次149，未递增。另做圣彼得堡连续缩放与小幅往返拖动：放大触及既有下限，缩小仍可操作，返回WORLD后仅剩world地貌纹理。未重引入冻结。

Benelux仍有186项、1个可见水文批次，须德海可见，medium完整发布。ARCHIVES滚轮38px且地图尺度不变，拖条323px；百科、help、地图反馈合并正常。有限进程间隔P95约17.5～18ms，法国模式切换观察到约455ms长间隔；不是GPU基准，不能宣称行政卡顿全部消失。

## 包体与清理

只读取嵌入PCK索引和长度，未解包或计算哈希。原PCK1,286,874,276B，文件载荷1,284,237,158B，其余为目录及对齐。按主要消费者归类，混合文件不重复计数。

| 类别 | 原包载荷B |
|---|---:|
| 地貌 | 888,246,357 |
| 物理几何及城市地理资料 | 133,998,268 |
| 政治、行政及旗帜 | 123,428,358 |
| 水文 | 69,641,454 |
| 图片、字体及UI | 21,987,481 |
| 3D模型 | 1,958,272 |
| 其他依赖 | 44,976,968 |

在原355条排除基础上，排除296份无当前运行消费者的旧Siberian衍生物，15,570,042B；MapRelief已不请求旧Siberian目录，北方/亚洲目录仍消费的同路径资产保留。再排除被本轮两片替代的旧BIN。共653条明确排除。原始资料和旧制作输入留盘，不随导出删除。

| 交付文件 | 代数4 | 代数5 |
|---|---:|---:|
| EXE，总分发长度 | 1,391,392,944B | **1,375,604,528B** |
| 其中嵌入PCK | 1,286,874,276B | 1,271,085,860B |
| 必要R56回退EXE | 1,834,465,568B | 1,834,465,568B |

总分发长度减少**15,788,416B，约15.06MiB／1.13%**，没有拆分外部PCK。当前地貌载荷872,477,232B。包内全部活动及境外保留地貌均在，653条排除路径均不在。其余主要是有效地图内容，未为容量目标删行政、水文、旗帜或降低精度。

统一入口只导出一次，原路径原子替换候选。再次执行返回unchanged，跳过导入、制作和导出。自动清退2份重复临时BIN，5,657,333B；另清理51份重复窗口图、日志、临时场景及中间索引，20,584,754B。合计53文件／26,242,087B。构建暂存已为空。

**旧普通预览EXE实际删除0份／0B。** 文件名盘点只发现R57、R56、受保护的3份Release及既有GIS工具，没有无主PCK或失败大候选。不能把已不存在的R50—R55计作节省。玩家验收并明确提升后，既有机制才清退被替代的普通回退。

本轮来源下载0B。临时BIN和正式BIN各写5,657,333B；另有一次1,375,604,528B构建暂存，已退出。研究目录清理前32,447,299B，保留14文件／12,386,994B，含11张游戏窗口图及3份必要记录。累计截图/日志覆盖写及NTFS物理写入未测量。未清空Godot缓存，未建立新来源缓存。

来源与增量描述：[来源记录](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/france_support_sources.json)、[recipe](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/recipe.json)。有限观察与容量数据合并为[一份记录](D:/programs/WWO/wwo/local-artifacts/r57-mode-repair-2026-10-21/observations.json)，原重复输出已退出。

## 仍需玩家验收

法国其他格线、原失败地点、真实存档中已有每日统计的经济图，以及持续游玩下的行政安装卡顿。西班牙抽样类别边界、近景粗海岸和来源精度限制不靠伪细节处理。本轮没有全仓回归、长期性能或全球地图验收。
