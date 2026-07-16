# 法律、权利与国家执行能力

状态：设计冻结 v1。政策不是点击后立即生效的全局修正；国家机构也不是普通组织的换皮。

## 1. 国家制度状态

每个国家及其辖区至少保存：

```text
StateCapacity
  country_id
  administrative_capacity: 0..100
  enforcement_capacity: 0..100
  fiscal_capacity: 0..100
  corruption: 0..100
  local_autonomy: 0..100
  legitimacy: 0..100
  institution_capacity_records[]
```

国家级数值是摘要。地方机构可以有不同能力、腐败、自治和服从程度；全国政策效果不得只乘一个全局常数。

## 2. 法律与权利

```text
Law
  law_id
  country_id
  category
  jurisdiction_scope
  enacted_hour
  effective_hour
  legal_rules[]
  right_grants[]
  obligation_rules[]
  responsible_institution_ids[]
  required_budget_rule
  repeal_or_expiry?
```

```text
RightRecord
  right_id
  holder_scope
  protected_action
  jurisdiction_scope
  legal_basis_id
  remedy_ids[]
  enforcement_institution_ids[]
  practical_access_conditions[]
```

法律权利与实际可行性分开。纸面权利可以存在，但因无预算、无官员、腐败、地方抵抗或信息不足而难以执行。

## 3. 政策生命周期

```text
问题进入议程
→ 提出
→ 审议、批准或命令
→ 确认法律依据
→ 分配预算、人员和责任机构
→ 制定执行计划
→ 地方落实与对象遵从
→ 结果、申诉、修正或废止
```

每个阶段由不同权限控制。拥有提案权的人物不能跳过批准、预算和执行；拥有行政职位也不能修改超出法定范围的法律。

## 4. 政策实施记录

```text
PolicyImplementation
  implementation_id
  agenda_or_law_id
  responsible_institution_id
  target_scope
  stage
  budget_required
  budget_committed
  staffing_required
  staffing_available
  administrative_difficulty
  enforcement_requirement
  local_resistance
  organization_support
  compliance_rate_estimate
  progress
  causal_record_ids[]
```

实施效果结构：

```text
落实能力 = 法律授权 × 预算充分度 × 人员充分度
           × 行政能力 × 执法能力 × 基础设施
           × (1 - 腐败损失) × (1 - 地方抵抗)
           × 组织协作
```

公式使用数据驱动曲线和边界，不要求各因素简单线性相乘；结构与来源必须可解释。

## 5. 遵从与规避

政策对象拥有自己的反应。劳动法通过后，企业可能完全遵守、部分规避、贿赂、裁员、转移生产、提出诉讼或通过行业组织反对。反应取决于成本、执法概率、处罚、企业现金、组织立场和管理者目标。

政府不会因为法律存在就直接修改所有企业状态。执行机构产生检查、处罚、服务或激励，企业再作出反应。

## 6. 腐败

腐败不是随机扣分，而是资源或权限被私人使用的可追踪过程。它可能导致预算流失、选择性执法、任命偏差、信息失真和公众评价变化。

腐败行为需要行动者、机会、收益、风险与受损主体。反腐需要审计、司法、媒体、组织压力和制度改革；不能通过一个无来源按钮永久清零。

## 7. 地方自治与多级辖区

国家、地区和地方机构分别拥有法定权限。中央政策可能：

- 直接执行。
- 需要地方共同预算。
- 只提供标准，由地方选择实施。
- 因自治而不可强制。
- 在紧急状态下临时扩大中央权限。

辖区冲突返回明确法律与机构原因，不由 UI 猜测。

## 8. 财政与人员来源

政策预算来自政府账户的税收、借款或转移；人员来自真实机构职位和就业合同。没有资金或人员时，政策进入延迟、缩减或失败状态，不凭空执行。

制度失败应反馈到财政、合法性、地方评价、组织立场和人物职业表现。

## 9. AI 使用

机构 AI 评估法律义务、当前议程、预算、人员、执行缺口和政治压力，形成季度项目。地方执行者根据职业义务、组织信任、腐败诱因、风险和本地关系行动。

国家目标不能直接写入结果，只能创建议程、预算和执行承诺。

## 10. UI

政策卡第一层显示阶段、主要支持/反对、预算状态和落实趋势。点击后显示法律依据、责任机构、预算、人员、地方落实和主要阻碍。

普通人物可观察公开法律与本地实际效果；相关职位人物才看到内部执行数据和控制入口。

## 11. 首版与保留接口

首版必须：法律记录、权利授予、地方/中央辖区、政策六阶段、预算/人员、行政/执法能力、腐败与地方抵抗、企业基础遵从反应。

只保留接口：完整司法案件、宪法审查、行政复议层级、国际法、殖民法权、秘密警察体系和复杂税法。
