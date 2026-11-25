use crate::{
    formal_ui::{Command, Display, Skin, BRASS, IVORY, MUTED},
    overlay::Mesh,
    transport_scene::{GeometryEvidence, TransportScene},
    ui::{Action, Hit, Mode},
    world::World,
};
use serde::{Deserialize, Serialize};
use wwo_map_lab::{
    formal_bootstrap::{mode_name, InitialWorld},
    transport::{NodeCoverage, TransportMode, TransportSegment},
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ObjectId {
    Node(String),
    Segment(String),
    Vehicle { segment: String, reservation: u64 },
}

pub struct MappedSite<'a> {
    pub name: &'a str,
    pub source: &'a str,
    pub note: &'a str,
}

#[derive(Clone)]
pub enum Link {
    Object(ObjectId),
    Travel(String),
    CurrentTravel,
    Market(String),
    Freight(u64),
}

pub struct Context<'a> {
    pub skin: &'a Skin,
    pub world: &'a InitialWorld,
    pub map: &'a World,
    pub date: &'a str,
    pub mode: Mode,
    pub scene: &'a TransportScene,
    pub debug: bool,
}

pub struct Detail {
    title: String,
    summary: Vec<String>,
    details: Vec<String>,
    pub links: Vec<(String, Link)>,
}

const TOP: f32 = 88.;
const ROW: f32 = 29.;

impl Detail {
    pub fn build(c: &Context<'_>, selected: &ObjectId) -> Option<Self> {
        let mut d = Self { title: String::new(), summary: vec![], details: vec![], links: vec![] };
        let id = match selected {
            ObjectId::Node(id) => { c.node(id, &mut d)?; id }
            ObjectId::Segment(id) => { c.segment(id, &mut d)?; id }
            ObjectId::Vehicle { segment, reservation } => {
                c.segment(segment, &mut d)?;
                if c.world.is_player_transport_reservation(*reservation) {
                    d.links.push(("查看本人行程".into(), Link::CurrentTravel));
                }
                if let Some(lot) = c.world.freight_for_reservation(*reservation) {
                    d.links.push(("查看在途货物".into(), Link::Freight(lot.id)));
                }
                segment
            }
        };
        if c.debug { d.details.insert(0, id.clone()); }
        Some(d)
    }

    pub fn rect(&self, size: [u32; 2], expanded: bool) -> [f32; 4] {
        let base = 52. + self.summary.len() as f32 * 23.
            + (self.links.len() + usize::from(!self.details.is_empty())) as f32 * ROW;
        let details = if expanded { self.details.len() as f32 * 36. } else { 0. };
        [17., TOP, 402_f32.min(size[0] as f32 - 34.),
            (base + details).min((size[1] as f32 - TOP - 145.).max(base))]
    }
}

impl Context<'_> {
    fn place<'a>(&'a self, id: &'a str) -> &'a str {
        self.skin.geographic_name(id).unwrap_or_else(|| self.world.place_name(id))
    }

    fn destination(&self, id: &str, label: String, d: &mut Detail) {
        if self.world.player_alive() && self.world.can_book_transport_to(id) {
            d.links.push((label, Link::Travel(id.into())));
        }
    }

    fn jurisdiction<'a>(&'a self, id: &str) -> Option<&'a str> {
        let sources = self.world.sources();
        let polity = sources.place_polity(id).or_else(|| {
            sources.polities().get(self.world.transport().unit_at(id)?)
        })?;
        if self.date < polity.valid_from.as_str() || self.date >= polity.valid_to.as_str()
            || !self.world.can_read_polity_record(&polity.id) {
            return None;
        }
        Some(self.map.polities.iter().find(|row| row.id == polity.id && row.active(self.date))
            .map_or(polity.name_zh.as_str(), |row| self.skin.country_name(row)))
    }

    fn edge(&self, id: &str) -> Option<&TransportSegment> {
        let network = self.world.transport();
        if network.evidence(id).is_some_and(|record| !record.applies_on(self.date)) { return None; }
        network.segment(id)
    }

    fn node(&self, id: &str, d: &mut Detail) -> Option<()> {
        let network = self.world.transport();
        if network.node(id).is_none() {
            let site = self.scene.reference_site(id)?;
            d.title = "历史地物".into();
            if self.world.can_read_opening_language() {
                d.title = site.name.into();
                d.details.extend([site.source, site.note].into_iter().filter(|s| !s.is_empty()).map(str::to_owned));
            }
            return Some(());
        }
        d.title = "交通地点".into();
        if !self.world.can_read_place_record(id) {
            if self.world.can_book_transport_to(id) {
                d.title = self.place(id).into();
                self.destination(id, "运往此处".into(), d);
            }
            return Some(());
        }
        d.title = self.place(id).into();
        d.summary.push(match network.coverage(id) {
            NodeCoverage::Connected => "可办理运输",
            NodeCoverage::Impassable => "已知连接停运",
            _ => "暂无可办理的已知连接",
        }.into());
        if self.mode == Mode::Political {
            if let Some(name) = self.jurisdiction(id) { d.summary.push(name.into()); }
        }
        self.destination(id, "运往此处".into(), d);
        if self.mode == Mode::Economic {
            if let Some(unit) = self.world.population_unit_at(id)
                .filter(|unit| self.world.macro_economy().markets().contains_key(*unit)) {
                d.links.push(("查看商品供需".into(), Link::Market(unit.into())));
            }
        }
        let sea_connections = || self.scene.node_corridors(id).iter().filter_map(|id| self.edge(id))
            .filter(|edge| edge.mode == TransportMode::Shipping);
        for edge in sea_connections().filter(|edge| edge.id == "shipping_channel")
            .chain(sea_connections().filter(|edge| edge.id != "shipping_channel")).take(2) {
            let other = if edge.from == id { &edge.to } else { &edge.from };
            d.links.push((format!("海运 · {}", self.place(other)), Link::Object(ObjectId::Segment(edge.id.clone()))));
        }
        Some(())
    }

    fn segment(&self, id: &str, d: &mut Detail) -> Option<()> {
        let edge = self.edge(id)?;
        d.title = "交通线路".into();
        if !self.world.can_read_place_record(&edge.from) && !self.world.can_read_place_record(&edge.to) {
            return Some(());
        }
        let network = self.world.transport();
        let direction = if edge.bidirectional { "往返" } else { "至" };
        d.title = format!("{} {direction} {}", self.place(&edge.from), self.place(&edge.to));
        if let Some(access) = network.availability(id) {
            let status = if !access.open || access.capacity_units == 0 { "停运" }
                else if access.capacity_units < edge.profile.capacity_units { "减运" }
                else { "运营" };
            let capacity = if access.open { access.capacity_units } else { 0 };
            d.summary.push(format!("{} · {status} · 运力 {capacity}", mode_name(edge.mode)));
        }
        if self.mode == Mode::Political {
            let mut names: Vec<_> = [&edge.from, &edge.to].into_iter().filter_map(|id| self.jurisdiction(id)).collect();
            names.dedup();
            if !names.is_empty() { d.summary.push(names.join(" / ")); }
        }
        if self.mode == Mode::Economic {
            let load: u64 = self.world.economic_transport_on(id).map(|flow| u64::from(flow.load_units)).sum();
            if load > 0 { d.summary.push(format!("在途货位 {load}")); }
        }
        for endpoint in [&edge.from, &edge.to] {
            self.destination(endpoint, format!("运往 {}", self.place(endpoint)), d);
        }
        let geometry = self.scene.segment_geometry(id);
        match geometry {
            GeometryEvidence::EstimatedSeaTrack => d.summary.push("估计航迹".into()),
            GeometryEvidence::SeaRelation => d.summary.push("港口运输关系 · 航迹待核实".into()),
            GeometryEvidence::Unmapped if edge.mode == TransportMode::Shipping => d.summary.push("航迹待核实".into()),
            _ => (),
        }
        d.details.push(match geometry {
            GeometryEvidence::HistoricalCorridor => "走廊有历史线位资料",
            GeometryEvidence::EstimatedSeaTrack => "按历史通航走廊估计，参考现有水陆边界",
            GeometryEvidence::SeaRelation => "虚线指示承运关系，具体航道待考证",
            GeometryEvidence::Schematic => "端点示意",
            GeometryEvidence::Unmapped if edge.mode == TransportMode::Shipping => "海运联系 · 航迹未确认",
            GeometryEvidence::Unmapped => "运营连接 · 线位未确认",
        }.into());
        d.details.push(format!("基准运行 {} 分钟", edge.profile.travel_minutes));
        if id == "shipping_channel" {
            d.details.push("泰晤士河口的历史水深与分时潮位待核实。".into());
        }
        if self.debug {
            if let Some(evidence) = network.evidence(id) { d.details.push(evidence.source.clone()); }
        }
        Some(())
    }
}

impl Display<'_> {
    pub(crate) fn transport_detail(&self, d: &Detail, panel: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>) {
        let expanded = self.hud.transport_detail_expanded;
        let [x, y, w, h] = d.rect(self.size, expanded);
        let left = x + 14.;
        let width = w - 28.;
        panel.rect(x, y, w, h, [13, 24, 31, 246]);
        panel.rect(x, y, w, 1., BRASS);
        self.skin.paragraph(text, &d.title, 1, [left, y + 10., width - 38., 38.], IVORY, 0.94);
        crate::formal_ui::close_button(panel, hits, [x + w - 15., y + 8.],
            Action::Hud(Command::CloseTransportDetail));
        let mut top = y + 48.;
        for value in &d.summary {
            self.skin.text(text, value, 0, [left, top], width, MUTED);
            top += 23.;
        }
        for (index, (value, _)) in d.links.iter().enumerate() {
            self.row(panel, text, hits, [left, top, width, 25.], value,
                Some(Action::Hud(Command::TransportDetail(index))), false);
            top += ROW;
        }
        if !d.details.is_empty() {
            self.row(panel, text, hits, [left, top, 102., 25.], if expanded { "收起" } else { "详细资料" },
                Some(Action::Hud(Command::ToggleTransportDetail)), false);
            top += ROW;
            if expanded {
                for value in &d.details {
                    if top + 34. > y + h { break; }
                    self.skin.paragraph(text, value, 0, [left, top, width, 34.], MUTED, 0.94);
                    top += 36.;
                }
            }
        }
    }
}

#[derive(Deserialize, PartialEq)]
pub struct TransportView {
    pub destinations: Vec<Destination>,
    pub destination: String,
    pub destination_label: String,
    pub location: String,
    pub cargo: bool,
    pub can_plan_work_trip: bool,
    pub can_move_home: bool,
    pub can_commute: bool,
    pub active: bool,
    #[serde(default)]
    pub freight_can_plan: bool,
    pub passenger_lines: Vec<String>,
    pub passenger_notice: String,
    pub travel_confirm: bool,
    pub lots: Vec<CargoRow>,
    pub freight_lines: Vec<String>,
    pub freight_notice: String,
    pub freight_actions: Vec<TransportAction>,
}

impl TransportView {
    pub fn planning(&self) -> bool {
        if self.cargo {
            self.freight_can_plan
        } else {
            !self.active
        }
    }
}

#[derive(Deserialize, PartialEq)]
pub struct Destination { pub id: String, pub label: String }

#[derive(Deserialize, PartialEq)]
pub struct CargoRow { pub id: u64, pub label: String, pub selected: bool }

#[derive(Deserialize, PartialEq)]
pub struct TransportAction { pub id: String, pub label: String }

fn action(command: Command) -> Option<Action> {
    Some(Action::Hud(command))
}

fn transport(verb: &'static str, index: usize) -> Option<Action> {
    action(Command::Transport(verb, index))
}

impl Display<'_> {
    pub(crate) fn travel_page(&self, panels: &mut Mesh, art: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>) {
        let Some([x, y, w, h]) = self.page_rect() else { return };
        self.folio(panels, art, text, hits, [x, y, w, h], "运输");
        self.transport_form(panels, text, hits, [x + 17., y + 55., w - 34., h - 65.], false);
    }

    pub(crate) fn freight_page(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>, bounds: [f32; 4]) {
        self.transport_form(panels, text, hits, bounds, true);
    }

    fn transport_form(&self, m: &mut Mesh, t: &mut Mesh, hits: &mut Vec<Hit>, [x,y,w,h]: [f32;4], freight: bool) {
        let Some(v) = self.session.and_then(|s| s.transport.as_ref()) else { return };
        let half = w * 0.5;
        if let Some(query) = &self.hud.transport_directory {
            let field = if query.is_empty() { "输入地点名称" } else { query };
            self.row(m,t,hits,[x,y,w,30.],field,None,true);
            let width = w / 4.;
            for (i, label) in ["全部", "城市", "港口", "地区"].into_iter().enumerate() {
                self.row(m,t,hits,[x+i as f32*width,y+39.,width-4.,27.],label,
                    action(Command::TransportCategory(i)),self.hud.transport_category==i);
            }
            if v.destinations.is_empty() {
                self.skin.text(t,if query.is_empty() { "输入名称或选择类别" } else { "未找到可办理运输的地点" },
                    0,[x,y+78.],w,MUTED);
            }
            let rows = ((h-76.)/32.).max(0.) as usize;
            for (i, row) in v.destinations.iter().take(rows).enumerate() {
                self.row(m,t,hits,[x,y+76.+i as f32*32.,w,28.],&row.label,transport("destination",i),false);
            }
            return;
        }

        let cargo = freight || v.cargo;
        let mut top = y;
        let heading = if v.destination_label.is_empty() { "选择目的地".to_owned() }
            else { format!("运往 {}", v.destination_label) };
        self.skin.text(t,&heading,1,[x,top],w,IVORY);
        top += 30.;
        if v.planning() {
            self.skin.text(t,"点击地图上的城市或港口",0,[x,top+5.],half-4.,MUTED);
        }
        self.row(m,t,hits,[x+half,top,half,27.],"搜索地点",action(Command::TransportDirectory),false);
        top += 36.;
        if !freight {
            self.row(m,t,hits,[x,top,half-4.,27.],"本人",transport("passenger",0),!cargo);
            self.row(m,t,hits,[x+half,top,half,27.],"已有货物",transport("cargo",0),cargo);
            top += 36.;
        }

        if cargo {
            if v.lots.is_empty() {
                self.skin.text(t,"暂无可办理的货物",0,[x,top],w,MUTED);
                return;
            }
            let lot = v.lots.iter().find(|lot| lot.selected).map_or("选择货物", |lot| &lot.label);
            self.row(m,t,hits,[x,top,w,28.],lot,action(Command::TransportLots),self.hud.transport_lots_open);
            top += 35.;
            if self.hud.transport_lots_open {
                let rows = ((y+h-top)/31.).max(0.) as usize;
                for (i, lot) in v.lots.iter().enumerate().skip(self.hud.lot_offset).take(rows) {
                    self.row(m,t,hits,[x,top,w,27.],&lot.label,transport("lot",i),lot.selected);
                    top += 31.;
                }
                return;
            }
            let mut buttons = Vec::new();
            for row in &v.freight_actions {
                let verb = match row.id.as_str() {
                    "freight_quote" => "freight_quote",
                    "freight_dispatch" => "freight_dispatch",
                    "sale_quote" => "sale_quote",
                    "sale_confirm" => "sale_confirm",
                    _ => continue,
                };
                buttons.push((row.label.as_str(),transport(verb,0)));
            }
            if !freight && v.freight_lines.len() > 3 {
                buttons.push((if self.hud.transport_steps { "收起" } else { "行程详情" },action(Command::TransportSteps)));
            }
            top = self.transport_buttons(m,t,hits,[x,top,w],&buttons);
            self.transport_lines(t,[x,top,w,y+h-top],&v.freight_lines,&v.freight_notice,4);
        } else {
            self.skin.text(t,&format!("{} {}",if v.active { "上一站" } else { "出发地" },v.location),0,[x,top],w,MUTED);
            top += 25.;
            let mut buttons = Vec::new();
            if v.active {
                buttons.push(("到下一站下车",transport("stop",0)));
            } else if v.travel_confirm {
                buttons.push(("付款并预约",transport("depart",0)));
            } else if !v.destination.is_empty() && v.destination_label != v.location {
                buttons.push(("更新报价",transport("preview",0)));
            }
            if v.can_plan_work_trip && v.destination.is_empty() { buttons.push(("前往工作地",transport("work_trip",0))); }
            if !v.passenger_lines.is_empty() || v.can_commute || v.can_move_home {
                buttons.push((if self.hud.transport_steps { "收起" } else { "行程详情" },action(Command::TransportSteps)));
            }
            top = self.transport_buttons(m,t,hits,[x,top,w],&buttons);
            if self.hud.transport_steps && !v.travel_confirm {
                let mut options = Vec::new();
                if v.can_commute { options.push(("设／停通勤",transport("commute",0))); }
                if v.can_move_home { options.push(("登记迁居",transport("move_home",0))); }
                top = self.transport_buttons(m,t,hits,[x,top,w],&options);
            }
            self.transport_lines(t,[x,top,w,y+h-top],&v.passenger_lines,&v.passenger_notice,3);
        }
    }

    fn transport_buttons(&self, m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,[x,y,w]:[f32;3],
        buttons:&[(&str,Option<Action>)]) -> f32 {
        if buttons.is_empty() { return y; }
        let cell=w/buttons.len() as f32;
        for (i,(label,action)) in buttons.iter().enumerate() {
            self.row(m,t,hits,[x+i as f32*cell,y,cell-4.,29.],label,*action,false);
        }
        y+36.
    }

    fn transport_lines(&self, t:&mut Mesh,[x,y,w,h]:[f32;4],lines:&[String],notice:&str,summary:usize) {
        let mut top = y;
        if !notice.is_empty() {
            self.skin.paragraph(t, notice, 0, [x,top,w,37.], MUTED, 1.);
            top += 40.;
        }
        let limit = if self.hud.transport_steps { lines.len() } else { summary };
        for (i,line) in lines.iter().take(limit).enumerate() {
            if top+22. > y+h { break; }
            self.skin.text(t,line,usize::from(i==1),[x,top],w,IVORY);
            top += 24.;
        }
    }
}
