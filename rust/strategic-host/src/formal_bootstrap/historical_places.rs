use super::{local_id, read_list, AuthorityKind, Place, Polity, RegimentalOpeningStation, Route, RouteMode, WorldSources, START_DATE};
use crate::formal_save::invalid;
use serde::Deserialize;
use std::{collections::{BTreeMap, BTreeSet}, io};

impl WorldSources {
    pub fn polities(&self) -> &BTreeMap<String, Polity> {
        &self.polities
    }

    pub fn authority(&self, subject: &str) -> Option<(&Polity, AuthorityKind)> {
        let subject = self.polities.get(subject)?;
        let controller = self.polities.get(&subject.controller_id)?;
        let kind = match subject.relationship.as_str() {
            "administered_territory" => AuthorityKind::Administration,
            "military_occupation" => AuthorityKind::Occupation,
            "protected_state" | "protected_territory" => AuthorityKind::Protection,
            _ => AuthorityKind::LegacyController,
        };
        Some((controller, kind))
    }

    pub fn places(&self) -> &BTreeMap<String, Place> {
        &self.places
    }

    pub fn place_polity(&self, place: &str) -> Option<&Polity> {
        self.polities.get(historical_place_polity(self.places.get(place)?))
    }

    pub fn routes(&self) -> &BTreeMap<String, Route> {
        &self.routes
    }

    pub fn population_unit_at(&self, place_id: &str) -> Option<&str> {
        self.place_population_units.get(place_id).map(String::as_str)
    }

    pub fn polity_population_bindings(&self) -> &BTreeMap<String, String> {
        &self.polity_population_bindings
    }

    pub fn population_units(&self) -> impl Iterator<Item = &str> {
        self.population_income.keys().map(String::as_str)
    }

    pub(super) fn opening_parent_at(&self, place_id: &str) -> Option<&str> {
        let place = self.places.get(place_id)?;
        self.population_unit_at(place_id).or_else(|| match (place.id.as_str(), place.parent_country_id.as_str()) {
            ("dover" | "port_london", "british_empire") => Some("british_isles_1900"),
            ("vienna", "austro_hungarian_empire") => Some("austria_hungary"),
            (_, "united_states") => Some("united_states_1900"),
            (_, id) => self.polities.contains_key(id).then_some(id),
        })
    }

    pub(super) fn dated_place_jurisdiction(&self, place_id: &str) -> Option<&str> {
        self.dated_place_jurisdictions.get(place_id).map(String::as_str)
    }
}

pub(super) fn load_polities() -> io::Result<BTreeMap<String, Polity>> {
    #[derive(Deserialize)]
    struct Evidence {
        schema_version: u32,
        unit_count: usize,
        units: Vec<Polity>,
    }
    let source: Evidence = serde_json::from_slice(include_bytes!(
        "../../../../data/world_map/historical/political_units_1900.json"
    ))?;
    if source.schema_version != 1 || source.unit_count != source.units.len() {
        return Err(invalid("invalid historical political evidence header"));
    }
    let mut ids = BTreeSet::new();
    let mut polities = BTreeMap::new();
    for polity in source.units {
        if !local_id(&polity.id) || !ids.insert(polity.id.clone())
            || !date(&polity.valid_from) || !date(&polity.valid_to) || polity.valid_from > polity.valid_to
        {
            return Err(invalid(format!("invalid historical political identity {}", polity.id)));
        }
        if polity.valid_from.as_str() <= START_DATE && START_DATE <= polity.valid_to.as_str() {
            polities.insert(polity.id.clone(), polity);
        }
    }
    if polities.is_empty() || polities.values().any(|p| {
        !p.controller_id.is_empty() && !polities.contains_key(&p.controller_id)
    }) {
        return Err(invalid("missing historical authority at the formal opening date"));
    }
    Ok(polities)
}

pub(super) fn historical_place_polity(place: &Place) -> &str {
    match (place.id.as_str(), place.parent_country_id.as_str()) {
        ("kolkata", "british_empire") => "cshapes_gw_750",
        ("alexandria" | "port_alexandria", "ottoman_empire") => "khedivate_of_egypt",
        (_, "british_empire") => "british_isles_1900",
        (_, "japanese_empire") => "empire_of_japan",
        (_, "united_states") => "united_states_1900",
        (_, "argentine_republic") => "argentina_1900",
        (_, "country_bel") => "kingdom_of_belgium",
        (_, "austro_hungarian_empire") => "austria_hungary",
        (_, parent) => parent,
    }
}

type PopulationBindings = BTreeMap<String, String>;

pub(super) fn load_population_bindings(
    polities: &BTreeMap<String, Polity>,
    populations: &BTreeMap<String, u64>,
) -> io::Result<(PopulationBindings, PopulationBindings)> {
    #[derive(Deserialize)]
    struct Crosswalk {
        schema_id: String,
        records: Vec<Binding>,
    }
    #[derive(Deserialize)]
    struct Binding {
        economy_entity_id: String,
        polity_ids: Vec<String>,
        mapping_mode: String,
    }
    let crosswalk: Crosswalk = serde_json::from_slice(include_bytes!(
        "../../../../data/world_map/historical/major_economy_polity_crosswalk_1900.json"
    ))?;
    if crosswalk.schema_id != "major_economy_polity_crosswalk_1900_v1" {
        return Err(invalid("invalid historical population crosswalk"));
    }
    let mut result: BTreeMap<_, _> = populations.keys()
        .filter(|unit| polities.contains_key(*unit))
        .map(|unit| (unit.clone(), unit.clone()))
        .collect();
    let mut name_aliases = BTreeMap::new();
    for binding in crosswalk.records {
        if !populations.contains_key(&binding.economy_entity_id) {
            return Err(invalid("population crosswalk references an unknown statistical unit"));
        }
        let exact_alias = binding.mapping_mode == "historical_name_alias";
        if exact_alias && binding.polity_ids.len() != 1 {
            return Err(invalid("population name alias must reference one historical polity"));
        }
        for polity in binding.polity_ids {
            if !polities.contains_key(&polity) {
                return Err(invalid(format!("population crosswalk references inactive polity {polity}")));
            }
            if let Some(old) = result.insert(polity.clone(), binding.economy_entity_id.clone()) {
                if old != binding.economy_entity_id {
                    return Err(invalid(format!("ambiguous population crosswalk for {polity}")));
                }
            }
            if exact_alias {
                name_aliases.insert(polity, binding.economy_entity_id.clone());
            }
        }
    }
    if populations.keys().any(|unit| !result.values().any(|bound| bound == unit)) {
        return Err(invalid("formal statistical unit has no political binding"));
    }
    Ok((result, name_aliases))
}

pub(super) fn load_map() -> io::Result<(BTreeMap<String, Place>, BTreeMap<String, Route>, BTreeSet<String>)> {
    #[derive(Deserialize)]
    struct Country { id: String }
    #[derive(Deserialize)]
    struct Port {
        #[serde(flatten)]
        place: Place,
        city_id: String,
    }
    let countries = read_list::<Country>(include_bytes!("../../../../data/world_map/countries.json"), "countries")?;
    let countries: BTreeSet<_> = countries.into_iter().map(|country| country.id).collect();
    let regions = read_list::<Place>(include_bytes!("../../../../data/world_map/regions.json"), "regions")?;
    let cities = read_list::<Place>(include_bytes!("../../../../data/world_map/cities.json"), "cities")?;
    let ports = read_list::<Port>(include_bytes!("../../../../data/world_map/ports.json"), "ports")?;
    let region_ids: BTreeSet<_> = regions.iter().map(|place| place.id.clone()).collect();
    let city_ids: BTreeSet<_> = cities.iter().map(|place| place.id.as_str()).collect();
    let port_ids: BTreeSet<_> = ports.iter().map(|port| port.place.id.as_str()).collect();
    if ports.iter().any(|port| !city_ids.contains(port.city_id.as_str())) {
        return Err(invalid("formal port references an unknown city"));
    }
    let mut routes = BTreeMap::new();
    for (mode, bytes, list, endpoints) in [
        (RouteMode::Road, &include_bytes!("../../../../data/world_map/road_segments.json")[..], "segments", &city_ids),
        (RouteMode::Rail, &include_bytes!("../../../../data/world_map/rail_segments.json")[..], "segments", &city_ids),
        (RouteMode::Shipping, &include_bytes!("../../../../data/world_map/shipping_routes.json")[..], "routes", &port_ids),
    ] {
        load_routes(&mut routes, mode, bytes, list, endpoints)?;
    }
    let city_keys = city_ids.into_iter().map(str::to_owned).collect();
    let mut places = BTreeMap::new();
    for place in regions.into_iter().chain(cities).chain(ports.into_iter().map(|port| port.place)) {
        if !local_id(&place.id) || !countries.contains(&place.parent_country_id)
            || (!place.parent_region_id.is_empty() && !region_ids.contains(place.parent_region_id.as_str()))
            || place.lon_lat.is_some_and(|[lon, lat]| !(-180.0..=180.0).contains(&lon) || !(-90.0..=90.0).contains(&lat))
        {
            return Err(invalid(format!("invalid formal place {}", place.id)));
        }
        let id = format!("place:{}", place.id);
        if places.insert(id.clone(), place).is_some() {
            return Err(invalid(format!("duplicate formal place {id}")));
        }
    }
    Ok((places, routes, city_keys))
}

pub(super) fn load_regimental_opening_stations(
    places: &BTreeMap<String, Place>,
    polities: &BTreeMap<String, Polity>,
) -> io::Result<BTreeMap<String, Vec<RegimentalOpeningStation>>> {
    let stations = read_list::<RegimentalOpeningStation>(
        include_bytes!("../../../../data/formal/regimental_opening_stations_1900.json"), "stations",
    )?;
    let mut regiments = BTreeSet::new();
    let mut by_place: BTreeMap<String, Vec<_>> = BTreeMap::new();
    for station in stations {
        if !local_id(&station.regiment_id) || !regiments.insert(station.regiment_id.clone())
            || !places.contains_key(&station.place_id) || !polities.contains_key(&station.polity_id)
            || station.name.trim().is_empty() || station.name_zh.trim().is_empty()
            || station.source.trim().is_empty() || !station.source_url.starts_with("https://")
        {
            return Err(invalid(format!("invalid regimental opening station {}", station.regiment_id)));
        }
        by_place.entry(station.place_id.clone()).or_default().push(station);
    }
    Ok(by_place)
}

fn load_routes(
    routes: &mut BTreeMap<String, Route>,
    mode: RouteMode,
    bytes: &[u8],
    list: &str,
    endpoints: &BTreeSet<&str>,
) -> io::Result<()> {
    #[derive(Deserialize)]
    struct Link {
        id: String,
        #[serde(rename = "type")]
        kind: String,
        #[serde(alias = "from_city_id", alias = "from_port_id")]
        from: String,
        #[serde(alias = "to_city_id", alias = "to_port_id")]
        to: String,
    }
    let kind = match mode {
        RouteMode::Road => "road",
        RouteMode::Rail => "rail",
        RouteMode::Shipping => "shipping",
    };
    for link in read_list::<Link>(bytes, list)? {
        if !local_id(&link.id) || link.kind != kind || link.from == link.to
            || !endpoints.contains(link.from.as_str()) || !endpoints.contains(link.to.as_str())
            || routes.contains_key(&link.id)
        {
            return Err(invalid(format!("invalid formal route {}", link.id)));
        }
        routes.insert(link.id.clone(), Route {
            id: link.id,
            mode,
            from_place_id: format!("place:{}", link.from),
            to_place_id: format!("place:{}", link.to),
        });
    }
    Ok(())
}

fn date(value: &str) -> bool {
    let mut parts = value.split('-');
    let year = parts.next().filter(|s| s.len() == 4).and_then(|s| s.parse::<i32>().ok());
    let month = parts.next().filter(|s| s.len() == 2).and_then(|s| s.parse::<u32>().ok());
    let day = parts.next().filter(|s| s.len() == 2).and_then(|s| s.parse::<u32>().ok());
    matches!((year, month, day, parts.next()), (Some(y), Some(m), Some(d), None)
        if y > 0 && (1..=crate::calendar::month_length(y, m)).contains(&d))
}
