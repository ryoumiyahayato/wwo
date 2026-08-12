# WWO WORLD DATA PERFORMANCE BASELINE — BATCH 1

Starting master: 4b738ab8b0a21e8685aae95381717e9efd2327a8
Branch: chore/world-data-performance-baseline-20260812

This is a measurement report. Production gameplay, authoritative map data, and workflows were not modified.

## Runtime and workload

- Runtime: 4.6.3-stable (official) on Windows (13th Gen Intel(R) Core(TM) i7-13700H)
- Iterations: 7 full samples, 5 map samples, 1000 lookup operations per lookup sample.
- Synthetic scales: 1x, 2x, 5x, 10x; base 1000 records; synthetic data remains memory-only.
- Benchmark semantics: MACHINE-SPECIFIC OBSERVATIONAL BASELINE; timings are not universal CI pass/fail thresholds.

## Dataset sizes

| Dataset | Files | Raw bytes | Records | Decoded objects | Geometry points | Decoded estimate |
|---|---:|---:|---:|---:|---:|---:|
| countries | 1 | 175.2 KiB | 177 | 179 | 354 | 366.9 KiB |
| regions | 1 | 441.1 KiB | 107 | 220 | 22068 | 1.57 MiB |
| cities | 1 | 7.3 KiB | 32 | 33 | 32 | 24.2 KiB |
| ports | 1 | 1.9 KiB | 8 | 9 | 8 | 6.4 KiB |
| roads | 1 | 468 B | 3 | 4 | 0 | 1.6 KiB |
| rail | 1 | 1.6 KiB | 9 | 10 | 0 | 5.2 KiB |
| shipping | 1 | 859 B | 3 | 4 | 14 | 3.0 KiB |
| geometry_cache | 2 | 2.46 MiB | 177 | 3303 | 88687 | 9.50 MiB |
| historical_data | 8 | 6.32 MiB | 4908 | 5556 | 305705 | 22.63 MiB |
| organizations | 1 | 11.3 KiB | 13 | 25 | 4 | 27.9 KiB |
| characters | 1 | 6.6 KiB | 2 | 12 | 0 | 15.3 KiB |
| institutions | 1 | 10.3 KiB | 7 | 23 | 7 | 26.3 KiB |
| supporting_runtime_data | 4 | 23.1 KiB | 10 | 98 | 0 | 74.5 KiB |
| city_detail_shards | 156 | 38.10 MiB | 88927 | 89083 | 88927 | 130.75 MiB |
| city_detail_index | 1 | 34.8 KiB | 300 | 304 | 0 | 127.7 KiB |

Largest files and high-cardinality structures are preserved in the machine-readable JSON artifact.

## Load benchmark

- PrototypeV2Data.load_all() runtime-set load: median 74.162 ms (min 68.033, max 80.034; n=7)
- Geometry cache JSON parse: median 47.610 ms (min 41.175, max 55.827; n=7)
- City-detail index JSON parse: median 2.259 ms (min 1.658, max 3.695; n=7)

Per-file parse distributions are in runtime_file_parse in the JSON artifact.

## Geometry, index, and map query benchmark

- Canvas setup (geometry conversion + ID indexes + spatial indexes + transport tie cache): median 56.497 ms (min 55.452, max 63.001; n=5)
- View world: median 0.037 ms (min 0.035, max 0.045; n=5); visible counts { "countries": 1, "administrative_units": 0, "regions": 0, "cities": 0, "ports": 0, "institutions": 0, "organizations": 0, "rail": 0, "road": 0, "shipping": 0, "labels": 0 }.
- View europe: median 0.038 ms (min 0.038, max 0.044; n=5); visible counts { "countries": 2, "administrative_units": 0, "regions": 0, "cities": 0, "ports": 0, "institutions": 0, "organizations": 0, "rail": 0, "road": 0, "shipping": 0, "labels": 0 }.
- View france: median 0.058 ms (min 0.054, max 7.516; n=5); visible counts { "countries": 1, "administrative_units": 0, "regions": 0, "cities": 0, "ports": 0, "institutions": 0, "organizations": 0, "rail": 0, "road": 0, "shipping": 0, "labels": 0 }.
- View player_location: median 0.076 ms (min 0.072, max 14.272; n=5); visible counts { "countries": 3, "administrative_units": 1, "regions": 1, "cities": 3, "ports": 2, "institutions": 4, "organizations": 4, "rail": 1, "road": 1, "shipping": 1, "labels": 0 }.
- Representative ID lookups: median 4.701 ms (min 4.676, max 4.739; n=5) (5000 operations/sample).
- Representative map point query: median 7.571 ms (min 7.538, max 7.615; n=5)
- City-detail index configure: median 4.974 ms (min 4.838, max 5.367; n=5)
- City-detail cold viewport query: median 174.222 ms (min 169.078, max 180.672; n=5)
- City-detail warm viewport query: median 1.377 ms (min 1.327, max 1.735; n=5)

## Synthetic scaling

| Scale | Records | JSON bytes | Parse median | Index median | Lookup median |
|---:|---:|---:|---:|---:|---:|
| 1x | 1000 | 70.4 KiB | median 3.057 ms (min 2.926, max 3.491; n=5) | median 3.429 ms (min 3.124, max 3.901; n=5) | median 2.213 ms (min 2.104, max 2.469; n=5) |
| 2x | 2000 | 141.4 KiB | median 5.935 ms (min 4.954, max 6.580; n=5) | median 7.828 ms (min 7.108, max 8.305; n=5) | median 2.145 ms (min 2.095, max 2.374; n=5) |
| 5x | 5000 | 354.6 KiB | median 15.850 ms (min 12.299, max 24.055; n=5) | median 19.660 ms (min 19.009, max 24.400; n=5) | median 2.328 ms (min 2.250, max 2.578; n=5) |
| 10x | 10000 | 713.8 KiB | median 32.136 ms (min 25.463, max 34.772; n=5) | median 42.682 ms (min 41.543, max 47.722; n=5) | median 6.925 ms (min 4.122, max 9.650; n=5) |

Interpretation is intentionally conservative: use the measured distribution to decide when a future optimization is justified; no CI gate is set here.

## Likely complexity risks

- HP01 — 每次 load_all 都重新读取并完整 JSON.parse_string 一个文档；当前没有 parsed-document cache。 (O(total JSON bytes) per load).
- HP02 — setup 会重新提取数组、建立 ID 索引、转换 geometry cache、建立空间索引并重建 transport tie cache。 (O(records + geometry vertices + index cell coverage)).
- HP03 — 每次受控视图刷新会查询国家、行政区、宏区、城市、港口、机构、组织和三类运输索引。 (O(number of queried buckets + candidates)).
- HP04 — 运输显示层会过滤候选铁路并重新排序；高频重复调用时存在可缓存的排序成本。 (O(rail records + rail records log rail records)).
- HP05 — 城市分片查询会扫描全部 shard_metadata，再对相交分片排序并按缓存上限载入。 (O(shards + intersecting shards log intersecting shards)).
- HP06 — 屏幕间距 thinning 对已接受点逐一比较；候选数增长时可能出现明显的二次项。 (O(candidate records × accepted records)).

## Candidate optimizations

- OPT01 — 为稳定输入增加带 schema/version 指纹的 parsed metadata 或 derived cache。 Boundary: 在 world-map JSON 总量达到约 10 MB，或启动/重载每次都发生多次完整解析时评估。
- OPT02 — 将 geometry cache 的 PackedVector2/triangle 派生结果预构建为版本化二进制或紧凑缓存。 Boundary: 当 geometry vertex 总量达到约 1,000,000，或 setup 的 geometry conversion 超过 50 ms 中位数时评估。
- OPT03 — 为 shard bounds 增加 tile/R-tree 级元数据索引，避免每个 viewport 扫描全部分片。 Boundary: 当 city-detail shard 数超过 1,000，或 viewport query 中位数超过 2 ms 时评估。
- OPT04 — 缓存按 zoom level 的铁路排序候选与 label candidate 顺序。 Boundary: 当 rail records 超过 10,000，或 transport/label 刷新成为可见热点时评估。
- OPT05 — 对城市 detail thinning 使用空间网格或固定屏幕桶，保留当前 node/label budget。 Boundary: 当单个 viewport 候选城市超过 2,000，或 thinning 成为 O(N²) 热点时评估。

## TOP 20 FUTURE WORLD-DATA PERFORMANCE RISKS

| # | Risk | Revisit when |
|---:|---|---|
| 1 | 启动或重载重复完整 JSON parse | world-map JSON 总量 > 10 MB，或同一会话重复 load > 1 次 |
| 2 | geometry cache 一次性解码占用 | geometry vertices > 1,000,000，或 decoded estimate > 64 MB |
| 3 | country LOD polygon 转换与空间索引初始化 | 国家特征 > 500，或单个 LOD vertices > 500,000 |
| 4 | 行政区 LOD 首次懒加载暂停 | 单个行政区 LOD records > 10,000 |
| 5 | 宏区空间索引的 bounds 多单元覆盖 | 宏区 records > 1,000，或平均单记录覆盖 > 100 cells |
| 6 | 数组遍历建立 ID 索引 | 单类实体 > 100,000 |
| 7 | 大 bounds 记录插入 uniform-grid 产生桶膨胀 | 单条运输/几何记录覆盖 > 10,000 cells |
| 8 | 每次 camera refresh 查询多个空间索引 | 刷新频率 > 60/s，或单次候选总量 > 50,000 |
| 9 | 可见铁路过滤与排序重复执行 | rail records > 10,000，或 transport layer 高频重绘 |
| 10 | 可见标签候选排序与碰撞筛选 | label candidates > 5,000 |
| 11 | 几何转换产生重复 Dictionary/PackedArray 结构 | setup decoded estimate > 128 MB |
| 12 | city shard metadata 每次 viewport 全扫描 | shards > 1,000，或 query > 2 ms median |
| 13 | city shard cache 反复驱逐造成 thrash | 一次 viewport 相交 shards > cache limit，且相邻视图来回切换 |
| 14 | 城市 detail 候选 thinning 二次比较 | 单视口候选 > 2,000，或 accepted 接近 node budget |
| 15 | 城市 detail 命中检测线性扫描 visible records | visible city detail records > 1,600 |
| 16 | transport bounds/points 派生缓存增长 | rail + road + shipping records > 100,000 |
| 17 | 长运输线跨大量网格桶 | 单条长线覆盖 > 10,000 cells |
| 18 | 字符串 ID 转换与 key 构造重复 | 每帧处理记录 > 100,000，或 profile 显示字符串成本成为前 5 热点 |
| 19 | 历史/现代参考数据边界扩大后混入常规 load | 非运行时历史文件被加入启动路径，或历史 records > 1,000,000 |
| 20 | 基准分布未转化为回归阈值 | 连续三次 baseline 后仍无 median/p95 分布记录 |

## Measurement limits and handoff

- Timing values are machine-specific observational baselines; they are not universal CI pass/fail thresholds.

- 真实 process RSS/heap 未可靠测量：NOT MEASURED；decoded_data_bytes_estimate 是递归估算，不是 allocator 计数。
- cold parse 是同一进程的 first-pass 样本，未重启进程，也未控制 OS 文件缓存。
- benchmark 未改变生产 runtime，也未把 synthetic 数据写入正式 world data。
- benchmark 使用固定的 repository-local 输入；live master fetch/push 状态属于交付环境，不影响测量结果。起始 master SHA 为 4b738ab8b0a21e8685aae95381717e9efd2327a8。

Production code modified: NO
Benchmark tooling is under tools/ and its harness test is under tests/; the JSON result is a local ignored artifact.
