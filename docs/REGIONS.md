# 地区数据状态

## 正式地区权威

当前详细地区与行政几何位于：

```text
data/world_map/regions.json
```

当前已完成的详细层包括法国九个游戏宏观地区，以及96个法国本土行政单元的过渡几何。地图运行时使用统一投影、LOD、空间索引和共享边界数据进行绘制与对象命中。

九个当前宏观地区为：

- 北部工业带；
- 巴黎盆地；
- 诺曼底；
- 布列塔尼；
- 卢瓦尔河谷；
- 阿基坦；
- 中央高原；
- 罗讷河谷；
- 地中海沿岸。

它们是当前详细玩法地区的过渡划分，不宣称完全等同于1900年历史行政区。

## 多精度地区

- 当前活动地区保存详细地点、人物、旅行、工作、企业和组织。
- 重要关联地区保存简化工资、价格、就业、企业、组织和事件。
- 远方地区通过国家与聚合区域状态影响贸易、信贷、政策、战争和人口流动。

所有层级必须引用同一正式国家与地区体系。

## 已撤销内容

以下架空地区不再是正式地区：

```text
region:loran_dawnbay
region:loran_riverback
region:loran_forgeplain
region:loran_southridge
region:vesta_northstar
region:vesta_silverfield
region:vesta_eastlake
region:vesta_redhill
```

它们只允许保留在旧架空Alpha夹具、自动测试和迁移研究中。`data/world/demo_world.json` 的80个控制单元不再定义正式地区结构。

## 经济与制度接入要求

工资、生活成本、商品价格、信用、企业、组织、职位、政策与风险数据应扩展到正式地区ID。不得通过复制一套平行地区表来绕过 `data/world_map/regions.json`。

正式地图与模拟连接完成前，不得将旧两国八区的企业、政治和长跑结果视为正式Alpha验收。
