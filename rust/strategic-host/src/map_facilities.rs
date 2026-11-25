use crate::{formal_ui::MapSymbol, map_markers, overlay::Mesh, ui::{active, Mode}, world::Place};

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Facility { Industrial, Mining, Government, MilitaryBase, Aviation }

impl Facility {
    pub fn at(place: &Place, date: &str) -> Option<Self> {
        let facility = place.facility.or(match place.symbol.as_str() {
            "industrial" | "industrial_facility" => Some(Self::Industrial),
            "mining" | "mine" => Some(Self::Mining),
            "government" | "government_building" => Some(Self::Government),
            "military_base" => Some(Self::MilitaryBase),
            "aviation" | "airfield" => Some(Self::Aviation),
            _ => None,
        })?;
        if !active(date, &place.from_date, &place.to_date) || place.facility_active == Some(false) {
            return None;
        }
        match facility {
            Self::MilitaryBase if !place.military_facility_active => None,
            Self::Aviation if place.from_date.is_empty() => None,
            _ => Some(facility),
        }
    }

    pub fn mode(self) -> Mode {
        match self {
            Self::Industrial | Self::Mining | Self::Aviation => Mode::Economic,
            Self::Government => Mode::Political,
            Self::MilitaryBase => Mode::Military,
        }
    }

    pub fn symbol(self) -> MapSymbol {
        let (priority, region_max_mpp) = match self {
            Self::Industrial => (51,400.),
            Self::Mining => (54,550.),
            Self::Government => (57,350.),
            Self::MilitaryBase => (60,650.),
            Self::Aviation => (52,600.),
        };
        MapSymbol{priority,region_max_mpp,world:false,world_max_mpp:0.}
    }

    pub fn draw(self, mesh: &mut Mesh, [x,y,px,_]: [f32;4], selectable:bool) {
        let name = match self {
            Self::Industrial => "industrial",
            Self::Mining => "mining",
            Self::Government => "government",
            Self::MilitaryBase => "military_base",
            Self::Aviation => "aviation",
        };
        let mut ink = map_markers::GOLD;
        if !selectable { ink[3] = 158; }
        map_markers::glyph(mesh, name, [x + px * 0.5, y + px * 0.5], px, ink);
    }
}

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum PlaceFilter { #[default] Overview, Settlements, Heritage, Transport, Economy, Government, Military, Aviation }

impl PlaceFilter {
    pub fn visible(self, place: &Place, kind: &str, facility: Option<Facility>) -> bool {
        match self {
            Self::Overview => true,
            Self::Settlements => matches!(kind,"capital"|"admin_primary"|"admin_secondary"|"city"|"town"|"village"),
            Self::Heritage => matches!(kind,"historic_site"|"castle"|"fort"|"monument"|"religious"|"eiffel"|"clock_tower"|"pyramids"),
            Self::Transport => matches!(kind,"station"|"bridge"|"port"),
            Self::Economy => matches!(facility,Some(Facility::Industrial|Facility::Mining)),
            Self::Government => facility == Some(Facility::Government),
            Self::Military => place.military_facility_active && place.facility_active != Some(false),
            Self::Aviation => facility == Some(Facility::Aviation) && !place.military_facility_active,
        }
    }
}

pub fn symbol(kind: &str) -> &str {
    match kind {
        "religious_temple" | "religious_dome" => "religious",
        kind => kind,
    }
}
