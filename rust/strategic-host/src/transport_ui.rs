use crate::{
    formal_ui::{Command, Display, Page, IVORY, MUTED},
    overlay::Mesh,
    ui::{Action, Hit},
};
use serde::Deserialize;

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
        self.skin.text(text, "从报价簿选择商品，报价后选择采购货批。", 0, [x,y], w, MUTED);
        for (i, lot) in v.lots.iter().enumerate() {
            self.row(panels,text,hits,[x,y+24.+i as f32*25.,w-92.,23.], &lot.label, command("lot",i), lot.selected);
        }
        for (i,label) in ["<",">"].into_iter().enumerate() {
            let enabled = if i == 0 { v.lot_page > 0 } else { v.lots_next };
            self.row(panels,text,hits,[x+w-89.+i as f32*44.,y+24.,40.,23.],label,
                enabled.then(|| Action::Hud(Command::Transport(if i == 0 {"lots_prev"} else {"lots_next"},0))),false);
        }
        self.destinations(panels, text, hits, [x,y+105.,w], v);
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
