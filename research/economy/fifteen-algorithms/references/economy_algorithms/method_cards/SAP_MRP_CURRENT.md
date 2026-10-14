# SAP_MRP_CURRENT

[Exploring the Materials Requirements Planning (MRP) Process](https://learning.sap.com/courses/managing-logistics-in-sap-business-one/exploring-the-materials-requirements-planning-mrp-process)

实际阅读：Define MRP Scenario/Item Selection/Choose Inventory Data Sources; six-step wizard and due-date horizon; Running MRP related page process paragraph。版本：Live official course page accessed2026-10-08; publication year UNKNOWN (2026 is access year)。

原问题为工程MRP建议流程。授权公司规划者取得所选仓库/公司库存、既有供需、forecast和BOM；状态为选定scenario、日期窗口和item参数，输出采购/生产建议。窗口按due date，父BOM子项纳入，默认考虑既有库存/供需，可让sales订单消费forecast；可反复what-if。参数horizon、leadtime、lot/min/max与warehouse范围，不是普适经济定律。证据官方工程说明，未运行产品；复杂度UNKNOWN，不猜SAP性能。单位item数量及日历日期。

WWO独立反例：forecast10及实际order10表示同一需求而机械相加会双买；窗口外late订单仍是真实责任。最小参考是明确哪些receipt按日期覆盖、哪些仍占exposure以及forecast消费关系。TEST_AS_REFERENCE；整套MRP wizard和跨公司全知查询REJECT_FOR_WWO_SCOPE。
