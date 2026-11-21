use crate::{formal_ui::Skin, overlay::Mesh};
use serde_json::Value;
use std::cell::{Cell, RefCell};
use wwo_map_lab::formal_population::{
    needs::QuantityRange, CohortSex, PopulationInspection, PopulationStructure, SocialDistribution,
};

const INK: [u8; 4] = [243, 236, 221, 255];
const MUTED: [u8; 4] = [183, 193, 195, 255];
const GOLD: [u8; 4] = [221, 185, 123, 255];
const ROW_HEIGHT: f32 = 23.;
const BODY_TOP: f32 = 105.;
const FOOTER_HEIGHT: f32 = 33.;

struct Row {
    label: (&'static str, &'static str),
    value: String,
    heading: bool,
    unknown: bool,
}

struct Layout {
    width: f32,
    english: bool,
    lines: Vec<(String, [u8; 4])>,
    sections: Vec<usize>,
}

pub struct Panel {
    pub input: String,
    pub query: String,
    pub scroll: usize,
    report: Vec<Row>,
    reported_query: String,
    scope_relation: Option<&'static str>,
    population_total: Option<u64>,
    layout: RefCell<Option<Layout>>,
    max_scroll: Cell<usize>,
}

impl Default for Panel {
    fn default() -> Self {
        Self {
            input: "world".into(),
            query: "world".into(),
            scroll: 0,
            report: Vec::new(),
            reported_query: String::new(),
            scope_relation: None,
            population_total: None,
            layout: RefCell::new(None),
            max_scroll: Cell::new(0),
        }
    }
}

impl Panel {
    pub fn set_report(&mut self, inspection: &PopulationInspection<'_>) {
        if self.reported_query != inspection.query_id {
            self.scroll = 0;
            self.reported_query = inspection.query_id.into();
        }
        self.report.clear();
        self.layout.get_mut().take();
        self.scope_relation = Some(inspection.scope_relation);
        self.population_total = inspection.population_total;

        self.heading("当前人口", "Current population");
        self.field("查询对象", "Query", Some(inspection.query_id));
        let date = inspection.date;
        self.field(
            "游戏时间",
            "Game time",
            Some(format!(
                "{:04}-{:02}-{:02} {:02}:{:02}  /  #{}",
                date.year, date.month, date.day, date.hour, date.minute, inspection.minute,
            )),
        );
        let (zh, en) = match inspection.scope_relation {
            "world" => ("全球账户", "World accounts"),
            "statistical_account" => ("正式人口账户", "Population account"),
            "historical_name_alias_of_account" => (
                "人口账户的历史地名",
                "Historical name for this population account",
            ),
            "residence_site_in_account" => (
                "账户内的居住地点，地点人数未知",
                "Residence site in an account. Site population unknown.",
            ),
            "dated_city_reference" => ("历史城市资料", "Dated city evidence"),
            "dated_evidence_only" => (
                "历史资料，当前人数未知",
                "Dated evidence. Current population unknown.",
            ),
            _ => ("人口范围未知", "Population scope unknown"),
        };
        self.field(zh, en, Some(""));
        let (zh, en) = if inspection.scope_relation == "world" {
            ("全球人口", "World population")
        } else {
            ("账户总人口", "Account population")
        };
        self.number(zh, en, inspection.population_total);
        self.number("直属人数", "Direct residents", inspection.direct_residents);
        self.field("统计账户", "Account", inspection.account_id);
        self.field("上级账户", "Parent account", inspection.parent_id);
        self.field(
            "地图地点",
            "Explicit map sites",
            joined(&inspection.map_place_ids),
        );
        self.show_structure(inspection.structure.as_ref());
        self.show_cohorts(inspection.structure.as_ref());
        self.show_social(inspection.social.as_ref());
        self.show_living(inspection);
        self.show_coverage(inspection.structural_coverage.as_ref());
        self.show_opening(inspection);
        self.show_changes(inspection);
        self.show_history(inspection);

        if !inspection.children.is_empty() {
            self.heading("下级人口账户", "Child accounts");
            for child in &inspection.children {
                self.line(format!(
                    "{}  |  {}  |  {}",
                    child.name,
                    child.unit_id,
                    number(child.population_total)
                ));
            }
        }
    }

    fn show_opening(&mut self, inspection: &PopulationInspection<'_>) {
        self.heading("开局依据", "Opening basis");
        self.field("账户口径", "Basis", Some(inspection.basis));
        self.field(
            "开局版本",
            "Opening version",
            inspection.opening_version.map(|v| v.to_string()),
        );
        if let Some(opening) = inspection.opening {
            self.number(
                "开局人数",
                "Opening population",
                Some(opening.population_value),
            );
            self.field("资料", "Source", Some(opening.source_id.as_str()));
            self.field("原表位置", "Locator", Some(opening.locator.as_str()));
            self.field("方法", "Method", Some(opening.method.as_str()));
            self.number(
                "未定位人口",
                "Unlocated population",
                opening.research_unlocated_balance,
            );
            if let Ok(context) = serde_json::to_value(opening) {
                self.field("统计日期", "Reference date", value_text(&context["date"]));
                self.field("统计范围", "Scope", value_text(&context["scope"]));
                self.field("区间", "Interval", interval(&context));
                self.field(
                    "不确定性",
                    "Uncertainty",
                    value_text(&context["uncertainty_kind"]),
                );
            }
        } else if let Some(estimate) = inspection.legacy_estimate {
            self.number(
                "旧估计人数",
                "Legacy population estimate",
                Some(estimate.value),
            );
            self.field(
                "区间",
                "Interval",
                Some(format!(
                    "{}–{}",
                    number(estimate.lower),
                    number(estimate.upper)
                )),
            );
            self.field(
                "统计日期",
                "Reference date",
                Some(estimate.calibration_date),
            );
            self.field("资料", "Source", Some(estimate.source_table));
            self.field("方法", "Method", Some(estimate.source_method));
        } else {
            self.number("开局人数", "Opening population", None);
        }
    }

    fn show_structure(&mut self, structure: Option<&PopulationStructure<'_>>) {
        self.heading("人口结构", "Population structure");
        if let Some(structure) = structure {
            self.number(
                "有姓名的居民",
                "Named residents",
                Some(structure.named_residents),
            );
            self.number(
                "年龄和性别已分组",
                "Residents in age and sex cohorts",
                Some(structure.residents_with_cohort_age_and_sex),
            );
            self.number(
                "匿名居民未分配年龄或性别",
                "Anonymous residents with age or sex unassigned",
                Some(structure.population_total - structure.named_residents - structure.residents_with_cohort_age_and_sex),
            );
            self.number(
                "分组人口",
                "Cohort residents",
                Some(structure.cohort_residents),
            );
            self.number(
                "未分类人口",
                "Unclassified residents",
                Some(structure.unclassified_residents),
            );
            if let Some(ages) = structure.count_ages(15, 64) {
                self.heading("潜在劳动年龄（匿名居民 15–64 岁）", "Potential working age (anonymous residents aged 15–64)");
                self.number("确定在范围内", "Within range", Some(ages.definitely_in_range));
                self.number("年龄段与范围相交", "Age band overlaps range", Some(ages.possibly_in_range_with_known_age));
                self.number("年龄未知", "Age unknown", Some(ages.age_unknown));
            }
        } else {
            self.field("结构覆盖", "Structure coverage", None::<String>);
        }
    }

    fn show_social(&mut self, social: Option<&SocialDistribution<'_>>) {
        self.heading("社会属性分配", "Social attributes");
        let Some(social) = social else {
            self.field("分配状态", "Allocation status", Some("未分配 / Unassigned"));
            return;
        };
        if social.affected_resident_pools > 0 {
            self.field(
                "人口变动后保守下界",
                "Conservative counts after population changes",
                Some(""),
            );
        }
        self.field(
            "各维度分别计数，交叉属性人数未知",
            "Counts are independent by dimension. Intersections are unknown.",
            Some(""),
        );
        for (key, dimension) in &social.dimensions {
            let (zh, en) = match *key {
                "class" => ("社会阶层", "Social class"),
                "legal_estate" => ("法定身份等级", "Legal estate"),
                "occupation" => ("职业", "Occupation"),
                "language" => ("语言", "Language"),
                "culture" => ("文化", "Culture"),
                "religion" => ("宗教", "Religion"),
                "literacy" => ("识字", "Literacy"),
                "residence" => ("城乡居住", "Urban and rural residence"),
                "marital_status" => ("婚姻状态", "Marital status"),
                "housing" => ("住房", "Housing"),
                _ => continue,
            };
            self.heading(zh, en);
            if dimension.assigned_residents == 0 {
                self.field("未分配", "Unassigned", Some(""));
            }
            self.number("已分配人数", "Assigned residents", Some(dimension.assigned_residents));
            self.number("未知人数", "Unknown residents", Some(dimension.unknown_residents));
            for (classification, categories) in &dimension.by_classification {
                if !categories.is_empty() {
                    self.field("原表分类", "Census classification", Some(*classification));
                    for (category, count) in categories {
                        self.line(format!("{category}  |  {}", number(*count)));
                    }
                }
            }
            if !dimension.source_ids.is_empty() {
                self.field("资料", "Sources", Some(dimension.source_ids.iter().copied().collect::<Vec<_>>().join("  |  ")));
            }
            if let Some(source) = dimension.direct_opening_distribution {
                self.field("观测日期", "Observation date", Some(source.observed_date.as_str()));
                self.field("观测范围", "Observed scope", Some(source.observed_scope.as_str()));
                self.number("原表统计适用人数", "Census denominator", Some(source.observed_total));
                self.field("原表位置", "Locator", Some(source.locator.as_str()));
                self.field("分配方法", "Allocation method", Some(source.method.as_str()));
                self.field("原表定义", "Source definition", Some(source.definition.as_str()));
            }
        }
    }

    fn show_cohorts(&mut self, structure: Option<&PopulationStructure<'_>>) {
        let Some(structure) = structure.filter(|structure| !structure.cohorts.is_empty()) else {
            return;
        };
        self.heading("年龄与性别分组", "Age and sex cohorts");
        for cohort in &structure.cohorts {
            let age = cohort.age_years.map(|age| match age.oldest {
                Some(oldest) if oldest != age.youngest => format!("{}–{oldest}", age.youngest),
                Some(_) => age.youngest.to_string(),
                None => format!("{}+", age.youngest),
            });
            let (zh, en) = match cohort.sex {
                Some(CohortSex::Male) => ("M", "Male"),
                Some(CohortSex::Female) => ("F", "Female"),
                None => ("性别未知", "Sex unknown"),
            };
            let mut value = format!(
                "{}  |  {}  |  {:?}",
                number(cohort.members),
                cohort.unit_id,
                cohort.provenance
            );
            if let Some(evidence) = &cohort.evidence {
                value.push_str(&format!(
                    "  |  {} ({})",
                    evidence.observed_date, evidence.source_id
                ));
            }
            self.field(zh, en, Some(value));
            self.field("年龄", "Age", age);
            if let Some(evidence) = &cohort.evidence {
                self.field("原表位置", "Locator", Some(evidence.locator));
                self.field("分配方法", "Allocation method", Some(evidence.method));
                self.field("不确定性", "Uncertainty", Some(evidence.uncertainty));
            }
        }
    }

    fn show_living(&mut self, inspection: &PopulationInspection<'_>) {
        self.heading("生活条件与需要", "Living conditions and needs");
        if let Some(structure) = &inspection.structure {
            let energy = &structure.published_energy_reference;
            let protein = &structure.published_protein_reference;
            let water = &structure.published_efsa_water_reference;
            self.heading("按人口属性计算的条件需求", "Conditional needs by population attributes");
            for ((zh, en), known, unknown, quantity, unit) in [
                (("膳食能量", "Food energy"), energy.people_with_reference, energy.people_without_reference,
                    energy.conditional_kcal_per_day, "kcal/day"),
                (("蛋白质", "Protein"), protein.people_with_reference, protein.people_without_reference,
                    protein.conditional_grams_per_day, "g/day"),
                (("食物及饮品水量", "Water from food and beverages"), water.people_with_reference, water.people_without_reference,
                    water.moderate_environment_pal_1_6_total_ingested_litres_per_day, "L/day"),
            ] {
                self.field(zh, en, quantity.map(|range| daily_quantity(range, unit)));
                self.number("可计算人数", "Residents with a reference", Some(known));
                self.number("未知人数", "Unknown residents", Some(unknown));
            }
        }
        self.heading("历史饮食习惯及禁忌", "Historical dietary customs and restrictions");
        if inspection.dietary_norms.is_empty() {
            self.field("适用人群未分配", "Applicable population unassigned", Some(""));
        }
        for norm in &inspection.dietary_norms {
            self.field("饮食规范", "Dietary norm", Some(norm.trait_id));
            self.number("登记宗教可能适用人数", "Residents with matching recorded religion", Some(norm.residents_with_matching_religion));
            self.number("宗教未分配人数", "Residents with religion unassigned", Some(norm.residents_with_unassigned_religion));
            self.number("实际遵行人数", "Observed adherents", norm.observed_adherents);
        }
        let Ok(living) = serde_json::to_value(&inspection.living_conditions) else {
            return;
        };
        self.field(
            "历史观测覆盖",
            "Historical observation coverage",
            living["historical_actual_coverage"]
                .as_str()
                .filter(|&value| value != "unknown"),
        );
        if let Some(gaps) = living["historical_quantity_gaps"]
            .as_array()
            .filter(|gaps| !gaps.is_empty())
        {
            self.heading("历史数量缺项", "Missing historical quantities");
            for gap in gaps {
                self.record(gap, &["category", "missing_inputs"]);
            }
        }
        if let Some(references) = living["references"]
            .as_array()
            .filter(|entries| !entries.is_empty())
        {
            self.heading(
                "现代与临时安置条件参照",
                "Conditional modern and emergency references",
            );
            for entry in references {
                self.record(
                    entry,
                    &[
                        "category",
                        "context",
                        "quantity",
                        "unit",
                        "conditions",
                        "source",
                    ],
                );
            }
        }
    }

    fn show_changes(&mut self, inspection: &PopulationInspection<'_>) {
        self.heading("近期人口变化", "Recent population changes");
        for change in &inspection.recent_changes {
            let mut value = format!("#{}  |  {}", change.minute, change.kind);
            if let Some(unit) = change.unit_id {
                value.push_str(&format!("  |  {unit}"));
            }
            if let Some(destination) = change.destination {
                value.push_str(&format!(" → {destination}"));
            }
            match change.members {
                Some(members) => self.line(format!("{value}  |  {}", number(members))),
                None => self.field("人数未知", "Count unknown", Some(value)),
            }
        }
        if inspection.archived_change_details_unknown {
            self.field("更早的变化明细", "Earlier change details", None::<String>);
        } else if inspection.recent_changes.is_empty() {
            self.field("无近期变动记录", "No recent entries", Some(""));
        }
    }

    fn show_history(&mut self, inspection: &PopulationInspection<'_>) {
        if let Some(city) = &inspection.city_reference {
            self.heading("城市历史统计", "Dated city evidence");
            self.record(
                city,
                &[
                    "city_key",
                    "representative_record",
                    "source_date",
                    "source_parent_id",
                    "source_id",
                    "definition",
                    "evidence",
                    "status",
                ],
            );
            self.number(
                "历史城市人口",
                "Dated city population",
                city["population_value"].as_u64(),
            );
        }
        if let Some(archive) = &inspection.archive {
            for (labels, records, fields) in [
                (
                    ("地图与统计地区", "Map and statistical identities"),
                    &archive.geographies,
                    &[
                        "catalogue",
                        "status",
                        "geometry_status",
                        "parent",
                        "parent_ids",
                        "opening_ids",
                        "opening_id",
                        "shared_opening_ids",
                        "historical_observation_ids",
                        "study_candidates",
                        "note",
                    ][..],
                ),
                (
                    ("下级历史统计范围", "Child historical scopes"),
                    &archive.geography_children,
                    &[
                        "catalogue",
                        "status",
                        "geometry_status",
                        "parent",
                        "historical_observation_ids",
                        "note",
                    ][..],
                ),
                (
                    ("历史人口观测", "Dated population observations"),
                    &archive.dated_population,
                    &[
                        "date",
                        "date_precision",
                        "enumeration_date",
                        "kind",
                        "population_value",
                        "population_lower",
                        "population_upper",
                        "parent_id",
                        "wwo_id",
                        "source_id",
                        "locator",
                        "definition",
                        "method",
                        "quality",
                        "mapping_status",
                        "breakdowns",
                        "component_population_value",
                        "published_total_minus_components",
                    ][..],
                ),
                (
                    ("历史人口结构", "Dated demographic observations"),
                    &archive.dated_structure,
                    &[
                        "date",
                        "dimension",
                        "subcategory",
                        "dialect",
                        "measure",
                        "category",
                        "values",
                        "source_id",
                        "locator",
                        "published_scope",
                        "definition",
                    ][..],
                ),
                (
                    ("研究候选统计", "Candidate research statistics"),
                    &archive.candidate_research_population,
                    &[
                        "date",
                        "kind",
                        "population_value",
                        "population_lower",
                        "population_upper",
                        "source_id",
                        "locator",
                        "method",
                        "quality",
                        "parent_id",
                        "wwo_id",
                        "mapping_status",
                        "scope_note",
                        "definition",
                    ][..],
                ),
                (
                    ("原始资料", "Sources"),
                    &archive.sources,
                    &[
                        "publisher",
                        "url",
                        "locator",
                        "rights",
                        "date_note",
                        "boundary_note",
                        "references",
                        "reference_date",
                        "license",
                        "contemporary_cross_check",
                        "boundary_sources",
                    ][..],
                ),
            ] {
                if !records.is_empty() {
                    self.heading(labels.0, labels.1);
                    for record in records {
                        self.record(record, fields);
                    }
                }
            }
        }
        if !inspection.traits.is_empty() {
            self.heading("相关历史统计", "Other historical observations");
            for record in &inspection.traits {
                self.record(
                    record,
                    &[
                        "category",
                        "evidence_kind",
                        "observed_unit_id",
                        "place_id",
                        "region",
                        "scope",
                        "observation",
                        "opening_links",
                        "aggregation",
                        "source_id",
                        "locator",
                    ],
                );
                self.field(
                    "观测日期",
                    "Observation date",
                    value_text(&record["observed_date"]),
                );
                self.number(
                    "按此方式的人数",
                    "Observed adherents",
                    record["adherence"]["count"].as_u64(),
                );
                self.number(
                    "适用人数",
                    "Population to which it applies",
                    record["adherence"]["denominator"].as_u64(),
                );
            }
        }
    }

    fn show_coverage(&mut self, coverage: Option<&Value>) {
        self.heading("历史结构资料覆盖", "Historical structure coverage");
        let Some(coverage) = coverage else {
            self.field("覆盖范围", "Coverage scope", None::<String>);
            return;
        };
        if let Some(dimensions) = coverage["scope"]["dimensions"].as_object() {
            for (dimension, row) in dimensions {
                self.line(dimension.replace('_', " "));
                self.number(
                    "已复核资料表",
                    "Reviewed panels",
                    row["reviewed_panels"]
                        .as_array()
                        .map(|items| items.len() as u64),
                );
                self.number(
                    "候选资料表",
                    "Candidate panels",
                    row["candidate_panels"]
                        .as_array()
                        .map(|items| items.len() as u64),
                );
            }
        }
        if let Some(panels) = coverage["panels"]
            .as_object()
            .filter(|panels| !panels.is_empty())
        {
            self.heading("历史结构资料表", "Dated demographic panels");
            for panel in panels.values() {
                self.record(
                    panel,
                    &[
                        "dimension",
                        "status",
                        "observed_unit_id",
                        "observed_date",
                        "source_id",
                        "locator",
                        "classification_id",
                        "eligible_universe",
                        "measure_unit",
                        "directly_classified_count",
                        "category_relationship",
                        "categories",
                    ],
                );
                self.number(
                    "统计适用人数",
                    "Eligible denominator",
                    panel["eligible_denominator"].as_u64(),
                );
            }
        }
    }

    pub fn set_error(&mut self, message: impl Into<String>) {
        self.report.clear();
        self.layout.get_mut().take();
        self.scroll = 0;
        self.reported_query.clear();
        self.scope_relation = None;
        self.population_total = None;
        self.field("查询失败", "Query failed", Some(message.into()));
    }

    pub(crate) fn status(&self) -> Value {
        let layout = self.layout.borrow();
        let first = self.scroll.min(self.max_scroll.get());
        let visible_preview: Vec<_> = layout
            .as_ref()
            .into_iter()
            .flat_map(|layout| {
                layout
                    .lines
                    .iter()
                    .skip(first)
                    .take(4)
                    .map(|(line, _)| line)
            })
            .collect();
        serde_json::json!({
            "query": self.query,
            "input": self.input,
            "scroll": first,
            "scope_relation": self.scope_relation,
            "population_total": self.population_total,
            "visible_preview": visible_preview,
        })
    }

    fn heading(&mut self, zh: &'static str, en: &'static str) {
        self.report.push(Row {
            label: (zh, en),
            value: String::new(),
            heading: true,
            unknown: false,
        });
    }

    fn field<S: Into<String>>(&mut self, zh: &'static str, en: &'static str, value: Option<S>) {
        self.report.push(Row {
            label: (zh, en),
            heading: false,
            unknown: value.is_none(),
            value: value.map(Into::into).unwrap_or_default(),
        });
    }

    fn number(&mut self, zh: &'static str, en: &'static str, value: Option<u64>) {
        self.field(zh, en, value.map(number));
    }

    fn line(&mut self, value: String) {
        self.field("", "", Some(value));
    }

    fn record(&mut self, record: &Value, fields: &[&str]) {
        let identity = ["id", "panel_id", "record_id", "unit_id"]
            .into_iter()
            .find_map(|key| record[key].as_str());
        let title = ["title", "name"]
            .into_iter()
            .find_map(|key| record[key].as_str());
        let caption = match (title, identity) {
            (Some(title), Some(id)) if title != id => format!("{title}  |  {id}"),
            _ => title.or(identity).unwrap_or_default().into(),
        };
        if !caption.is_empty() {
            self.line(caption);
        }
        for key in fields {
            if *key == "population_value" {
                let (zh, en) = match record["kind"].as_str() {
                    Some("city") => ("历史城市人口", "Dated city population"),
                    Some("province") => ("历史省人口", "Dated province population"),
                    Some("admin") => ("历史行政区总人口", "Dated administrative total"),
                    Some("district") => ("历史地区人口", "Dated district population"),
                    _ => ("历史统计人口", "Dated population"),
                };
                self.number(zh, en, record[*key].as_u64());
                continue;
            }
            if let Some(value) = value_text(&record[*key]) {
                self.line(format!("  {}  {value}", key.replace('_', " ")));
            }
        }
    }

    pub(crate) fn scroll_by(&mut self, step: isize) {
        let limit = self.max_scroll.get();
        self.scroll = self
            .scroll
            .min(limit)
            .saturating_add_signed(step)
            .min(limit);
    }

    pub(crate) fn jump_section(&mut self, direction: isize) {
        let Some(layout) = self.layout.get_mut().as_ref() else {
            return;
        };
        let limit = self.max_scroll.get();
        let first = self.scroll.min(limit);
        let target = match direction.signum() {
            1 => layout
                .sections
                .iter()
                .copied()
                .find(|&row| row > first)
                .unwrap_or(limit),
            -1 => layout
                .sections
                .iter()
                .rev()
                .copied()
                .find(|&row| row < first)
                .unwrap_or(0),
            _ => first,
        };
        self.scroll = target.min(limit);
    }

    pub fn contains(&self, size: [u32; 2], [px, py]: [f64; 2]) -> bool {
        let [x, y, w, h] = bounds(size).map(f64::from);
        w >= 70. && h >= 98. && px >= x && py >= y && px < x + w && py < y + h
    }

    pub fn draw(&self, size: [u32; 2], skin: &Skin, background: &mut Mesh, text: &mut Mesh) {
        let [x, y, w, h] = bounds(size);
        if w < 70. || h < 98. {
            return;
        }
        background.rect(x, y, w, h, [13, 22, 29, 250]);
        background.rect(x, y, w, 2., GOLD);
        background.rect(x + 15., y + 41., w - 30., 33., [24, 38, 44, 255]);
        background.rect(x + 15., y + 97., w - 30., 1., [83, 95, 95, 255]);
        let left = x + 19.;
        let text_width = w - 43.;
        skin.text(
            text,
            skin.choose("人口调试", "Population Debug"),
            1,
            [left, y + 10.],
            text_width,
            GOLD,
        );
        let (query_text, query_color) = if self.input.is_empty() {
            (&self.query, MUTED)
        } else {
            (&self.input, INK)
        };
        let query = format!("{}  {query_text}", skin.choose("查询", "Query"));
        skin.text(text, &query, 0, [left, y + 47.], text_width, query_color);
        let help = skin.choose(
            "回车查询 · 地图选择 · 滚轮查看 · 左右键切换 · F7 关闭",
            "Enter to query · Select on map · Scroll · Left/Right sections · F7 to close",
        );
        skin.text(text, help, 0, [left, y + 75.], text_width, MUTED);
        let visible = ((h - BODY_TOP - FOOTER_HEIGHT) / ROW_HEIGHT)
            .floor()
            .max(0.) as usize;
        if visible == 0 {
            return;
        }

        let mut cache = self.layout.borrow_mut();
        let layout = cache.get_or_insert_with(|| self.layout(skin, text_width));
        if layout.width != text_width || layout.english != skin.english() {
            *layout = self.layout(skin, text_width);
        }
        let limit = layout.lines.len().saturating_sub(visible);
        self.max_scroll.set(limit);
        let first = self.scroll.min(limit);
        let last = (first + visible).min(layout.lines.len());
        for (index, (line, color)) in layout.lines[first..last].iter().enumerate() {
            skin.text(
                text,
                line,
                0,
                [left, y + BODY_TOP + index as f32 * ROW_HEIGHT],
                text_width,
                *color,
            );
        }
        if limit > 0 {
            let track = visible as f32 * ROW_HEIGHT;
            let thumb = (track * visible as f32 / layout.lines.len() as f32).max(10.);
            let offset = (track - thumb) * first as f32 / limit as f32;
            background.rect(x + w - 11., y + BODY_TOP, 3., track, [54, 68, 74, 255]);
            background.rect(x + w - 11., y + BODY_TOP + offset, 3., thumb, GOLD);
        }
        if !layout.lines.is_empty() {
            skin.text(
                text,
                &format!("{}–{} / {}", first + 1, last, layout.lines.len()),
                0,
                [left, y + h - 27.],
                text_width,
                MUTED,
            );
        }
    }

    fn layout(&self, skin: &Skin, width: f32) -> Layout {
        let mut lines = Vec::new();
        let mut sections = Vec::new();
        for row in &self.report {
            if row.heading {
                sections.push(lines.len());
            }
            let label = skin.choose(row.label.0, row.label.1);
            let value = if row.unknown {
                skin.choose("未知", "Unknown")
            } else {
                &row.value
            };
            let text = if row.heading || value.is_empty() {
                label.to_owned()
            } else if label.is_empty() {
                value.to_owned()
            } else {
                format!("{label}  {value}")
            };
            let color = if row.heading {
                GOLD
            } else if row.unknown {
                MUTED
            } else {
                INK
            };
            let text = romanize_russian(&text);
            wrap(skin, &text, width, &mut lines, color);
        }
        Layout {
            width,
            english: skin.english(),
            lines,
            sections,
        }
    }
}

// The HUD atlas has Latin glyphs. Source records still retain the census spelling.
fn romanize_russian(text: &str) -> std::borrow::Cow<'_, str> {
    const LETTERS: [&str; 32] = [
        "a", "b", "v", "g", "d", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p",
        "r", "s", "t", "u", "f", "kh", "ts", "ch", "sh", "shch", "\"", "y", "'", "e", "yu", "ya",
    ];
    if !text.chars().any(|ch| matches!(ch, 'А'..='я' | 'Ё' | 'ё')) {
        return text.into();
    }
    let mut result = String::with_capacity(text.len());
    for ch in text.chars() {
        let romanized = match ch {
            'А'..='Я' => LETTERS[(ch as u32 - 'А' as u32) as usize],
            'а'..='я' => LETTERS[(ch as u32 - 'а' as u32) as usize],
            'Ё' | 'ё' => "yo",
            _ => {
                result.push(ch);
                continue;
            }
        };
        if ch.is_uppercase() {
            result.push((romanized.as_bytes()[0] as char).to_ascii_uppercase());
            result.push_str(&romanized[1..]);
        } else {
            result.push_str(romanized);
        }
    }
    result.into()
}

fn bounds([width, height]: [u32; 2]) -> [f32; 4] {
    let (width, height) = (width as f32, height as f32);
    let w = if width >= 900. {
        (width * 0.62).min(860.)
    } else {
        (width - 32.).max(0.)
    };
    let h = (height - 90.).clamp(0., 805.);
    [(width - w - 16.).max(0.), (height - h) / 2. + 16., w, h]
}

fn joined(ids: &[&str]) -> Option<String> {
    (!ids.is_empty()).then(|| ids.join("  |  "))
}

fn daily_quantity(range: QuantityRange, unit: &str) -> String {
    format!("{}–{} {unit}", number(range.lower.round() as u64), number(range.upper.round() as u64))
}

fn interval(value: &Value) -> Option<String> {
    Some(format!(
        "{}–{}",
        number(value["population_lower"].as_u64()?),
        number(value["population_upper"].as_u64()?)
    ))
}

fn value_text(value: &Value) -> Option<String> {
    match value {
        Value::Null => None,
        Value::String(s) => (!s.is_empty()).then(|| s.clone()),
        Value::Number(n) => Some(n.as_u64().map_or_else(|| n.to_string(), number)),
        Value::Array(a) => {
            let values: Vec<_> = a.iter().filter_map(value_text).collect();
            (!values.is_empty()).then(|| values.join("  |  "))
        }
        Value::Object(o) => {
            let values: Vec<_> = o
                .iter()
                .filter_map(|(key, value)| {
                    Some(format!("{} {}", key.replace('_', " "), value_text(value)?))
                })
                .collect();
            (!values.is_empty()).then(|| values.join(", "))
        }
        _ => Some(value.to_string()),
    }
}

fn number(value: u64) -> String {
    let digits = value.to_string();
    let mut formatted = String::new();
    for (i, digit) in digits.chars().enumerate() {
        if i != 0 && (digits.len() - i) % 3 == 0 {
            formatted.push(',');
        }
        formatted.push(digit);
    }
    formatted
}

fn wrap(skin: &Skin, text: &str, width: f32, lines: &mut Vec<(String, [u8; 4])>, color: [u8; 4]) {
    let mut rest = text.trim_end();
    while !rest.is_empty() {
        if skin.width(rest, 0) <= width {
            lines.push((rest.to_owned(), color));
            break;
        }
        let mut filled = 0.;
        let mut end = 0;
        let mut word_end = 0;
        for (offset, ch) in rest.char_indices() {
            filled += skin.width(&rest[offset..offset + ch.len_utf8()], 0);
            if filled > width {
                break;
            }
            end = offset + ch.len_utf8();
            if ch.is_whitespace() {
                word_end = offset;
            }
        }
        let cut = if word_end > 2 {
            word_end
        } else if end > 0 {
            end
        } else {
            rest.chars().next().expect("non-empty line").len_utf8()
        };
        lines.push((rest[..cut].trim_end().to_owned(), color));
        rest = rest[cut..].trim_start();
    }
}
