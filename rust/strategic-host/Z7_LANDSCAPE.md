# 全球 Z7 森林和山地实机记录

`wwo-map-lab --play`，地理模式，RTX 3050 Laptop Vulkan，1280×720，俯视且北朝上。近景用现有常规地图最大滚轮倍率。QPK 来自 [Rust Windows 2026-11-15 归档](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115)。Z7 的 `7.qpk` 为 1,608,178,325 字节。新增 `landscape-cover-v1.qsc` 为 58,133,027 字节。

## 七洲抽样

首张截图前冻结名单。抽样 Z7，种子 2026111907，CPython 3.14.6 MT19937 `random.Random.choice`，Shapely 2.2.0。Natural Earth Admin 0 Map Units 1:110m v5.1.1 与 v5.1.2 分发版 1:110m Land GeoJSON 取相交陆地。沿用上轮欧亚分界近似，印尼东经 131° 以东陆块归大洋洲。排除上轮七个 Z7 分片，按 Z/X/Y 等概率抽取。[冻结名单](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/frozen-samples.json)

两档均用方位等距投影，210 和 25 米／像素。表内是稳定帧实际采样中心分片。每档从运行时已提交页表抽查中心与八个视口边缘位置，七洲稳定帧均为 Z7，中心权重 1。岸线和河道使用 QPK。

| 洲 | 经度、纬度 | 中心分片 | 观察 | 实拍 |
| --- | --- | --- | --- | --- |
| 亚洲 | 44.296875, 30.234375 | 7/159/42 | 荒漠低地，近景无森林。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-asia-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-asia-25.png) |
| 欧洲 | 41.484375, 58.359375 | 7/157/22 | 林冠和河谷，河道沿用 QPK。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-europe-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-europe-25.png) |
| 非洲 | 31.640625, 20.390625 | 7/150/49 | 荒漠与河谷，近景无连续森林。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-africa-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-africa-25.png) |
| 北美洲 | −113.203125, 44.296875 | 7/47/32 | 山脊、裸坡和针叶林。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-north-america-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-north-america-25.png) |
| 南美洲 | −58.359375, −26.015625 | 7/86/82 | 低地阔叶林斑块和林缘。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-south-america-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-south-america-25.png) |
| 大洋洲 | 137.109375, −17.578125 | 7/225/76 | 低地林丛和开阔地。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-oceania-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-oceania-25.png) |
| 南极洲 | 144.140625, −83.671875 | 7/230/123 | 冰盖。区域图初期混入 Z4–Z6，稳定后为 Z7。 | [210](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-antarctica-210.png) · [25](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-antarctica-25.png) |

## 固定检查

- 179.98°E、16.7°S 跨反经线，边缘使用 `7/255/75` 与 `7/0/75`，均完整驻留。[反经线](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-dateline.png)
- 极点视口按经度扇入，Z7 需要超出 256 页缓存预算。北极和南极都经历 Z5，稳定回退到 Z6。25 米／像素时中心分别使用 `6/75/0` 和 `6/116/63`。[北极](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-north-pole.png) · [南极](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-south-pole.png)
- 11.25°E、46.40625°N 在四个 Z7 分片交点。稳定边缘用 X135–136、Y30–31，观察到山谷和林带跨页。48 米／像素仍有渐隐实例，75 米／像素为地表层。645 米／像素使用 Z7 与 `6/68/15` 混合，920 米／像素使用 Z6。返回最大缩放后林冠位置一致。[四页交界](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-alps-page-edge.png) · [Z6/Z7 混合](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/survey-alps-z7-blend.png)
- [亚马孙阔叶林](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/landscape-amazon-z7.png) · [加拿大针叶林](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/landscape-british-columbia-z7.png) · [多洛米蒂](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/landscape-dolomites-z7.png) · [喜马拉雅](https://github.com/ryoumiyahayato/wwo/releases/download/z7-landscape-20261119/landscape-himalaya-z7.png)

## 运行开销

| 场景 | 秒 | FPS | P95 帧间隔 | 工作集峰值 | 私有内存峰值 | 专用显存峰值 |
| --- | --- | --- | --- | --- | --- | --- |
| 亚马孙静止 | 25.7 | 144.0 | 7.36 ms | 254.0 MiB | 625.9 MiB | 381.9 MiB |
| 多洛米蒂静止 | 25.3 | 144.2 | 7.34 ms | 266.5 MiB | 670.6 MiB | 414.0 MiB |
| 亚马孙连续平移 | 35.0 | 144.1 | 7.33 ms | 256.2 MiB | 629.7 MiB | 381.9 MiB |

帧率来自窗口呈现间隔，受 144 Hz 刷新上限约束。移动测量含拖动之间的短停，路线约 222 公里。显存为 WDDM 该进程的专用显存采样峰值。切换政治地图后景观实例块数归零，切回地理地图后恢复。QPK 高程和覆盖共用约 68 MiB 缓存。高山坡面和冰雪边缘仍受 DEM 取样限制。世界覆盖是现代资料，树种、个体及岩面小形体是视觉推定。16 个采样纹理上限的适配器沿用原地图管线，本轮在单张 Vulkan 显卡上实测。
