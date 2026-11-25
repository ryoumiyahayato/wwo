use crate::{formal_ui::MapSymbol, overlay::Mesh, ui::Mode, world::Place};

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Facility { Industrial, Mining, Government, MilitaryBase, Aviation }

impl Facility {
    pub fn for_place(place: &Place) -> Option<Self> {
        place.facility.or(match place.symbol.as_str() {
            "industrial" | "industrial_facility" => Some(Self::Industrial),
            "mining" | "mine" => Some(Self::Mining),
            "government" | "government_building" => Some(Self::Government),
            "military_base" => Some(Self::MilitaryBase),
            "aviation" | "airfield" => Some(Self::Aviation),
            _ => None,
        })
    }

    pub fn mode(self) -> Mode {
        match self {
            Self::Industrial | Self::Mining => Mode::Economic,
            Self::Government => Mode::Political,
            Self::MilitaryBase => Mode::Military,
            Self::Aviation => Mode::Geographic,
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
        MapSymbol{screen_px:21.,priority,region_max_mpp,world:false,world_max_mpp:0.}
    }

    pub fn draw(self, mesh: &mut Mesh, [x,y,px,_]: [f32;4], selectable:bool) {
        let scale=px/32.;
        let project=|[a,b]:[f32;2]|[x+a*scale,y+b*scale];
        let outline=[[16.,2.],[29.,9.5],[29.,22.5],[16.,30.],[3.,22.5],[3.,9.5]];
        let border=[177,142,86,if selectable {255}else{158}];
        let foreground=[240,208,149,border[3]];
        mesh.shape(&outline.map(project),[23,32,39,border[3]]);
        for (a,b) in outline.iter().zip(outline.iter().cycle().skip(1)) {
            mesh.line(project(*a),project(*b),1.30*scale,border);
        }
        let lines:&[&[[f32;2]]] = match self {
            Self::Industrial=>&[&[[8.,23.],[8.,15.],[13.,18.],[13.,13.],[18.,17.],[18.,10.],[22.,10.],[23.,23.],[8.,23.]],
                &[[11.,21.],[13.,21.]],&[[16.,21.],[18.,21.]],&[[21.,21.],[22.,21.]]],
            Self::Mining=>&[&[[9.,23.],[21.,11.]],&[[12.,11.],[9.,15.]],&[[9.,11.],[13.,10.4],[17.,11.2],[23.,15.]],
                &[[13.,18.],[20.,24.],[23.,21.]]],
            Self::Government=>&[&[[7.,13.],[16.,8.],[25.,13.],[7.,13.]],&[[8.,23.],[24.,23.]],&[[11.,15.],[11.,21.]],&[[16.,15.],[16.,21.]],&[[21.,15.],[21.,21.]]],
            Self::MilitaryBase=>&[&[[10.,11.],[22.,11.],[22.,18.],[16.,23.],[10.,18.],[10.,11.]],&[[13.,16.],[19.,16.]],&[[16.,13.],[16.,19.]]],
            Self::Aviation=>&[&[[16.,8.],[16.,23.]],&[[8.,17.],[16.,13.],[24.,17.]],&[[13.,22.],[16.,20.],[19.,22.]]],
        };
        for line in lines {
            for segment in line.windows(2) {
                mesh.line(project(segment[0]),project(segment[1]),1.65*scale,foreground);
            }
        }
    }
}

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum PlaceFilter { #[default] Settlements, Heritage, Infrastructure, Military }

impl PlaceFilter {
    pub fn visible(self, place: &Place, kind: &str, facility: Option<Facility>) -> bool {
        match self {
            Self::Settlements => matches!(kind,"capital"|"admin_primary"|"admin_secondary"|"city"|"town"|"village")
                || facility==Some(Facility::Government),
            Self::Heritage => matches!(kind,"historic_site"|"castle"|"fort"|"monument"|"religious"|"eiffel"|"clock_tower"|"pyramids"),
            Self::Infrastructure => matches!(kind,"station"|"bridge"|"port")
                || matches!(facility,Some(Facility::Industrial|Facility::Mining|Facility::Aviation)),
            Self::Military => place.military_facility_active,
        }
    }
}

pub fn symbol(kind: &str) -> &str {
    match kind {
        "religious_temple" | "religious_dome" => "religious",
        kind => kind,
    }
}
