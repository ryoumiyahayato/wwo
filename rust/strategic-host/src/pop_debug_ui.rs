use crate::{formal_ui::Skin, overlay::Mesh};
use serde_json::Value;
use std::{cell::Cell, cmp::Reverse, collections::BTreeMap};
use wwo_map_lab::{
    formal_macro::MacroEconomy,
    formal_population::{
        households::{HouseholdNeed, HouseholdNeeds, NeedPeriod},
        workforce::LaborSupply,
        CohortSex, PopulationInspection, PopulationStructure, RecordedPopulationDay, SocialDistribution,
    },
};

type Words = (&'static str, &'static str);
type Color = [u8; 4];

const PANEL: Color = [15, 25, 32, 255];
const ROW: Color = [23, 35, 43, 255];
const LINE: Color = [54, 73, 81, 255];
const INK: Color = [241, 234, 217, 255];
const MUTED: Color = [172, 188, 192, 255];
const GOLD: Color = [222, 189, 123, 255];
const TEAL: Color = [98, 185, 170, 255];
const BLUE: Color = [106, 155, 201, 255];
const MISSING: Color = [91, 106, 116, 255];
const PALETTE: [Color; 4] = [TEAL, GOLD, BLUE, [189, 132, 154, 255]];
const ROW_H: f32 = 25.;
const TOP: f32 = 78.;
const FOOTER: f32 = 27.;
const PYRAMID_ROWS: usize = 6;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Page {
    #[default]
    Overview,
    Structure,
    Needs,
    Changes,
}

const PAGES: [(Page, Words); 4] = [
    (Page::Overview, ("概况", "Overview")),
    (Page::Structure, ("结构", "Structure")),
    (Page::Needs, ("需求", "Needs")),
    (Page::Changes, ("变动", "Changes")),
];

const DIMENSIONS: [(&str, Words); 11] = [
    ("age", ("年龄", "Age")), ("sex", ("性别", "Sex")),
    ("class", ("阶层", "Class")), ("occupation", ("职业", "Occupation")),
    ("religion", ("宗教", "Religion")), ("culture", ("文化", "Culture")),
    ("language", ("语言", "Language")), ("literacy", ("识字", "Literacy")),
    ("residence", ("城乡", "Residence")), ("legal_estate", ("法律身份", "Legal status")),
    ("labour", ("劳动与产能", "Labour & output")),
];

#[derive(Default)]
struct Overview {
    name: String,
    current: Option<u64>,
    named: Option<u64>,
    direct: Option<u64>,
    children: Option<u64>,
    unlocated: Option<u64>,
    dated: Option<(u64, String)>,
    account: Option<String>,
    state_account: bool,
    parent: Option<String>,
    version: Option<u32>,
    relation: &'static str,
}

struct Group {
    name: String,
    count: u64,
    unknown: bool,
}

impl Group {
    fn label<'a>(&'a self, skin: &Skin) -> &'a str {
        if self.unknown { return skin.choose("未分配", "Unassigned"); }
        match self.name.as_str() {
            "male" => skin.choose("男性", "Male"),
            "female" => skin.choose("女性", "Female"),
            "Urban" => skin.choose("城市", "Urban"),
            "Rural" => skin.choose("农村", "Rural"),
            "Manual and service households" => skin.choose("体力与服务业家庭", "Manual and service households"),
            "Smallholder and self-employed households" => skin.choose("小农与自营家庭", "Smallholder and self-employed households"),
            "Salaried and professional households" => skin.choose("受薪与专业家庭", "Salaried and professional households"),
            "Proprietor and rentier households" => skin.choose("业主与食利家庭", "Proprietor and rentier households"),
            name => name,
        }
    }
}

#[derive(Default)]
struct Structure {
    // Sex columns are male, female and unassigned.
    age: Vec<(String, [u64; 3])>,
    pyramid: Vec<usize>,
    pyramid_max: u64,
    age_unassigned: [u64; 3],
    by_dimension: BTreeMap<&'static str, Distribution>,
    labour: Vec<LaborRow>,
    modelled_ages: u64,
}

struct LaborRow {
    label: Words,
    item: String,
    people: Option<u64>,
    hours: Option<u64>,
    output: String,
}

impl Structure {
    fn from_report(structure: &PopulationStructure<'_>, social: Option<&SocialDistribution<'_>>,
        labour: Option<&LaborSupply>, market: &MacroEconomy) -> Self {
        let mut result = Self::default();
        let mut sex = [0_u64; 2];
        let mut age_groups = BTreeMap::<(u16, Option<u16>), [u64; 3]>::new();
        for cohort in &structure.cohorts {
            let column = match cohort.sex {
                Some(CohortSex::Male) => 0,
                Some(CohortSex::Female) => 1,
                None => 2,
            };
            if column < 2 { sex[column] += cohort.members; }
            let Some(age) = cohort.age_years else { continue; };
            if cohort.evidence.as_ref().is_some_and(|evidence| evidence.method == "regional_age_sex_analogue_v44") {
                result.modelled_ages += cohort.members;
            }
            age_groups.entry((age.youngest, age.oldest)).or_default()[column] += cohort.members;
        }
        result.age = age_groups.into_iter().map(|((youngest, oldest), counts)| {
            let label = match oldest {
                Some(oldest) if youngest == oldest => youngest.to_string(),
                Some(oldest) => format!("{youngest}–{oldest}"),
                None => format!("{youngest}+"),
            };
            (label, counts)
        }).collect();
        result.pyramid = (0..result.age.len()).collect();
        result.pyramid.sort_by_key(|&i| Reverse(result.age[i].1.iter().sum::<u64>()));
        result.pyramid.truncate(PYRAMID_ROWS);
        result.pyramid.sort_unstable();
        result.pyramid_max = result.pyramid.iter().flat_map(|&i| &result.age[i].1[..2]).copied().max().unwrap_or(0);
        let total = structure.population_total;
        let sex_totals = [sex[0], sex[1], total - sex[0] - sex[1]];
        result.age_unassigned = std::array::from_fn(|column| {
            sex_totals[column] - result.age.iter().map(|(_, counts)| counts[column]).sum::<u64>()
        });
        result.by_dimension.insert("sex", Distribution::new(vec![
            Group { name: "male".into(), count: sex[0], unknown: false },
            Group { name: "female".into(), count: sex[1], unknown: false },
            Group { name: String::new(), count: total - sex[0] - sex[1], unknown: true },
        ]));
        for (dimension, _) in DIMENSIONS.into_iter().skip(2) {
            let mut distribution = Distribution::new(groups_for(social, dimension, total));
            distribution.modelled = social.and_then(|s| s.dimensions.get(dimension)).map_or(0, |s| s.modelled_residents);
            result.by_dimension.insert(dimension, distribution);
        }
        if let Some(labour) = labour {
            for (label, count) in [
                (("劳动人口", "Potential workers"), Some(labour.potential_workers)),
                (("儿童及未就学未成年人", "Children and nonstudents"), Some(labour.children)),
                (("学生", "Students"), Some(labour.students)), (("老年人", "Older residents"), Some(labour.older)),
                (("家庭照护者", "Family caregivers"), Some(labour.caregivers)),
                (("活动状态未分配", "Activity unassigned"), Some(labour.unresolved_activity)),
                (("失业", "Unemployment"), labour.unemployment),
            ] {
                result.labour.push(LaborRow { label, item: String::new(), people: count,
                    hours: (label.1 == "Potential workers").then_some(labour.annual_labor_hours), output: String::new() });
            }
            for sector in &labour.sectors {
                let label = match sector.id {
                    "cultivation" => ("种植业", "Cultivation"), "livestock" => ("畜牧业", "Livestock"),
                    "fisheries" => ("渔业", "Fisheries"), "forestry" => ("林业", "Forestry"),
                    "extraction" => ("采掘", "Extraction"), "manufacturing" => ("制造", "Manufacturing"),
                    "textiles" => ("纺织与制衣", "Textiles & clothing"),
                    "construction" => ("建筑", "Construction"), "commerce" => ("商业", "Commerce"),
                    "education" => ("教育", "Education"), "healthcare" => ("医疗", "Health care"),
                    "transport" => ("运输", "Transport"), _ => ("其他服务业", "Other services"),
                };
                result.labour.push(LaborRow { label, item: String::new(), people: Some(sector.workers),
                    hours: Some(sector.annual_hours), output: String::new() });
                for setup in &sector.alternatives {
                    for output in &setup.output {
                        let Some((name, _, unit)) = market.commodity_info(&output.commodity_id) else { continue; };
                        let mut amount = format!("{:.1} {unit}", output.units);
                        if let Some(own) = setup.own_use.iter().find(|own| own.commodity_id == output.commodity_id) {
                            amount.push_str(&format!(" / {:.1}", own.units));
                        }
                        result.labour.push(LaborRow { label: ("", ""), item: name.into(),
                            people: None, hours: None, output: amount });
                    }
                    if let Some(history) = &setup.historical_yield {
                        result.labour.push(LaborRow { label: ("单产参考 / 条件收成", "Yield / conditional harvest"),
                            item: String::new(), people: None, hours: None,
                            output: format!("{:.2} t/ha / {:.0} t", history.tonnes_per_hectare, history.conditional_tonnes_per_harvest) });
                    }
                }
            }
        }
        result
    }
}

struct Distribution {
    groups: Vec<Group>,
    other: u64,
    modelled: u64,
}

impl Distribution {
    fn new(groups: Vec<Group>) -> Self {
        let other = groups.iter().filter(|group| !group.unknown).skip(3).map(|group| group.count).sum();
        Self { groups, other, modelled: 0 }
    }
}

fn groups_for(social: Option<&SocialDistribution<'_>>, dimension: &str, total: u64) -> Vec<Group> {
    let mut counts = BTreeMap::<&str, u64>::new();
    let unknown = social.and_then(|social| social.dimensions.get(dimension)).map_or(total, |data| {
        for group in data.by_classification.values() {
            for (&category, &count) in group {
                *counts.entry(category).or_default() += count;
            }
        }
        data.unknown_residents
    });
    let mut groups: Vec<_> = counts.into_iter()
        .map(|(name, count)| Group { name: name.into(), count, unknown: false }).collect();
    groups.sort_by_key(|group| Reverse(group.count));
    if unknown > 0 {
        groups.push(Group { name: String::new(), count: unknown, unknown: true });
    }
    groups
}

struct Need {
    label: String,
    service: Option<Words>,
    unit: String,
    period: NeedPeriod,
    quantity: f64,
    eligible: u64,
}

#[derive(Default)]
struct Needs {
    rows: Vec<Need>,
    classes: Vec<Group>,
    by_class: BTreeMap<String, Vec<Need>>,
}

impl Needs {
    fn from_report(needs: &HouseholdNeeds, social: Option<&SocialDistribution<'_>>, market: &MacroEconomy) -> Self {
        let build = |rows: &[HouseholdNeed]| rows.iter().map(|row| Need {
            label: row.commodity_id.and_then(|id| market.commodity_info(id))
                .map_or(row.id, |(name, _, _)| name).into(),
            service: match row.id {
                "domestic_water" => Some(("生活用水", "Domestic water")),
                "occupied_housing_space" => Some(("居住面积", "Housing area")),
                "occupied_dwellings" => Some(("住房", "Dwellings")),
                "basic_care" => Some(("基础医疗", "Basic care")),
                "primary_school_places" => Some(("小学学位", "Primary places")),
                "local_passenger_trips" => Some(("地方出行", "Local trips")),
                "vegetables" => Some(("蔬菜", "Vegetables")),
                "wood_fuel" => Some(("薪柴", "Fuelwood")),
                "household_furnishings" => Some(("家具", "Furnishings")),
                _ => None,
            },
            unit: row.unit.clone(),
            period: row.period,
            quantity: row.quantity,
            eligible: row.eligible_people,
        }).collect::<Vec<_>>();
        let mut classes = groups_for(social, "class", needs.residents);
        let by_class = needs.by_class.iter().map(|group| (group.class.clone(), build(&group.needs))).collect();
        // Sources reporting an industrial position may not define household classes.
        classes.retain(|group| group.count != 0);
        Self { rows: build(&needs.needs), classes, by_class }
    }
}

pub struct Panel {
    pub input: String,
    pub query: String,
    pub scroll: usize,
    pub page: Page,
    pub place_name: Option<String>,
    pub revision: Option<(i64, usize)>,
    overview: Overview,
    structure: Structure,
    needs: Needs,
    days: Vec<RecordedPopulationDay>,
    population_range: Option<(u64, u64)>,
    dimension: usize,
    class: usize,
    mobility_open: bool,
    failed: bool,
    max_scroll: Cell<usize>,
}

impl Default for Panel {
    fn default() -> Self {
        Self {
            input: String::new(), query: "world".into(), scroll: 0, page: Page::Overview,
            place_name: None, revision: None, overview: Overview::default(),
            structure: Structure::default(), needs: Needs::default(), days: Vec::new(),
            population_range: None,
            dimension: 0, class: 0, mobility_open: false, failed: false, max_scroll: Cell::new(0),
        }
    }
}

impl Panel {
    pub fn set_report(
        &mut self, report: &PopulationInspection<'_>, social: Option<&SocialDistribution<'_>>,
        needs: Option<&HouseholdNeeds>, labour: Option<&LaborSupply>, market: &MacroEconomy, days: Vec<RecordedPopulationDay>,
    ) {
        let city_without_account = report.population_total.is_none() && report.query_id.starts_with("place:");
        let account = report.account_name.or(report.account_id).map(str::to_owned);
        let dated = report.city_reference.as_ref().or_else(|| report.archive.as_ref()?.dated_population.first());
        self.overview = Overview {
            name: self.place_name.clone().or_else(|| {
                (!city_without_account).then(|| report.account_name.map(str::to_owned)).flatten()
            }).unwrap_or_else(|| report.query_id.to_owned()),
            current: report.population_total,
            named: report.structure.as_ref().map(|structure| structure.named_residents),
            direct: report.direct_residents,
            children: report.child_residents,
            unlocated: report.opening.and_then(|opening| opening.research_unlocated_balance),
            dated: dated.and_then(|row| Some((row["population_value"].as_u64()?,
                row["source_date"].as_str().or(row["date"].as_str()).unwrap_or_default().into()))),
            account,
            state_account: report.account_id.is_some_and(|id| id.starts_with("us_state_")),
            parent: report.parent_name.or(report.parent_id).map(str::to_owned),
            version: report.opening_version,
            relation: report.scope_relation,
        };
        if self.page == Page::Structure {
            self.structure = report.structure.as_ref()
                .map(|structure| Structure::from_report(structure, social, labour, market)).unwrap_or_default();
        }
        if self.page == Page::Needs {
            self.needs = needs.map(|needs| Needs::from_report(needs, social, market)).unwrap_or_default();
            self.class = self.class.min(self.needs.classes.len());
        }
        self.population_range = days.iter().filter_map(|day| day.population).fold(None, |range, value| {
            Some(range.map_or((value, value), |(min, max): (u64, u64)| (min.min(value), max.max(value))))
        });
        self.days = days;
        self.failed = false;
    }

    pub fn set_error(&mut self) {
        self.failed = true;
        self.overview = Overview::default();
        self.scroll = 0;
    }

    pub fn contains(&self, size: [u32; 2], point: [f64; 2]) -> bool {
        inside(bounds(size), point)
    }

    pub fn page_at(&self, size: [u32; 2], point: [f64; 2]) -> Option<Page> {
        let [x, y, w, _] = bounds(size);
        let width = (w - 24.) / PAGES.len() as f32;
        PAGES.iter().enumerate().find_map(|(i, &(page, _))|
            inside([x + 12. + i as f32 * width, y + 42., width, 31.], point).then_some(page))
    }

    pub fn next_page(&self) -> Page {
        let index = PAGES.iter().position(|&(page, _)| page == self.page).unwrap_or(0);
        PAGES[(index + 1) % PAGES.len()].0
    }

    pub fn reset_location(&mut self) {
        self.scroll = 0;
        self.class = 0;
    }

    pub fn click_control(&mut self, size: [u32; 2], point: [f64; 2]) {
        let [x, y, w, _] = self.body(size);
        match self.page {
            Page::Structure => {
                if let Some(index) = (0..DIMENSIONS.len()).find(|&i| inside(dimension_rect(x, y, w, i), point)) {
                    self.dimension = index;
                    self.scroll = 0;
                }
            }
            Page::Needs if !self.needs.classes.is_empty() => {
                let count = self.needs.classes.len() + 1;
                if inside([x + w - 63., y, 30., 28.], point) {
                    self.class = (self.class + count - 1) % count;
                    self.scroll = 0;
                } else if inside([x + w - 30., y, 30., 28.], point) {
                    self.class = (self.class + 1) % count;
                    self.scroll = 0;
                }
            }
            Page::Changes if inside([x, y + 112., w, 28.], point) => {
                self.mobility_open = !self.mobility_open;
                self.scroll = 0;
            }
            _ => {}
        }
    }

    pub(crate) fn scroll_by(&mut self, step: isize) {
        self.scroll = self.scroll.min(self.max_scroll.get()).saturating_add_signed(step).min(self.max_scroll.get());
    }

    pub(crate) fn status(&self) -> Value {
        serde_json::json!({
            "query": self.query, "input": self.input, "scroll": self.scroll,
            "scope_relation": self.overview.relation, "page": format!("{:?}", self.page),
            "population_total": self.overview.current, "dimension": DIMENSIONS[self.dimension].0,
            "class_selection": self.class, "recorded_days": self.days.len(),
        })
    }

    fn body(&self, size: [u32; 2]) -> [f32; 4] {
        let [x, y, w, h] = bounds(size);
        [x + 12., y + TOP, w - 24., (h - TOP - FOOTER).max(0.)]
    }

    pub fn draw(&self, size: [u32; 2], skin: &Skin, background: &mut Mesh, text: &mut Mesh) {
        let [x, y, w, h] = bounds(size);
        if w < 240. || h < 150. { return; }
        let mut ui = Surface { skin, fill: background, text };
        ui.fill.rect(x, y, w, h, PANEL);
        ui.fill.rect(x, y, w, 2., GOLD);
        let title = match self.overview.name.as_str() {
            "world" => skin.choose("全球", "World"),
            "unmapped" | "" => skin.choose("未选地区", "No area selected"),
            name => name,
        };
        ui.label(("人口", "Population"), [x + 13., y + 11., 80., 19.], GOLD);
        ui.text(title, [x + 95., y + 11., w - 108., 19.], INK);
        let tab_w = (w - 24.) / PAGES.len() as f32;
        for (index, &(page, label)) in PAGES.iter().enumerate() {
            ui.button(label, [x + 12. + tab_w * index as f32, y + 42., tab_w - 2., 30.], page == self.page);
        }
        if self.failed {
            ui.label(("查询失败", "Query failed"), self.body(size), MUTED);
        } else {
            let body = self.body(size);
            match self.page {
                Page::Overview => self.draw_overview(&mut ui, body),
                Page::Structure => self.draw_structure(&mut ui, body),
                Page::Needs => self.draw_needs(&mut ui, body),
                Page::Changes => self.draw_changes(&mut ui, body),
            }
        }
        let footer = [x + 12., y + h - FOOTER + 3., w - 24., 20.];
        if self.input.is_empty() {
            ui.label(("点击地图切换地区  ·  右击国家  ·  F7 关闭",
                "Select an area  ·  Right-click a country  ·  F7 closes"), footer, MUTED);
        } else {
            ui.text(&self.input, footer, GOLD);
        }
    }

    fn draw_overview(&self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4]) {
        self.max_scroll.set(0);
        let data = &self.overview;
        let present = data.current.is_some();
        let local_label = if data.relation == "world" { ("全球总人口", "World population") }
            else { ("当地总人口", "Local population") };
        ui.fill.rect(x, y, w, 68., ROW);
        ui.label(local_label, [x + 11., y + 7., w - 22., 17.], MUTED);
        ui.text(&data.current.map(number).unwrap_or_else(|| ui.word(("未知", "Unknown")).into()),
            [x + 11., y + 28., w - 22., 22.], INK);
        if !present {
            let mut top = y + 80.;
            if let Some((population, date)) = &data.dated {
                ui.pair(("历史人口 · 未分配", "Dated population · unallocated"), &number(*population), [x, top, w, 24.]);
                top += 25.;
                ui.pair(("统计日期", "Census date"), date, [x, top, w, 24.]);
                top += 25.;
            }
            if let Some(account) = &data.account {
                let label = if data.state_account { ("所属州统计账户", "Containing U.S. state account") }
                    else { ("所属统计账户", "Containing statistical account") };
                ui.label(label, [x + 4., top, w - 8., 19.], MUTED);
                ui.text(account, [x + 4., top + 22., w - 8., 20.], INK);
            }
            return;
        }
        let half = w / 2.;
        let rows = [
            (("具名人口", "Named"), data.named),
            (("未具名人口", "Unnamed"), data.current.zip(data.named).map(|(total, named)| total - named)),
            (("直属人口", "Direct residents"), data.direct),
            (("下级地区", "Child accounts"), data.children),
            (("未定位余额", "Unlocated balance"), data.unlocated),
            (("底账版本", "Opening version"), data.version.map(u64::from)),
        ];
        for (i, (label, count)) in rows.into_iter().enumerate() {
            let left = x + (i % 2) as f32 * half;
            let top = y + 80. + (i / 2) as f32 * 62.;
            if top + 54. > y + h { break; }
            ui.fill.rect(left, top, half - 5., 54., ROW);
            ui.label(label, [left + 9., top + 5., half - 21., 16.], MUTED);
            ui.text(&option_number(count), [left + 9., top + 24., half - 21., 19.], INK);
        }
        if y + 305. <= y + h {
            if let Some(parent) = &data.parent {
                ui.pair(("上级账户", "Parent account"), parent, [x, y + 271., w, 24.]);
            }
        }
    }

    fn draw_structure(&self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4]) {
        for (i, &(_, label)) in DIMENSIONS.iter().enumerate() {
            ui.button(label, dimension_rect(x, y, w, i), self.dimension == i);
        }
        let Some(total) = self.overview.current else {
            self.max_scroll.set(0);
            ui.label(("当地人口未分配", "Local population unallocated"), [x, y + 63., w, 22.], MUTED);
            return;
        };
        let start = y + 79.;
        let skin = ui.skin;
        if DIMENSIONS[self.dimension].0 == "labour" {
            ui.label(("估算 · 各配方为备选 · 产量 / 自用", "Estimated · Alternative recipes · Output / own use"),
                [x, start, w, 22.], MUTED);
            let headers = [("行业或商品", "Sector or good"), ("人数", "People"), ("工时/年", "Hours/year"),
                ("并行批次产量", "Parallel batch output")];
            let rows = self.structure.labour.iter().map(|row| vec![
                if row.item.is_empty() { skin.choose(row.label.0, row.label.1).into() } else { row.item.clone() },
                option_number(row.people),
                row.hours.map_or_else(|| "—".into(), |hours| magnitude(hours as f64, skin)),
                row.output.clone(),
            ]);
            self.table(ui, [x, start + 24., w, (y + h - start - 24.).max(0.)], &headers,
                &[0.30, 0.16, 0.17, 0.37], self.structure.labour.len(), rows);
            return;
        }
        let modelled = if self.dimension < 2 { self.structure.modelled_ages } else {
            self.structure.by_dimension.get(DIMENSIONS[self.dimension].0).map_or(0, |row| row.modelled)
        };
        let start = if modelled > 0 {
            ui.text(&format!("{} {}", ui.word(("含模型估算", "Modelled residents")), number(modelled)),
                [x, start, w, 18.], MUTED);
            start + 20.
        } else { start };
        let chart = (h - 180.).clamp(72., 150.);
        let table_y = start + chart + 6.;
        let table_h = (y + h - table_y).max(0.);
        if self.dimension == 0 {
            self.draw_pyramid(ui, [x, start, w, chart]);
            let widths = [0.18, 0.205, 0.205, 0.205, 0.205];
            let headers = [("年龄", "Age"), ("男性", "Male"), ("女性", "Female"),
                ("未知性别", "Sex unknown"), ("人口比例", "Share")];
            let rows = std::iter::once((skin.choose("年龄未分组", "Unclassified age"), &self.structure.age_unassigned))
                .chain(self.structure.age.iter().map(|(label, counts)| (label.as_str(), counts)))
                .map(|(label, counts)| vec![label.into(), number(counts[0]), number(counts[1]),
                    number(counts[2]), share(counts.iter().sum(), total)]);
            self.table(ui, [x, table_y, w, table_h], &headers, &widths, self.structure.age.len() + 1, rows);
        } else if let Some(distribution) = self.structure.by_dimension.get(DIMENSIONS[self.dimension].0) {
            self.draw_pie(ui, [x, start, w, chart], distribution, total);
            let headers = [("类别", "Category"), ("人数", "Residents"), ("比例", "Share")];
            let widths = [0.58, 0.25, 0.17];
            let groups = &distribution.groups;
            let rows = groups.iter().map(|group| vec![group.label(skin).into(), number(group.count), share(group.count, total)]);
            self.table(ui, [x, table_y, w, table_h], &headers, &widths, groups.len(), rows);
        }
    }

    fn draw_pyramid(&self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4]) {
        ui.fill.rect(x, y, w, h, ROW);
        let axis = x + w / 2.;
        let pad = 28.;
        let bar = (w / 2. - pad).max(0.);
        let max = self.structure.pyramid_max;
        ui.label(("男性", "Male"), [x + 11., y + 3., 75., 16.], TEAL);
        ui.right(ui.word(("女性", "Female")), [x + w - 85., y + 3., 72., 16.], GOLD);
        if max == 0 {
            ui.center(ui.word(("没有年龄与性别联合数据", "No joint age and sex data")), [x, y + h / 2. - 9., w, 20.], MUTED);
            return;
        }
        let label = if self.structure.age.len() > PYRAMID_ROWS {
            ("人数最多的六个年龄组", "Six largest age groups")
        } else {
            ("底账年龄组", "Ledger age groups")
        };
        ui.center(ui.word(label), [x, y + 3., w, 16.], MUTED);
        let span = ((h - 26.) / self.structure.pyramid.len() as f32).min(30.);
        for (i, &index) in self.structure.pyramid.iter().rev().enumerate() {
            let (label, values) = &self.structure.age[index];
            let top = y + 23. + i as f32 * span;
            let width = |value| bar * value as f32 / max as f32;
            ui.fill.rect(axis - pad - width(values[0]), top, width(values[0]), (span - 2.).max(1.), TEAL);
            ui.fill.rect(axis + pad, top, width(values[1]), (span - 2.).max(1.), GOLD);
            ui.center(label, [axis - pad, top - 2., 2. * pad, span], MUTED);
        }
    }

    fn draw_pie(&self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4], distribution: &Distribution, total: u64) {
        ui.fill.rect(x, y, w, h, ROW);
        if total == 0 { return; }
        let groups = &distribution.groups;
        let known = groups.iter().filter(|group| !group.unknown && group.count > 0);
        let mut slices: Vec<_> = known.take(3).enumerate()
            .map(|(i, group)| (group.label(ui.skin), group.count, PALETTE[i])).collect();
        if distribution.other > 0 { slices.push((ui.word(("其他", "Other")), distribution.other, PALETTE[3])); }
        if let Some(group) = groups.iter().find(|group| group.unknown && group.count > 0) {
            slices.push((group.label(ui.skin), group.count, MISSING));
        }
        let r = (h / 2. - 8.).max(1.);
        let center = [x + r + 16., y + h / 2.];
        let mut angle = -std::f32::consts::FRAC_PI_2;
        let spacing = (h / slices.len().max(1) as f32).min(22.);
        for (i, (name, count, color)) in slices.into_iter().enumerate() {
            let sweep = std::f32::consts::TAU * count as f32 / total as f32;
            let steps = ((sweep * 10.).ceil() as usize).max(2);
            let mut points = Vec::with_capacity(steps + 2);
            points.push(center);
            points.extend((0..=steps).map(|j| {
                let a = angle + sweep * j as f32 / steps as f32;
                [center[0] + r * a.cos(), center[1] + r * a.sin()]
            }));
            ui.fill.shape(&points, color);
            angle += sweep;
            let left = x + 2. * r + 30.;
            let top = y + 5. + i as f32 * spacing;
            ui.fill.rect(left, top + 7., 8., 8., color);
            ui.text(name, [left + 13., top, w - (left - x) - 78., spacing], INK);
            ui.right(&share(count, total), [x + w - 66., top, 55., spacing], MUTED);
        }
    }

    fn draw_needs(&self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4]) {
        let classes = &self.needs.classes;
        let group = self.class.checked_sub(1).and_then(|i| classes.get(i));
        let filter = group.map_or(ui.word(("全部人口", "All residents")), |group| group.label(ui.skin));
        ui.fill.rect(x, y, w, 28., ROW);
        ui.label(("阶层", "Class"), [x + 7., y + 3., 65., 20.], MUTED);
        ui.text(filter, [x + 72., y + 3., w - 220., 20.], INK);
        if let Some(group) = group {
            ui.right(&number(group.count), [x + w - 149., y + 3., 77., 20.], MUTED);
        }
        if !classes.is_empty() {
            ui.button(("‹", "‹"), [x + w - 63., y, 30., 28.], false);
            ui.button(("›", "›"), [x + w - 30., y, 30., 28.], false);
        }
        let rows = if let Some(group) = group {
            self.needs.by_class.get(&group.name).map(Vec::as_slice)
        } else {
            Some(self.needs.rows.as_slice())
        };
        let note = if rows.is_none() {
            ("该阶层需求未计算", "Requirements for this class have not been calculated")
        } else if self.needs.rows.is_empty() {
            ("当地人口未分配", "Local population unallocated")
        } else {
            ("需求为模型估算  ·  实际消费与满足率未统计", "Modelled needs  ·  Actual use and fulfilment unmeasured")
        };
        ui.label(note, [x + 2., y + 33., w - 4., 22.], MUTED);
        let headers = [("商品或服务", "Good or service"), ("人均需求", "Per person"),
            ("总需求", "Total need"), ("实际消费", "Actual use"), ("满足率", "Fulfilled")];
        let widths = [0.245, 0.218, 0.247, 0.166, 0.124];
        let skin = ui.skin;
        let rows = rows.unwrap_or_default();
        let values = rows.iter().map(|need| {
            let individual = (need.eligible != 0).then(|| need.quantity / need.eligible as f64);
            vec![need.service.map_or(need.label.as_str(), |label| skin.choose(label.0, label.1)).into(),
                quantity(individual, &need.unit, need.period, true, skin),
                quantity(Some(need.quantity), &need.unit, need.period, false, skin),
                "—".into(), "—".into()]
        });
        self.table(ui, [x, y + 58., w, (h - 58.).max(0.)], &headers, &widths, rows.len(), values);
    }

    fn draw_changes(&self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4]) {
        ui.fill.rect(x, y, w, 106., ROW);
        ui.label(("总人口 · 最近 14 日", "Total population · last 14 days"), [x + 8., y + 3., w - 16., 17.], MUTED);
        if let Some((min, max)) = self.population_range {
            let plot = [x + 112., y + 25., (w - 126.).max(0.), 56.];
            ui.label(("日期", "Date"), [x + 8., y + 86., 68., 17.], MUTED);
            ui.right(&number(max), [x + 3., y + 21., 101., 17.], MUTED);
            if min != max { ui.right(&number(min), [x + 3., y + 65., 101., 17.], MUTED); }
            for offset in [0., 28., 56.] {
                ui.fill.line([plot[0], plot[1] + offset], [plot[0] + plot[2], plot[1] + offset], 1., LINE);
            }
            let position = |i: usize, value: u64| [
                plot[0] + if self.days.len() == 1 { plot[2] / 2. }
                    else { plot[2] * i as f32 / (self.days.len() - 1) as f32 },
                plot[1] + if max == min { plot[3] / 2. }
                    else { plot[3] * (max - value) as f32 / (max - min) as f32 },
            ];
            let mut previous = None;
            for (i, day) in self.days.iter().enumerate() {
                let current = day.population.map(|value| position(i, value));
                if let Some(point) = current {
                    if let Some(before) = previous { ui.fill.line(before, point, 2.0, TEAL); }
                    ui.fill.rect(point[0] - 2., point[1] - 2., 4., 4., TEAL);
                }
                previous = current;
            }
            if let Some(first) = self.days.first() {
                ui.text(&short_date(first), [plot[0], y + 86., 55., 17.], MUTED);
            }
            if let Some(last) = self.days.last().filter(|_| self.days.len() > 1) {
                ui.right(&short_date(last), [x + w - 65., y + 86., 55., 17.], MUTED);
            }
        } else {
            ui.label(("当地人口未分配", "Local population unallocated"), [x + 9., y + 42., w - 18., 20.], MUTED);
        }
        ui.button(if self.mobility_open { ("−  阶层流动", "−  Class mobility") }
            else { ("+  阶层流动", "+  Class mobility") }, [x, y + 112., w, 28.], false);
        let mut top = y + 145.;
        if self.mobility_open {
            let headers = [("原阶层", "From class"), ("新阶层", "To class"), ("人数", "Residents")];
            ui.row(&headers.map(|label| ui.word(label).to_owned()), &[0.38, 0.38, 0.24], [x, top, w, 23.], true);
            top += 24.;
            ui.label(("阶层流动未统计", "Class mobility unmeasured"), [x + 7., top, w - 14., 23.], MUTED);
            top += 28.;
        }
        ui.label(("底账已记录事件  ·  — 无可用统计", "Ledger events  ·  — unavailable"), [x + 4., top, w - 8., 20.], MUTED);
        top += 23.;
        let headers = [("日期", "Date"), ("出生", "Births"), ("死亡", "Deaths"), ("迁入", "In"),
            ("迁出", "Out"), ("净变化", "Net")];
        let widths = [0.20, 0.16, 0.16, 0.16, 0.16, 0.16];
        let rows = self.days.iter().rev().map(|day| {
            vec![short_date(day), event_count(day.births, false), event_count(day.deaths, false),
                event_count(day.immigration, day.journal_covers_day), event_count(day.emigration, day.journal_covers_day),
                if day.journal_covers_day { format!("{:+}", day.net()) } else { "—".into() }]
        });
        self.table(ui, [x, top, w, (y + h - top).max(0.)], &headers, &widths, self.days.len(), rows);
    }

    fn table<const N: usize>(
        &self, ui: &mut Surface<'_>, [x, y, w, h]: [f32; 4],
        headers: &[Words; N], widths: &[f32; N], len: usize, rows: impl Iterator<Item = Vec<String>>,
    ) {
        let visible = ((h - ROW_H) / ROW_H).floor().max(0.) as usize;
        let limit = len.saturating_sub(visible);
        self.max_scroll.set(limit);
        if h < ROW_H { return; }
        let row_w = if limit > 0 { w - 7. } else { w };
        let header = headers.map(|label| ui.word(label).to_owned());
        ui.row(&header, widths, [x, y, row_w, ROW_H], true);
        let first = self.scroll.min(limit);
        for (i, cells) in rows.skip(first).take(visible).enumerate() {
            ui.row(&cells, widths, [x, y + (i + 1) as f32 * ROW_H, row_w, ROW_H], false);
        }
        if limit > 0 && visible > 0 {
            let track = visible as f32 * ROW_H;
            let thumb = (track * visible as f32 / len as f32).max(13.);
            ui.fill.rect(x + w - 4., y + ROW_H, 3., track, LINE);
            ui.fill.rect(x + w - 4., y + ROW_H + (track - thumb) * first as f32 / limit as f32, 3., thumb, GOLD);
        }
    }
}

struct Surface<'a> {
    skin: &'a Skin,
    fill: &'a mut Mesh,
    text: &'a mut Mesh,
}

impl Surface<'_> {
    fn word(&self, label: Words) -> &'static str { self.skin.choose(label.0, label.1) }

    fn text(&mut self, text: &str, [x, y, w, _]: [f32; 4], color: Color) {
        if w > 0. { self.skin.text(self.text, text, 0, [x + 2., y], w - 2., color); }
    }

    fn label(&mut self, label: Words, area: [f32; 4], color: Color) {
        self.text(self.word(label), area, color);
    }

    fn right(&mut self, value: &str, [x, y, w, h]: [f32; 4], color: Color) {
        let offset = (w - self.skin.width(value, 0)).max(0.);
        self.text(value, [x + offset, y, w - offset + 2., h], color);
    }

    fn center(&mut self, value: &str, [x, y, w, h]: [f32; 4], color: Color) {
        let offset = ((w - self.skin.width(value, 0)) / 2.).max(0.);
        self.text(value, [x + offset, y, w - offset, h], color);
    }

    fn button(&mut self, label: Words, [x, y, w, h]: [f32; 4], active: bool) {
        self.button_text(self.word(label), [x, y, w, h], active);
    }

    fn button_text(&mut self, label: &str, [x, y, w, h]: [f32; 4], active: bool) {
        self.fill.rect(x, y, w, h, if active { [47, 62, 67, 255] } else { ROW });
        if active { self.fill.rect(x, y + h - 2., w, 2., GOLD); }
        self.center(label, [x, y + (h - 18.).max(0.) * 0.5, w, h], if active { GOLD } else { INK });
    }

    fn pair(&mut self, label: Words, value: &str, [x, y, w, h]: [f32; 4]) {
        self.label(label, [x + 4., y, w * 0.45, h], MUTED);
        self.right(value, [x + w * 0.45, y, w * 0.55 - 5., h], INK);
    }

    fn row(&mut self, cells: &[String], widths: &[f32], [x, y, w, h]: [f32; 4], header: bool) {
        self.fill.rect(x, y, w, h - 1., if header { [33, 51, 56, 255] } else { ROW });
        let mut left = x;
        for (i, (value, fraction)) in cells.iter().zip(widths).enumerate() {
            let width = w * fraction;
            let area = [left + 5., y + 3., width - 10., h];
            let color = if header || value == "—" { MUTED } else { INK };
            if i == 0 || header { self.text(value, area, color); }
            else { self.right(value, area, color); }
            left += width;
        }
    }
}

pub(crate) fn bounds([w, h]: [u32; 2]) -> [f32; 4] {
    let (w, h) = (w as f32, h as f32);
    let width = if w > 1050. { (w * 0.44).clamp(520., 630.) } else { (w * 0.59).min(520.) };
    let top = if h >= 630. { 103. } else { 65. };
    [(w - width - 41.).max(0.), top, width, (h - top - 115.).max(0.)]
}

fn inside([x, y, w, h]: [f32; 4], [px, py]: [f64; 2]) -> bool {
    w > 0. && h > 0. && px >= f64::from(x) && px < f64::from(x + w)
        && py >= f64::from(y) && py < f64::from(y + h)
}

fn dimension_rect(x: f32, y: f32, w: f32, index: usize) -> [f32; 4] {
    let width = w / 5.;
    [x + (index % 5) as f32 * width, y + (index / 5) as f32 * 25., width - 3., 23.]
}

fn short_date(day: &RecordedPopulationDay) -> String {
    format!("{:02}-{:02}", day.date.month, day.date.day)
}

fn number(value: u64) -> String {
    let raw = value.to_string();
    let mut result = String::with_capacity(raw.len() + raw.len() / 3);
    for (i, digit) in raw.chars().enumerate() {
        if i > 0 && (raw.len() - i) % 3 == 0 { result.push(','); }
        result.push(digit);
    }
    result
}

fn option_number(count: Option<u64>) -> String { count.map(number).unwrap_or_else(|| "—".into()) }

fn event_count(count: u64, observed_zero: bool) -> String {
    option_number((count > 0 || observed_zero).then_some(count))
}

fn share(count: u64, total: u64) -> String {
    if total == 0 { "—".into() } else { format!("{:.1}%", count as f64 / total as f64 * 100.) }
}

fn quantity(value: Option<f64>, unit: &str, period: NeedPeriod, per_person: bool, skin: &Skin) -> String {
    let Some(mut value) = value else { return "—".into(); };
    let unit = match (unit, per_person, value.abs()) {
        ("吨", true, _) if value >= 0.001 => { value *= 1_000.; "kg" }
        ("吨", true, _) => { value *= 1_000_000.; "g" }
        ("吨", false, _) => "t",
        ("千件", true, _) => { value *= 1_000.; skin.choose("件", "items") }
        ("百件", true, _) => { value *= 100.; skin.choose("件", "items") }
        ("百套", true, _) => { value *= 100.; skin.choose("套", "sets") }
        ("百匹", true, _) => { value *= 100.; skin.choose("匹", "bolts") }
        ("百箱", true, _) => { value *= 100.; skin.choose("箱", "cases") }
        ("百万支", true, _) => { value *= 1_000_000.; skin.choose("支", "pieces") }
        ("兆瓦时", true, _) => { value *= 1_000.; "kWh" }
        ("dwellings", _, _) => skin.choose("户", "homes"),
        ("visits" | "trips", _, _) => skin.choose("次", "trips"),
        ("places", _, _) => skin.choose("位", "seats"),
        _ => unit,
    };
    let suffix = match period {
        NeedPeriod::Day => skin.choose("/日", "/d"),
        NeedPeriod::Year => skin.choose("/年", "/yr"),
        NeedPeriod::Occupancy => "",
    };
    format!("{} {unit}{suffix}", magnitude(value, skin))
}

fn magnitude(value: f64, skin: &Skin) -> String {
    if value == 0. { "0".into() }
        else if value >= 1_000_000_000. { skin.choose(
            &format!("{:.2}亿", value / 100_000_000.),
            &format!("{:.2}B", value / 1_000_000_000.),
        ).to_owned() }
        else if value >= 100_000. { skin.choose(
            &format!("{:.2}万", value / 10_000.),
            &format!("{:.2}M", value / 1_000_000.),
        ).to_owned() }
        else if value >= 100. { format!("{:.1}", value) }
        else if value >= 0.01 { format!("{:.3}", value) }
        else { format!("{:.2e}", value) }
}
