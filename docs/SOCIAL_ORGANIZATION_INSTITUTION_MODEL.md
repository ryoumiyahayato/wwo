# 社交、组织与国家机构模型

状态：设计冻结 v1。本文把人物关系、成员身份、组织职位和国家制度分成独立权威层。

## 1. 有限社会认知

人物界面只包含：

- 直接关系：实际认识且有联系渠道。
- 可接触人物：同事、邻居、同组织、同学校、亲属、共同联系人或地方活动对象。
- 公开人物：知道存在，但不能无条件直接联系。
- 未知人物：完全不出现在玩家 UI。

普通人物通常维持 5～15 个强关系，最多约 50 个活跃弱关系。该数值是内容与性能目标，不是硬性禁止更多历史记录；不活跃弱关系可以降为摘要。

## 2. 关系数据

```text
Relationship
  relationship_id
  character_a_id
  character_b_id
  familiarity: 0..100
  trust_a_to_b: -100..100
  trust_b_to_a: -100..100
  affinity_a_to_b: -100..100
  affinity_b_to_a: -100..100
  hostility: 0..100
  roles[]
  contact_channels[]
  last_interaction_hour?
  public_scope
  recent_interaction_ids[]
```

信任和好感是有方向的；共同关系对象仍使用同一稳定关系 ID。关系只在真实接触、家庭或明确制度联系发生时创建，不预建人物两两矩阵。

## 3. 关系自然变化

- 熟悉度：共同生活、工作和组织活动缓慢增加；长期无联系较快下降。
- 信任：可靠行为、帮助、兑现承诺增加；背叛、违约和冲突降低；自然衰减慢。
- 好感：性格、立场、互动和事件改变，不由熟悉度自动复制。
- 敌意：重大冲突、竞争、伤害与政治对立增加，可与高熟悉同时存在。

每次变化记录原因。UI 使用“今天、3 天前、2 个月前、一年多以前、从未直接互动”，永久禁止显示累计内部小时数。

## 4. 人物卡与上下文互动

人物卡第一层显示姓名、职业/职位、地区、关系摘要、最近互动和公开状态。点击后根据知识、可达性与关系显示联系、加深关系、请求帮助、引荐、谈判、调查、合作或冲突处理。

已建立关系的人物可直接继续互动，不要求重新从全人物列表选择。互动目标列表按可达性、关系、当前目标和实际条件排序。

## 5. 组织实体

```text
Organization
  organization_id
  organization_type
  legal_form
  country_id
  headquarters_location_id
  branch_ids[]
  public_profile
  member_count_summary
  resource_accounts[]
  influence_records[]
  public_stances[]
  department_ids[]
  position_definition_ids[]
  project_ids[]
  governance_rule_id
```

组织包括企业、工会、政党、协会、学校、大学、军队单位和地方团体。国家机构使用单独的 `Institution` 类型，不是换皮组织，但可以复用稳定 ID、职位和账户等技术组件。

## 6. 成员与职位

```text
OrganizationMembership
  organization_id
  character_id
  member_status
  joined_hour
  department_id?
  dues_rule?
  organization_trust
  obligations[]

PositionAssignment
  assignment_id
  position_definition_id
  holder_id
  department_id
  supervisor_assignment_id?
  subordinate_assignment_ids[]
  compensation_rule
  access_grant_ids[]
  started_hour
  ended_hour?
```

成员身份不等于职位。正式 UI 必须显示具体职位、部门、上级、下属、津贴、义务和权限；不能只写“组织成员”。

## 7. 我的组织与探索组织

“我的组织”只显示已加入组织，并按当前义务、项目和职位排序。“探索组织”独立显示已知且可能接触的未加入组织，按地区、类型、职业匹配、引荐、公开程度和加入条件筛选。

未知组织不显示；公开但不可加入的机构可以进入观察层，不混入可申请列表。

## 8. 组织资源、影响与立场

- 资源：有付款来源和用途的账户，用于工资、项目、宣传、研究、行政或军事行动。
- 影响：按成员、地区、市场、政策或其他组织分别存储的实际动员能力。
- 公开立场：对明确议题的支持、反对或中立，以及强度和公开时间。

这些字段必须进入公式：资源不足会拖欠或缩小项目；地区影响改变招募与政策支持；立场影响关系、联盟、成员满意和冲突。不得只作为说明文本。

## 9. 组织项目

```text
OrganizationProject
  project_id
  organization_id
  project_type
  target_scope
  sponsor_assignment_ids[]
  participant_ids[]
  budget_commitment
  personnel_commitment
  start_hour
  milestones[]
  status
  success_conditions[]
  opposition_ids[]
```

组织项目需要成员或职位、人物时间、预算和目标范围。招募、宣传、筹款、内部改革、扩建和行业项目都使用该结构，不以一次按钮即时产生全部效果。

## 10. 国家机构

```text
Institution
  institution_id
  country_id
  institution_type
  legal_mandates[]
  jurisdiction_scope
  budget_account_ids[]
  department_ids[]
  position_definition_ids[]
  agenda_slot_ids[]
  current_program_ids[]
  administrative_capacity
  enforcement_capacity
  legitimacy_record_id
```

国家由行政机关、代表机构、地方政府、司法、财政/中央银行、军队、教育科研机构等组成。企业、工会和政党影响国家，但不属于国家机构本体。

## 11. 国家议程

不使用固定线性国策树。议程是动态问题与制度项目：

```text
Agenda
  agenda_id
  category
  proposer_ids[]
  beneficiary_group_ids[]
  harmed_group_ids[]
  supporter_ids[]
  opponent_ids[]
  fiscal_cost
  legal_basis
  procedural_stage
  execution_difficulty
  legitimacy_effect
  stability_effect
  program_ids[]
```

类别包括基础设施、教育、工业、劳工、公共健康、财政、金融、军事、外交和行政改革。“扩建铁路”属于基础设施议程下的具体交通项目。

## 12. AI 目标

企业追求现金流、盈利、扩张、成本、市场和政策；工会追求成员、工资、劳动条件和立法；教育机构追求人才、教学、研究与扩散；军队追求战备、人员、装备和补给；政府机构追求税收、稳定、服务和政策执行。

组织 AI 使用长期目标—项目承诺，不每月随机更换无关项目。成员与职位人物的个人目标可以支持、抵制或利用组织目标。

## 13. 更新周期

| 周期 | 结算 |
| --- | --- |
| 即时 | 成员加入退出、任命免职、重大关系行为 |
| 每周 | 关系维护、普通组织活动、项目参与 |
| 每月 | 账户、工资、成员变化、项目进度、地区影响 |
| 每季度 | 大型投资、机构计划、国家议程重评 |
| 每年 | 长期组织结构、领导交接、制度变化 |

## 14. 首版与保留接口

首版必须：有限人物集合、人物卡、关系四维、我的/探索组织、成员与具体职位、权限授予、组织账户/影响/立场、地方机构与简单议程流程。

只保留接口：完整选举、复杂政党基层、董事会法、司法诉讼、多院议会、跨国组织、秘密派系与完整军事编制。
