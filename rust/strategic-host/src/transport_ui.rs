use crate::{
    formal_ui::{Command, Display, Page, Skin, BRASS, IVORY, MUTED},
    overlay::Mesh,
    transport_scene::{GeometryEvidence, TransportScene},
    ui::{Action, Hit, Mode},
    world::World,
};
use serde::{Deserialize, Serialize};
use wwo_map_lab::{
    formal_bootstrap::{
        economy_read::{ShipmentStatus, TradeShipment},
        freight::FreightState,
        AuthorityKind, InitialWorld, Polity,
    },
    formal_clock::{GameClock, MINUTES_PER_DAY},
    formal_ledger::LedgerPayment,
    military_grid::MilitaryCell,
    transport::{NetworkLayer, NodeCoverage, NodeKind, TransportMode, TransportSegment},
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ObjectId {
    Node(String),
    Segment(String),
    Vehicle { segment: String, reservation: u64 },
}

pub struct MappedSite<'a> {
    pub name: &'a str,
    pub kind: &'a str,
    pub source: &'a str,
    pub note: &'a str,
    pub coordinates: [f64; 2],
}

#[derive(Clone, PartialEq, Eq)]
pub enum Link {
    Object(ObjectId),
    Travel(String),
    CurrentTravel,
    Market(String),
    Firm { id: String, drawer: &'static str },
    Freight(u64),
    Battle(MilitaryCell),
}

pub struct Context<'a> {
    pub skin: &'a Skin,
    pub world: &'a InitialWorld,
    pub map: &'a World,
    pub date: &'a str,
    pub mode: Mode,
    pub scene: &'a TransportScene,
}

pub struct Detail {
    title: String,
    heading: &'static str,
    rows: Vec<(String, Option<usize>)>,
    pub links: Vec<Link>,
}

const DETAIL_Y: f32 = 96.;
const DETAIL_ROW: f32 = 35.;

impl Detail {
    pub fn build(context: &Context<'_>, selected: &ObjectId) -> Option<Self> {
        let skin = context.skin;
        let heading = match context.mode {
            Mode::Geographic => skin.choose("地理 · 交通", "Geography · Transport"),
            Mode::Political => skin.choose("政治 · 管辖与通行", "Politics · Jurisdiction and access"),
            Mode::Economic => skin.choose("经济 · 运力与结算", "Economy · Capacity and settlement"),
            Mode::Military => skin.choose("军事 · 交通基础设施", "Military · Transport infrastructure"),
        };
        let mut detail = Self { title: String::new(), heading, rows: Vec::new(), links: Vec::new() };
        match selected {
            ObjectId::Node(id) => context.node(id, &mut detail)?,
            ObjectId::Segment(id) => context.segment(id, &mut detail)?,
            ObjectId::Vehicle { segment, reservation } =>
                context.vehicle(segment, *reservation, &mut detail)?,
        }
        Some(detail)
    }

    fn line(&mut self, text: impl Into<String>) {
        self.rows.push((text.into(), None));
    }

    fn link(&mut self, label: impl Into<String>, link: Link) {
        if self.links.contains(&link) { return; }
        self.rows.push((label.into(), Some(self.links.len())));
        self.links.push(link);
    }

    fn rows_per_page(&self, size: [u32; 2]) -> usize {
        ((size[1] as f32 - DETAIL_Y - 177. - 96.) / DETAIL_ROW).max(1.) as usize
    }

    pub fn page_count(&self, size: [u32; 2]) -> usize {
        self.rows.len().div_ceil(self.rows_per_page(size)).max(1)
    }

    pub fn rect(&self, size: [u32; 2]) -> [f32; 4] {
        let rows = self.rows_per_page(size).min(self.rows.len());
        let footer = if self.page_count(size) > 1 { 36. } else { 8. };
        [17., DETAIL_Y, (size[0] as f32 - 34.).clamp(220., 452.), 56. + rows as f32 * DETAIL_ROW + footer]
    }
}

impl Context<'_> {
    fn say<'a>(&self, zh: &'a str, en: &'a str) -> &'a str { self.skin.choose(zh, en) }

    fn place<'a>(&'a self, id: &'a str) -> &'a str {
        if let Some(name) = self.skin.geographic_name(id) { return name; }
        self.world.place_name(id)
    }

    fn mode_name(&self, mode: TransportMode) -> &'static str {
        match mode {
            TransportMode::Rail => self.say("铁路", "Rail"),
            TransportMode::Road => self.say("道路", "Road"),
            TransportMode::Shipping => self.say("海运", "Sea"),
            TransportMode::InlandWaterway => self.say("河运", "River"),
            TransportMode::PortTransfer => self.say("港口换装", "Port transfer"),
            _ => self.say("地区集散", "Regional distribution"),
        }
    }

    fn restricted_status(&self, edge: &TransportSegment) -> &'static str {
        let access = self.world.transport().availability(&edge.id);
        match access {
            Some(access) if !access.open || access.capacity_units == 0 => self.say("停运", "Closed"),
            Some(access) if access.capacity_units < edge.profile.capacity_units => self.say("减容", "Capacity reduced"),
            Some(_) => self.say("可运营", "Operating"),
            None => self.say("运营状态待核", "Operating status unknown"),
        }
    }

    fn node(&self, id: &str, detail: &mut Detail) -> Option<()> {
        let network = self.world.transport();
        let Some(node) = network.node(id) else {
            return self.reference(id, detail);
        };
        if !self.world.can_read_place_record(id) {
            detail.title = self.say("交通节点", "Transport node").into();
            detail.line(self.say("人物尚不能阅读当地交通记录。", "The character cannot read the local transport record."));
            return Some(());
        }
        detail.title = self.place(id).to_owned();
        detail.line(id);
        let corridors = || self.scene.node_corridors(id).iter()
            .filter_map(|id| self.edge(id));
        match self.mode {
            Mode::Geographic => {
                let kind = match node.kind {
                    NodeKind::Port if corridors().any(|e| e.mode == TransportMode::Shipping) =>
                        self.say("海港", "Seaport"),
                    NodeKind::Port if corridors().any(|e| e.mode == TransportMode::InlandWaterway) =>
                        self.say("内河港／码头", "River port / landing"),
                    NodeKind::Port => self.say("港口", "Port"),
                    NodeKind::City => self.say("城市交通节点", "City transport node"),
                    NodeKind::Junction => self.say("交通连接点", "Transport junction"),
                    NodeKind::Area => self.say("统计地区集散节点", "Statistical distribution hub"),
                    NodeKind::Identity => self.say("历史地点", "Historical location"),
                };
                detail.line(kind);
                if let Some(point) = network.node_coordinates(id) { self.coordinates(point, detail); }
                detail.line(match network.coverage(id) {
                    NodeCoverage::Connected => self.say("交通覆盖 · 已接入运营网络", "Coverage · Connected to the operating network"),
                    NodeCoverage::Impassable => self.say("交通覆盖 · 已知连接停运", "Coverage · Known connections closed"),
                    NodeCoverage::Unrefined => self.say("交通覆盖 · 线路待细化", "Coverage · Route detail pending"),
                    NodeCoverage::Unknown => self.say("交通覆盖 · 资料待核", "Coverage · Evidence pending"),
                });
                for note in network.notes_at(id) { detail.line(note); }
                self.travel_link(id, detail);
            }
            Mode::Political => {
                self.jurisdiction_line(id, detail);
                detail.line(self.say("签证与海关规则待接入。", "Visa and customs rules are pending."));
            }
            Mode::Economic => {
                if let Some(unit) = self.world.population_unit_at(id) {
                    self.market_link(unit, detail);
                    self.local_economy_links(id, detail);
                    self.firm_orders(unit, id, detail);
                    self.market_activity(unit, detail);
                } else {
                    detail.line(self.say("当地正式市场待核。", "A formal market is unconfirmed here."));
                    self.local_economy_links(id, detail);
                }
            }
            Mode::Military => {
                self.military_context([network.node_coordinates(id)], detail);
            }
        }
        let mut edges = corridors().peekable();
        if edges.peek().is_none() {
            detail.line(self.say("运营连接资料待核。", "Operating connections are unconfirmed."));
        }
        for edge in edges {
            let (arrow, other) = if edge.from == id {
                (if edge.bidirectional { "<->" } else { "→" }, &edge.to)
            } else {
                (if edge.bidirectional { "<->" } else { "<-" }, &edge.from)
            };
            let mut label = format!("{} {arrow} {} · {}", self.mode_name(edge.mode),
                self.place(other), self.restricted_status(edge));
            if self.mode == Mode::Military {
                if let Some(access) = network.availability(&edge.id) {
                    let capacity = if access.open { access.capacity_units } else { 0 };
                    label.push_str(&format!(" · {} {capacity}", self.say("运力", "Slots")));
                }
            }
            detail.link(label, Link::Object(ObjectId::Segment(edge.id.clone())));
        }
        Some(())
    }

    fn reference(&self, id: &str, detail: &mut Detail) -> Option<()> {
        let site = self.scene.reference_site(id)?;
        if !self.world.can_read_opening_language() {
            detail.title = self.say("交通史料", "Transport reference").into();
            detail.line(self.say("人物尚不能阅读该书面资料。", "The character cannot read this record."));
            return Some(());
        }
        detail.title = site.name.into();
        detail.line(id);
        detail.line(match site.kind {
            "bridge" => self.say("桥梁 · 历史地物", "Bridge · Historical site"),
            "station" => self.say("车站 · 历史地物", "Station · Historical site"),
            "port" => self.say("港口 · 历史地物", "Port · Historical site"),
            _ => self.say("历史交通地物", "Historical transport site"),
        });
        match self.mode {
            Mode::Geographic => {
                self.coordinates(site.coordinates, detail);
                if !site.source.is_empty() { detail.line(site.source); }
                if !site.note.is_empty() { detail.line(site.note); }
            }
            Mode::Political => {
                detail.line(self.say("地物管辖和通行规则待核。", "Site jurisdiction and passage rules are unconfirmed."));
                detail.line(self.say("签证与海关规则待接入。", "Visa and customs rules are pending."));
            }
            Mode::Economic => detail.line(self.say("此地物的正式班次、容量与市场连接待核。",
                "Formal services, capacity and market connections are unconfirmed for this site.")),
            Mode::Military => self.military_context([Some(site.coordinates)], detail),
        }
        Some(())
    }

    fn edge(&self, id: &str) -> Option<&TransportSegment> {
        let network = self.world.transport();
        if network.evidence(id).is_some_and(|record| !record.applies_on(self.date)) { return None; }
        network.segment(id)
    }

    fn segment(&self, id: &str, detail: &mut Detail) -> Option<()> {
        let edge = self.edge(id)?;
        if !self.segment_readable(edge) {
            detail.title = self.say("交通线路", "Transport corridor").into();
            detail.line(self.say("人物尚不能阅读线路记录。", "The character cannot read the corridor record."));
            return Some(());
        }
        let arrow = if edge.bidirectional { "<->" } else { "→" };
        detail.title = format!("{} {arrow} {}", self.place(&edge.from), self.place(&edge.to));
        detail.line(id);
        detail.line(format!("{} · {}", self.mode_name(edge.mode), self.restricted_status(edge)));
        match self.mode {
            Mode::Geographic => {
                self.geographic_segment(edge, detail);
                self.travel_link(&edge.from, detail);
                self.travel_link(&edge.to, detail);
            }
            Mode::Political => {
                self.jurisdiction_line(&edge.from, detail);
                self.jurisdiction_line(&edge.to, detail);
                let from = self.jurisdiction(&edge.from);
                let to = self.jurisdiction(&edge.to);
                if let Some((from, to)) = from.zip(to).filter(|(a, b)|
                    self.world.can_read_polity_record(&a.id) && self.world.can_read_polity_record(&b.id)) {
                    detail.line(if from.id == to.id {
                        self.say("两端属于同一记录辖区。", "Both endpoints have the same recorded jurisdiction.")
                    } else {
                        self.say("两端分属不同记录辖区。", "The endpoints have different recorded jurisdictions.")
                    });
                }
                self.line_capacity(edge, detail);
                detail.line(self.say("签证与海关规则待接入。", "Visa and customs rules are pending."));
            }
            Mode::Economic => self.segment_economy(edge, detail),
            Mode::Military => {
                if self.scene.segment_geometry(id) == GeometryEvidence::Schematic {
                    detail.line(match edge.mode {
                        TransportMode::Shipping => self.say("虚线示意航路。实际航迹待核。",
                            "Dashed schematic sea lane. Exact course unconfirmed."),
                        _ => self.say("虚线连接代表地点。实际线路走向待核。",
                            "Dashes connect representative locations. Exact alignment unconfirmed."),
                    });
                }
                self.line_capacity(edge, detail);
                self.military_context([self.world.place_coordinates(&edge.from),
                    self.world.place_coordinates(&edge.to)], detail);
            }
        }
        for endpoint in [&edge.from, &edge.to] {
            detail.link(format!("{} · {}", self.say("节点", "Node"), self.place(endpoint)),
                Link::Object(ObjectId::Node(endpoint.clone())));
        }
        Some(())
    }

    fn segment_readable(&self, edge: &TransportSegment) -> bool {
        self.world.can_read_place_record(&edge.from) || self.world.can_read_place_record(&edge.to)
    }

    fn coordinates(&self, [lon, lat]: [f64; 2], detail: &mut Detail) {
        detail.line(format!("{} {lon:.4} · {} {lat:.4}",
            self.say("经度", "Longitude"), self.say("纬度", "Latitude")));
    }

    fn travel_link(&self, id: &str, detail: &mut Detail) {
        let station = self.world.last_station();
        if self.world.player_alive() && !self.world.passenger_in_transit()
            && self.world.can_select_transport_destination(id)
            && self.world.transport().routing_node(station) != self.world.transport().routing_node(id) {
            detail.link(format!("{} · {}", self.say("查询旅行", "Plan travel"), self.place(id)),
                Link::Travel(id.into()));
        }
    }

    fn geographic_segment(&self, edge: &TransportSegment, detail: &mut Detail) {
        detail.line(match self.scene.segment_geometry(&edge.id) {
            GeometryEvidence::HistoricalCorridor =>
                self.say("线路形状 · 历史走廊资料", "Route geometry · Historical corridor"),
            GeometryEvidence::Schematic if edge.mode == TransportMode::Shipping =>
                self.say("线路形状 · 示意航路", "Route geometry · Schematic sea lane"),
            GeometryEvidence::Schematic =>
                self.say("线路形状 · 端点示意", "Route geometry · Endpoint schematic"),
            GeometryEvidence::Unmapped =>
                self.say("线路形状待核 · 运营连接有记录", "Geometry pending · Operating connection recorded"),
        });
        detail.line(format!("{} {} {} · {} {}",
            self.say("基准运行", "Base running time"),
            edge.profile.travel_minutes, self.say("分钟", "min"),
            self.say("基准运力", "Nominal capacity"), edge.profile.capacity_units));
        if let Some(record) = self.world.transport().evidence(&edge.id) {
            let layer = match record.layer {
                NetworkLayer::Detailed => self.say("具名走廊", "Named corridor"),
                NetworkLayer::Domestic => self.say("地区统计连接", "Statistical distribution link"),
                NetworkLayer::Maritime => self.say("历史海运估计", "Historical maritime estimate"),
                NetworkLayer::River => self.say("河运资料", "Inland navigation source"),
                NetworkLayer::Transfer => self.say("换装连接", "Transfer link"),
            };
            let date = record.opened_on.as_deref().unwrap_or(record.as_of);
            let basis = if record.opened_on.is_some() { self.say("开通", "Opened") }
                else { self.say("校准日期", "Calibrated") };
            detail.line(format!("{layer} · {basis} {date}"));
            detail.line(&record.source);
            if let Some(confidence) = record.confidence_bp {
                detail.line(format!("{} {:.1}%", self.say("来源置信度", "Source confidence"),
                    f64::from(confidence) / 100.));
            }
        }
    }

    fn jurisdiction(&self, node: &str) -> Option<&Polity> {
        let sources = self.world.sources();
        let polity = sources.place_polity(node).or_else(|| {
            let unit = self.world.transport().unit_at(node)?;
            sources.polities().get(unit)
        })?;
        (polity.valid_from.as_str() <= self.date && self.date < polity.valid_to.as_str()).then_some(polity)
    }

    fn polity_name<'a>(&'a self, polity: &'a Polity) -> &'a str {
        self.map.polities.iter().find(|row| row.id == polity.id && row.active(self.date))
            .map_or_else(|| self.say(&polity.name_zh, &polity.id), |row| self.skin.country_name(row))
    }

    fn jurisdiction_line(&self, node: &str, detail: &mut Detail) {
        let place = self.place(node);
        let Some(polity) = self.jurisdiction(node) else {
            detail.line(format!("{place} · {}", self.say("管辖资料待核", "Jurisdiction unconfirmed")));
            return;
        };
        if !self.world.can_read_polity_record(&polity.id) {
            detail.line(format!("{place} · {}", self.say("人物尚不能阅读辖区资料", "Jurisdiction record unreadable")));
            return;
        }
        detail.line(format!("{place} · {}", self.polity_name(polity)));
        if let Some((controller, kind)) = self.world.sources().authority(&polity.id)
            .filter(|(p, _)| p.id != polity.id && self.world.can_read_polity_record(&p.id)) {
            let label = match kind {
                AuthorityKind::Administration => self.say("行政管理", "Administration"),
                AuthorityKind::Occupation => self.say("军事占领", "Occupation"),
                AuthorityKind::Protection => self.say("保护关系", "Protector"),
                AuthorityKind::LegacyController => self.say("记录控制方", "Recorded controller"),
            };
            detail.line(format!("{label} · {}", self.polity_name(controller)));
        }
    }

    fn line_capacity(&self, edge: &TransportSegment, detail: &mut Detail) {
        if let Some(access) = self.world.transport().availability(&edge.id) {
            let cap = if access.open { access.capacity_units } else { 0 };
            detail.line(format!("{} {cap}/{} · {} {}",
                self.say("运营／基准运力", "Operating / nominal slots"), edge.profile.capacity_units,
                self.say("当前占用", "Occupied"), self.world.occupied_transport_units(&edge.id)));
        }
    }

    fn military_context<const N: usize>(&self, points: [Option<[f64; 2]>; N], detail: &mut Detail) {
        detail.line(self.say("军运、征用与调度权限待接入。",
            "Military transport, requisition and dispatch authority are pending."));
        if let Some(record) = self.world.land_battle_record() {
            let cell = record.cell();
            if points.into_iter().flatten().any(|point| MilitaryCell::at(point, cell.size_km) == Some(cell)) {
                detail.link(format!("{} #{}", self.say("查看已有战场", "Open existing battlefield"), record.id),
                    Link::Battle(cell));
            }
        }
    }

    fn market_link(&self, unit: &str, detail: &mut Detail) {
        let name = self.world.sources().polities().get(unit)
            .map_or(unit, |polity| self.polity_name(polity));
        detail.link(format!("{} · {name}", self.say("地区市场", "Regional market")),
            Link::Market(unit.into()));
    }

    fn local_economy_links(&self, node: &str, detail: &mut Detail) {
        let at_node = |place: &str| self.world.transport().routing_node(place) == Some(node);
        for (firm, drawer) in self.world.organizations()
            .filter(|org| org.firm.is_some() && at_node(&org.place))
            .filter_map(|org| self.firm_drawer(&org.id, &org.place).map(|drawer| (org, drawer)))
            .take(4)
        {
            detail.link(format!("{} · {}", self.say("商号", "Firm"), firm.name),
                Link::Firm { id: firm.id.clone(), drawer });
        }
        for lot in self.world.freight_lots().rev().filter(|lot| match &lot.state {
            FreightState::Purchased => at_node(&lot.origin),
            FreightState::Interrupted { place } => at_node(place),
            FreightState::InTransit { reservation_id, destination } =>
                at_node(destination) || self.world.freight_progress(*reservation_id).0.is_some_and(at_node),
            FreightState::Delivered { destination } | FreightState::Sold { destination, .. } =>
                at_node(destination),
        }).take(4) {
            let name = self.world.macro_economy().commodity_info(&lot.good)
                .map_or(lot.good.as_str(), |(name, _, _)| name);
            let state = match &lot.state {
                FreightState::Purchased => self.say("待发运", "Awaiting dispatch"),
                FreightState::InTransit { .. } => self.say("在途", "In transit"),
                FreightState::Interrupted { .. } => self.say("中断", "Interrupted"),
                FreightState::Delivered { .. } => self.say("已到达", "Delivered"),
                FreightState::Sold { .. } => self.say("已售出", "Sold"),
            };
            detail.link(format!("{} #{} · {name} · {state}", self.say("货批", "Freight lot"), lot.id),
                Link::Freight(lot.id));
        }
    }

    fn firm_orders(&self, unit: &str, at: &str, detail: &mut Detail) {
        let network = self.world.transport();
        let orders = self.world.firm_material_orders(Some(unit)).filter(|row|
            [row.from, row.to].into_iter().any(|id| network.routing_node(id) == Some(at)));
        for order in orders.take(3) {
            detail.line(format!("{} · {} {} · {} {} · {} {}",
                self.say("物料订单", "Material order"),
                self.say("订购", "Ordered"), order.requested,
                self.say("待供", "Pending"), order.pending,
                self.say("交付", "Delivered"), order.delivered));
            detail.line(format!("{} → {} · {}",
                self.place(order.from), self.place(order.to), order.reference));
            let delivery = order.delivery_day.and_then(|day| day.checked_mul(MINUTES_PER_DAY));
            if let Some(delivery) = delivery {
                detail.line(format!("{} {}", self.say("交付日", "Delivery date"),
                    clock_label(delivery)));
            }
            if let Some(payment) = order.goods_payment {
                self.payment(self.say("商号货款", "Firm goods payment"), payment, detail);
            }
            for id in [order.buyer, order.seller] {
                self.firm_link(id, detail);
            }
        }
    }

    fn firm_link(&self, id: &str, detail: &mut Detail) {
        let Some(organization) = self.world.organization(id) else { return };
        let Some(drawer) = self.firm_drawer(id, &organization.place) else { return };
        detail.link(format!("{} · {}", self.say("商号", "Firm"), organization.name),
            Link::Firm { id: id.into(), drawer });
    }

    fn firm_drawer(&self, id: &str, place: &str) -> Option<&'static str> {
        if self.world.player_current_place() == Some(place) {
            Some("local")
        } else if self.world.player_organization_role(id).is_some() {
            Some("relations")
        } else {
            None
        }
    }

    fn market_activity(&self, unit: &str, detail: &mut Detail) {
        let Some(market) = self.world.macro_economy().markets().get(unit) else { return };
        detail.line(format!("{} {} · {} {}",
            self.say("市场品种", "Market commodities"), market.commodities.len(),
            self.say("供给未满足品种", "Commodities with unmet demand"),
            market.commodities.values().filter(|row| row.unmet > 0.).count()));
        let shipments = self.world.trade_market_shipments(unit);
        self.trade_rows(shipments, detail);
    }

    fn segment_economy(&self, edge: &TransportSegment, detail: &mut Detail) {
        self.line_capacity(edge, detail);
        let Some(economy) = self.world.transport_economy(&edge.id) else { return };
        if let Some(unit) = economy.from_market { self.market_link(unit, detail); }
        if let Some(unit) = economy.to_market.filter(|unit| Some(*unit) != economy.from_market) {
            self.market_link(unit, detail);
        }
        for end in [&edge.from, &edge.to] {
            if let Some(c) = self.world.transport_service_capacity(&edge.id, end) {
                detail.line(format!("{} · {} {}/{} · {} {}/{} · {} {}/{}", self.place(end),
                    self.say("班次", "Service"), c.service_used, c.service_limit,
                    self.say("货位", "Cargo"), c.cargo_used, c.cargo_limit,
                    self.say("客座", "Seats"), c.seats_used, c.seat_limit));
                let in_transit: u64 = economy.reservations.iter().filter(|row|
                    row.from == end && row.moving && row.freight).map(|row| u64::from(row.load_units)).sum();
                if in_transit > 0 {
                    detail.line(format!("{} · {} {in_transit}", self.place(end),
                        self.say("在途货位", "Freight slots in transit")));
                }
            }
        }
        if !economy.reservations.is_empty() {
            let moving = economy.reservations.iter().filter(|row| row.moving).count();
            detail.line(format!("{} {moving} · {} {}",
                self.say("运行预约", "Moving reservations"),
                self.say("待发预约", "Scheduled reservations"), economy.reservations.len() - moving));
        }
        for row in economy.reservations.iter().filter(|row| row.freight_lot.is_some()).take(4) {
            let Some(lot) = row.freight_lot else { continue };
            let status = if row.moving { self.say("抵达本段", "Segment arrival") }
                else { self.say("计划发车", "Scheduled departure") };
            let minute = if row.moving { row.ends } else { row.starts };
            detail.link(format!("{} #{lot} · {status} {}", self.say("货批", "Freight lot"), clock_label(minute)),
                Link::Freight(lot));
        }
        let shipment = economy.trade.first().or_else(|| economy.interrupted_trade.first())
            .or_else(|| economy.last_arrivals.first());
        if let Some(row) = shipment {
            for unit in [economy.from_market, economy.to_market].into_iter().flatten() {
                self.commodity_balance(unit, &row.shipment.commodity, detail);
            }
        }
        let shipments = economy.interrupted_trade.into_iter().chain(economy.trade).chain(economy.last_arrivals);
        self.trade_rows(shipments, detail);
    }

    fn commodity_balance(&self, unit: &str, commodity: &str, detail: &mut Detail) {
        let economy = self.world.macro_economy();
        let Some(state) = economy.markets().get(unit).and_then(|m| m.commodities.get(commodity)) else { return };
        let (product, measure) = economy.commodity_info(commodity)
            .map_or((commodity, ""), |(name, _, measure)| (name, measure));
        detail.line(format!("{unit} · {product} · {} {:.1}{measure} · {} {:.1}{measure}",
            self.say("库存", "Stock"), state.inventory, self.say("需求", "Demand"), state.demanded));
    }

    fn trade_rows<'a>(&self, shipments: impl IntoIterator<Item = TradeShipment<'a>>, detail: &mut Detail) {
        for read in shipments.into_iter().take(4) {
            let shipment = read.shipment;
            let (name, unit) = self.world.macro_economy().commodity_info(&shipment.commodity)
                .map_or((shipment.commodity.as_str(), ""), |(name, _, unit)| (name, unit));
            let status = match read.status {
                ShipmentStatus::Scheduled => self.say("已预约", "Scheduled"),
                ShipmentStatus::InTransit => self.say("在途", "In transit"),
                ShipmentStatus::Held => self.say("停运待续", "Held"),
                ShipmentStatus::Delivered => self.say("已交割", "Delivered"),
                ShipmentStatus::LegacyInTransit => self.say("旧在途记录", "Legacy in transit"),
            };
            detail.line(format!("{status} · {name} {:.1}{unit} · {} → {}",
                shipment.units, shipment.origin, shipment.destination));
            if let Some(at) = read.at {
                detail.line(format!("{} {}", self.say("最近站点", "Last stop"), self.place(at)));
            }
            if let Some(minute) = read.arrival_minute {
                let label = if read.status == ShipmentStatus::Delivered { self.say("交割", "Delivery") }
                    else { self.say("预计抵达", "Expected arrival") };
                detail.line(format!("{label} {}", clock_label(minute)));
            }
            for (label, payment) in [
                (self.say("货款", "Goods payment"), read.goods_payment),
                (self.say("运费", "Freight payment"), read.freight_payment),
                (self.say("退款", "Refund"), read.refund),
            ] {
                if let Some(payment) = payment { self.payment(label, payment, detail); }
            }
        }
    }

    fn payment(&self, label: &str, payment: LedgerPayment<'_>, detail: &mut Detail) {
        detail.line(format!("{label} · {} {} · {}",
            payment.amount, payment.denomination, clock_label(payment.minute)));
    }

    fn vehicle(&self, original: &str, reservation: u64, detail: &mut Detail) -> Option<()> {
        let vehicle = self.world.transport_vehicle(reservation);
        let segment = vehicle.as_ref().map_or(original, |vehicle| vehicle.segment_id);
        let edge = self.edge(segment)?;
        if !self.segment_readable(edge) {
            detail.title = self.say("交通载具", "Transport vehicle").into();
            detail.line(self.say("人物尚不能阅读载具所在线路的记录。",
                "The character cannot read the vehicle's corridor record."));
            return Some(());
        }
        detail.title = vehicle.as_ref().map_or_else(|| self.say("运输预约", "Transport reservation"), |vehicle|
            if vehicle.freight { self.say("货运载具", "Freight vehicle") }
            else { self.say("客运载具", "Passenger vehicle") }).into();
        detail.line(format!("{} #{reservation}", self.say("运输预约", "Reservation")));
        if let Some(vehicle) = vehicle {
            if let Some(port) = vehicle.alongside_seaport {
                detail.line(format!("{} · {}", self.say("在港装卸", "Alongside for handling"), self.place(port)));
            } else {
                detail.line(format!("{} → {} · {} {:.0}%",
                    self.place(vehicle.from), self.place(vehicle.to), self.say("本段进度", "Leg progress"),
                    f64::from(vehicle.progress) * 100.));
            }
        } else {
            detail.line(self.say("当前无载具在地图运行。", "No vehicle is currently moving on the map."));
        }
        detail.link(format!("{} · {} → {}", self.say("线路", "Corridor"),
            self.place(&edge.from), self.place(&edge.to)),
            Link::Object(ObjectId::Segment(segment.into())));
        match self.mode {
            Mode::Geographic if self.world.is_player_transport_reservation(reservation) => {
                detail.link(self.say("查看本人行程", "Open my journey"), Link::CurrentTravel);
            }
            Mode::Political => {
                self.jurisdiction_line(&edge.from, detail);
                self.jurisdiction_line(&edge.to, detail);
                self.line_capacity(edge, detail);
                detail.line(self.say("签证与海关规则待接入。", "Visa and customs rules are pending."));
            }
            Mode::Economic => {
                self.line_capacity(edge, detail);
                if let Some(lot) = self.world.freight_for_reservation(reservation) {
                    detail.link(format!("{} #{}", self.say("查看货批", "Open freight lot"), lot.id),
                        Link::Freight(lot.id));
                }
            }
            Mode::Military => self.military_context([None], detail),
            _ => (),
        }
        Some(())
    }
}

fn clock_label(minute: i64) -> String {
    let mut clock = GameClock::default();
    if clock.advance_minutes(minute).is_err() { return "—".into(); }
    let date = clock.current_date();
    format!("{}-{:02}-{:02} {:02}:{:02}", date.year, date.month, date.day, date.hour, date.minute)
}

impl Display<'_> {
    pub(crate) fn transport_detail(&self, detail: &Detail, panel: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>) {
        let [x, y, width, height] = detail.rect(self.size);
        let pages = detail.page_count(self.size);
        let page = self.hud.transport_detail_page.min(pages - 1);
        let rows = detail.rows_per_page(self.size);
        let left = x + 14.;
        let content = width - 28.;
        panel.rect(x, y, width, height, [13, 24, 31, 246]);
        panel.rect(x, y, width, 1., BRASS);
        self.skin.text(text, detail.heading, 0, [left, y + 6.], content - 40., BRASS);
        self.skin.paragraph(text, &detail.title, 1, [left, y + 25., content - 34., 29.], IVORY, 0.94);
        self.row(panel, text, hits, [x + width - 43., y + 11., 29., 26.], "×",
            Some(Action::Hud(Command::CloseTransportDetail)), false);
        for (offset, (value, link)) in detail.rows.iter().skip(page * rows).take(rows).enumerate() {
            let top = y + 55. + offset as f32 * DETAIL_ROW;
            if let Some(index) = link {
                self.row(panel, text, hits, [left, top, content, 28.], value,
                    Some(Action::Hud(Command::TransportDetail(*index))), false);
            } else {
                self.skin.paragraph(text, value, 0, [left, top, content, DETAIL_ROW], MUTED, 0.82);
            }
        }
        if pages > 1 {
            let top = y + height - 32.;
            self.skin.text(text, &format!("{} / {pages}", page + 1), 0, [left + 46., top + 4.], 82., MUTED);
            for (x, label, target) in [
                (left, "<", page.checked_sub(1)),
                (left + 123., ">", (page + 1 < pages).then_some(page + 1)),
            ] {
                self.row(panel, text, hits, [x, top, 36., 26.], label,
                    target.map(|page| Action::Hud(Command::TransportDetailPage(page))), false);
            }
        }
    }
}

#[derive(Deserialize, PartialEq)]
pub struct TransportView {
    pub destinations: Vec<Destination>,
    pub destination_page: usize,
    pub destinations_next: bool,
    pub destination: String,
    pub destination_is_current: bool,
    #[serde(default)]
    pub destination_detail: String,
    pub location: String,
    pub moving: bool,
    pub residence: String,
    pub workplace: String,
    pub commute: String,
    #[serde(default)]
    pub can_plan_work_trip: bool,
    #[serde(default)]
    pub can_move_home: bool,
    #[serde(default)]
    pub can_commute: bool,
    #[serde(default)]
    pub migration: Option<String>,
    pub mode: String,
    pub active: bool,
    pub passenger_lines: Vec<String>,
    pub passenger_notice: String,
    pub travel_confirm: bool,
    pub lots: Vec<CargoRow>,
    pub lot_page: usize,
    pub lots_next: bool,
    pub freight_lines: Vec<String>,
    pub freight_notice: String,
    pub freight_actions: Vec<TransportAction>,
}

#[derive(Deserialize, PartialEq)]
pub struct Destination { pub id: String, pub label: String }

#[derive(Deserialize, PartialEq)]
pub struct CargoRow { pub id: u64, pub label: String, pub selected: bool }

#[derive(Deserialize, PartialEq)]
pub struct TransportAction { pub id: String, pub label: String }

pub const PAGE_SIZE: usize = 6;
pub const LOT_PAGE_SIZE: usize = 3;

fn command(verb: &'static str, index: usize) -> Option<Action> {
    Some(Action::Hud(Command::Transport(verb, index)))
}

impl Display<'_> {
    pub(crate) fn travel_page(&self, panels: &mut Mesh, art: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>) {
        let Some([x,y,w,h]) = self.page_rect() else { return };
        let Some(v) = self.session.and_then(|s| s.transport.as_ref()) else { return };
        self.folio(panels, art, text, hits, [x,y,w,h], "旅行与通勤");
        let left = x + 18.;
        let width = w - 36.;
        let location = if v.moving { "上一站" } else { "当前位置" };
        self.skin.text(text, &format!("{location} {} · 常住地 {}", v.location, v.residence), 0, [left,y+58.], width, IVORY);
        self.skin.text(text, &format!("工作地点 {} · {}", v.workplace, v.commute), 0, [left,y+80.], width, MUTED);
        self.destinations(panels, text, hits, [left,y+104.,width], v);
        self.skin.text(text, &v.destination_detail, 0, [left,y+185.], width, MUTED);
        let row = y + 207.;
        let actions = [
            ("查询路线", (!v.active && !v.destination.is_empty() && !v.destination_is_current).then(|| Action::Hud(Command::Transport("preview", 0)))),
            ("购票出发", v.travel_confirm.then(|| Action::Hud(Command::Transport("depart", 0)))),
            ("取消或到站下车", v.active.then(|| Action::Hud(Command::Transport("stop", 0)))),
            ("设／停通勤", v.can_commute.then(|| Action::Hud(Command::Transport("commute", 0)))),
            ("前往工作地", v.can_plan_work_trip.then(|| Action::Hud(Command::Transport("work_trip", 0)))),
            ("登记迁居", v.can_move_home.then(|| Action::Hud(Command::Transport("move_home", 0)))),
            ("工作", Some(Action::Hud(Command::Page(Page::Relations)))),
        ];
        let cell = width / 4.;
        for (i, (label, action)) in actions.into_iter().enumerate() {
            self.row(panels, text, hits, [left+(i%4) as f32*cell,row+(i/4) as f32*31.,cell-4.,28.], label, action, false);
        }
        let start = if let Some(migration) = &v.migration {
            self.skin.text(text, migration, 0, [left,row+64.], width, MUTED);
            row + 83.
        } else {
            row + 65.
        };
        self.describe_transport(text, [left,start,width], &v.passenger_lines, &v.passenger_notice, y+h-start-8.);
    }

    pub(crate) fn freight_page(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>, [x,y,w,h]: [f32;4]) {
        let Some(v) = self.session.and_then(|s| s.transport.as_ref()) else { return };
        let caption = if v.lots.is_empty() {
            "个人从报价簿采购，企业从商号采购货批。"
        } else {
            "选择货批和目的地，再查询运费。"
        };
        self.skin.text(text, caption, 0, [x,y], w, MUTED);
        for (i, lot) in v.lots.iter().enumerate() {
            self.row(panels,text,hits,[x,y+24.+i as f32*25.,w-92.,23.], &lot.label, command("lot",i), lot.selected);
        }
        for (i,label) in ["<",">"].into_iter().enumerate() {
            let enabled = if i == 0 { v.lot_page > 0 } else { v.lots_next };
            self.row(panels,text,hits,[x+w-89.+i as f32*44.,y+24.,40.,23.],label,
                enabled.then(|| Action::Hud(Command::Transport(if i == 0 {"lots_prev"} else {"lots_next"},0))),false);
        }
        self.destinations(panels, text, hits, [x,y+105.,w], v);
        self.skin.text(text, &v.destination_detail, 0, [x,y+186.], w, MUTED);
        let row = y+220.;
        let cell = w / v.freight_actions.len().max(1) as f32;
        for (index, action) in v.freight_actions.iter().enumerate() {
            let verb = match action.id.as_str() {
                "freight_quote" => "freight_quote",
                "freight_dispatch" => "freight_dispatch",
                "sale_quote" => "sale_quote",
                "sale_confirm" => "sale_confirm",
                _ => continue,
            };
            self.row(panels,text,hits,[x+index as f32*cell,row,cell-4.,26.], &action.label, command(verb,0),false);
        }
        self.describe_transport(text, [x,row+31.,w], &v.freight_lines, &v.freight_notice, h-251.);
    }

    fn describe_transport(&self, text: &mut Mesh, [x,y,w]:[f32;3], lines:&[String], notice:&str, height:f32) {
        let rows = ((height - 20.).max(20.) / 17.) as usize;
        for (i, line) in lines.iter().take(rows).enumerate() {
            self.skin.text(text, line, 0, [x,y+i as f32*17.], w, IVORY);
        }
        if !notice.is_empty() {
            self.skin.paragraph(text, notice, 0, [x,y+rows.min(lines.len()) as f32*17.,w,33.], MUTED, 1.);
        }
    }

    fn destinations(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>, [x,y,w]:[f32;3], v:&TransportView) {
        self.skin.text(text, "目的地", 0, [x,y+5.], w, MUTED);
        let mode_width = ((w - 160.) / 6.).clamp(29., 59.);
        for (i, (id, label)) in [("all","全部"),("rail","铁路"),("road","道路"),
            ("shipping","海运"),("inland","内河"),("domestic","集散")].into_iter().enumerate() {
            self.row(panels,text,hits,[x+68.+i as f32*mode_width,y,mode_width-3.,24.],label,command("mode",i),v.mode==id);
        }
        for (i, label) in ["<",">"].into_iter().enumerate() {
            let enabled = if i == 0 { v.destination_page > 0 } else { v.destinations_next };
            self.row(panels,text,hits,[x+w-83.+i as f32*42.,y,37.,24.],label,
                enabled.then(|| Action::Hud(Command::Transport(if i == 0 {"cities_prev"} else {"cities_next"},0))),false);
        }
        let width = w / 3.;
        for (i, place) in v.destinations.iter().enumerate() {
            self.row(panels,text,hits,[x+(i%3) as f32*width,y+29.+(i/3) as f32*26.,width-4.,24.],
                &place.label, command("destination",i), v.destination == place.id);
        }
    }
}
