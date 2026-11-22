use super::{demography::OpeningDemography, historical::PopulationCatalogue, social::OpeningSocial, MAX_POPULATION};
use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs, io,
    path::{Component, Path, PathBuf},
    sync::OnceLock,
};

pub(crate) struct OpeningAssets {
    root: PathBuf,
    catalogue: Catalogue,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Catalogue {
    format_version: u32,
    current_version: u32,
    market_calibration_version: u32,
    versions: BTreeMap<u32, OpeningFiles>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OpeningFiles {
    opening: PathBuf,
    demography: Option<PathBuf>,
    social: Option<PathBuf>,
}

impl OpeningAssets {
    pub(crate) fn open(data_root: &Path) -> io::Result<Self> {
        let root = data_root.join("historical_population_1900");
        let path = root.join("runtime-manifest.json");
        let bytes = fs::read(&path).map_err(|error| io::Error::new(
            error.kind(), format!("historical population catalogue {}: {error}", path.display()),
        ))?;
        let catalogue: Catalogue = serde_json::from_slice(&bytes).map_err(|error| {
            invalid(format!("invalid historical population catalogue {}: {error}", path.display()))
        })?;
        if catalogue.format_version != 1
            || catalogue.versions.contains_key(&0)
            || !catalogue.versions.contains_key(&catalogue.current_version)
            || !catalogue.versions.contains_key(&catalogue.market_calibration_version)
        {
            return Err(invalid(format!("unsupported historical population catalogue {}", path.display())));
        }
        Ok(Self { root, catalogue })
    }

    pub(crate) fn current_version(&self) -> u32 {
        self.catalogue.current_version
    }

    pub(crate) fn market_calibration_version(&self) -> u32 {
        self.catalogue.market_calibration_version
    }

    pub(crate) fn versions(&self) -> impl Iterator<Item = u32> + '_ {
        self.catalogue.versions.keys().copied()
    }

    fn read(&self, version: u32, kind: &str, file: &Path) -> io::Result<Vec<u8>> {
        let mut components = file.components();
        if !matches!(components.next(), Some(Component::Normal(_))) || components.next().is_some()
            || file.extension().and_then(|ext| ext.to_str()) != Some("json")
        {
            return Err(invalid(format!("invalid historical population version {version} {kind} asset path")));
        }
        let path = self.root.join(file);
        fs::read(&path).map_err(|error| io::Error::new(error.kind(), format!(
            "historical population version {version} {kind} asset {}: {error}", path.display(),
        )))
    }
}

#[derive(Debug, Deserialize, Serialize)]
pub struct OpeningPopulationEstimate {
    pub population_value: u64,
    pub source_id: String,
    pub locator: String,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub research_unlocated_balance: Option<u64>,
    #[serde(flatten)]
    context: EstimateContext,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct EstimateContext {
    date: Option<String>,
    scope: Option<String>,
    population_lower: Option<u64>,
    population_upper: Option<u64>,
    uncertainty_kind: Option<String>,
}

pub(crate) struct HistoricalOpening {
    version: u32,
    pub(super) catalogue: PopulationCatalogue,
    pub(super) demography: OpeningDemography,
    pub(super) social: OpeningSocial,
    estimates: BTreeMap<String, OpeningPopulationEstimate>,
    pub(super) partitions: BTreeMap<String, Partition>,
    pub(super) statistical_aggregates: BTreeMap<String, StatisticalAggregate>,
    pub(super) standalone: BTreeMap<String, u64>,
    collective_scopes: BTreeMap<String, String>,
    declared_places: BTreeMap<String, String>,
    places: OnceLock<BTreeMap<String, String>>,
}

pub(super) struct Partition {
    pub(super) parent: String,
    pub(super) name: String,
    pub(super) statistical_parent: Option<String>,
    coextensive_place: bool,
}

pub(super) struct StatisticalAggregate {
    pub(super) parent: String,
    pub(super) name: String,
    pub(super) members: Vec<String>,
}

#[derive(Deserialize)]
struct Manifest {
    version: u32,
    groups: Vec<Group>,
}

#[derive(Deserialize)]
struct Group {
    unit_id: String,
    population_value: u64,
    source_id: String,
    locator: String,
    method: String,
    #[serde(flatten)]
    context: EstimateContext,
    units: Vec<Unit>,
    #[serde(default)]
    statistical_aggregates: Vec<AggregateInput>,
    legacy_unlocated_balance: Option<u64>,
    research_unlocated_balance: Option<u64>,
    collective_scope: Option<CollectiveScope>,
}

#[derive(Deserialize)]
struct CollectiveScope {
    name: String,
    polity_ids: Vec<String>,
}

#[derive(Deserialize)]
struct AggregateInput {
    unit_id: String,
    name: String,
    #[serde(flatten)]
    estimate: OpeningPopulationEstimate,
}

#[derive(Deserialize)]
struct Unit {
    unit_id: String,
    name: String,
    population_value: u64,
    source_id: Option<String>,
    locator: Option<String>,
    method: Option<String>,
    #[serde(flatten)]
    context: EstimateContext,
    #[serde(default)]
    place_ids: Vec<String>,
    #[serde(default)]
    coextensive_place: bool,
    statistical_parent: Option<String>,
}

impl HistoricalOpening {
    pub(crate) fn load<'a>(
        assets: &OpeningAssets,
        version: u32,
        legacy: &BTreeMap<String, u64>,
        known_polity: impl Fn(&str) -> bool,
        market_at: impl Fn(&str) -> Option<&'a str>,
    ) -> io::Result<Self> {
        let files = assets.catalogue.versions.get(&version).ok_or_else(|| io::Error::new(
            io::ErrorKind::NotFound,
            format!("historical population version {version} is absent from {}", assets.root.display()),
        ))?;
        let bytes = assets.read(version, "opening", &files.opening)?;
        let manifest: Manifest = serde_json::from_slice(&bytes)?;
        if manifest.version != version || manifest.groups.is_empty() {
            return Err(invalid("unsupported historical population opening"));
        }
        let mut opening = Self {
            version, demography: OpeningDemography::default(), social: OpeningSocial::default(),
            catalogue: PopulationCatalogue::new(assets.root.clone()),
            estimates: BTreeMap::new(), partitions: BTreeMap::new(), statistical_aggregates: BTreeMap::new(),
            standalone: BTreeMap::new(),
            collective_scopes: BTreeMap::new(), declared_places: BTreeMap::new(), places: OnceLock::new(),
        };
        let mut occupied_scopes: BTreeSet<String> = manifest.groups.iter().map(|group| group.unit_id.clone()).collect();
        occupied_scopes.extend(legacy.keys().cloned());
        for group in manifest.groups {
            let root = group.unit_id;
            if let Some(scope) = group.collective_scope {
                if !root.starts_with("statistical_area:") || known_polity(&root) || legacy.contains_key(&root)
                    || scope.name.trim().is_empty() || scope.polity_ids.len() < 2 || !group.units.is_empty()
                    || scope.polity_ids.iter().any(|id| !known_polity(id) || !occupied_scopes.insert(id.clone()))
                {
                    return Err(invalid(format!("invalid collective historical population group {root}")));
                }
                opening.collective_scopes.insert(root.clone(), scope.name);
            }
            if (!legacy.contains_key(&root) && !known_polity(&root) && !opening.collective_scopes.contains_key(&root))
                || group.population_value == 0 || group.population_value > MAX_POPULATION
                || [&group.source_id, &group.locator, &group.method].iter().any(|text| text.trim().is_empty())
            {
                return Err(invalid(format!("invalid historical population group {root}")));
            }
            if !legacy.contains_key(&root) {
                opening.standalone.insert(root.clone(), group.population_value);
            }
            let mut remaining = group.population_value;
            let partitioned = !group.units.is_empty();
            let mut aggregate_members = BTreeMap::<String, Vec<String>>::new();
            for leaf in group.units {
                let id = leaf.unit_id;
                if id.trim().is_empty() || leaf.name.trim().is_empty() || known_polity(&id)
                    || !occupied_scopes.insert(id.clone()) || leaf.population_value == 0
                    || leaf.coextensive_place && leaf.place_ids.len() != 1
                {
                    return Err(invalid(format!("invalid historical population partition {id}")));
                }
                remaining = remaining.checked_sub(leaf.population_value)
                    .ok_or_else(|| invalid(format!("historical population partitions exceed {root}")))?;
                for place in leaf.place_ids {
                    if market_at(&place) != Some(root.as_str())
                        || opening.declared_places.insert(place.clone(), id.clone()).is_some()
                    {
                        return Err(invalid(format!("invalid or repeated historical residence binding {place} in {id}")));
                    }
                }
                opening.estimates.insert(id.clone(), OpeningPopulationEstimate {
                    population_value: leaf.population_value, source_id: leaf.source_id.unwrap_or_else(|| group.source_id.clone()),
                    locator: leaf.locator.unwrap_or_else(|| group.locator.clone()),
                    method: leaf.method.unwrap_or_else(|| group.method.clone()),
                    research_unlocated_balance: None,
                    context: EstimateContext {
                        date: leaf.context.date.or_else(|| group.context.date.clone()),
                        scope: leaf.context.scope,
                        population_lower: leaf.context.population_lower,
                        population_upper: leaf.context.population_upper,
                        uncertainty_kind: leaf.context.uncertainty_kind.or_else(|| {
                            if group.legacy_unlocated_balance.is_none() { group.context.uncertainty_kind.clone() } else { None }
                        }),
                    },
                });
                if let Some(parent) = &leaf.statistical_parent {
                    aggregate_members.entry(parent.clone()).or_default().push(id.clone());
                }
                opening.partitions.insert(id, Partition {
                    parent: root.clone(), name: leaf.name, statistical_parent: leaf.statistical_parent,
                    coextensive_place: leaf.coextensive_place,
                });
            }
            for aggregate in group.statistical_aggregates {
                let id = aggregate.unit_id;
                let estimate = aggregate.estimate;
                let members = aggregate_members.remove(&id)
                    .ok_or_else(|| invalid(format!("no members for statistical population scope {id}")))?;
                if id.trim().is_empty() || aggregate.name.trim().is_empty() || known_polity(&id)
                    || !occupied_scopes.insert(id.clone()) || estimate.research_unlocated_balance.is_some()
                    || [&estimate.source_id, &estimate.locator, &estimate.method].iter().any(|text| text.trim().is_empty())
                    || estimate.population_value != members.iter().map(|member| opening.estimates[member].population_value).sum::<u64>()
                {
                    return Err(invalid(format!("invalid statistical population scope {id}")));
                }
                opening.estimates.insert(id.clone(), estimate);
                opening.statistical_aggregates.insert(id, StatisticalAggregate {
                    parent: root.clone(), name: aggregate.name, members,
                });
            }
            if !aggregate_members.is_empty() {
                return Err(invalid(format!("missing statistical population scopes in {root}")));
            }
            if let Some(residual) = group.legacy_unlocated_balance {
                if !partitioned || remaining != residual || legacy.get(&root) != Some(&group.population_value)
                    || group.research_unlocated_balance.is_some() {
                    return Err(invalid(format!("unlocated balance differs from the legacy control for {root}")));
                }
                // The verified leaves already debit this pool. Its control retains its
                // original provenance and must not be exposed as a historical observation.
                continue;
            }
            if partitioned && remaining != group.research_unlocated_balance.unwrap_or(0)
                || !partitioned && group.research_unlocated_balance.is_some() {
                return Err(invalid(format!("historical population partitions do not sum to {root}")));
            }
            if opening.estimates.insert(root.clone(), OpeningPopulationEstimate {
                population_value: group.population_value, source_id: group.source_id,
                locator: group.locator, method: group.method, context: group.context,
                research_unlocated_balance: group.research_unlocated_balance,
            }).is_some() {
                return Err(invalid(format!("repeated historical population group {root}")));
            }
        }
        let totals = opening.totals(legacy);
        if totals.values().chain(opening.standalone.values()).try_fold(0u64, |sum, &value| {
            sum.checked_add(value).filter(|&sum| sum <= MAX_POPULATION)
        }).is_none() {
            return Err(invalid("historical opening exceeds the supported population"));
        }
        if let Some(file) = &files.demography {
            let bytes = assets.read(version, "demography", file)?;
            opening.demography = OpeningDemography::load(&opening, &bytes)?;
        }
        if let Some(file) = &files.social {
            let bytes = assets.read(version, "social", file)?;
            opening.social = OpeningSocial::load(&opening, &bytes)?;
        }
        Ok(opening)
    }

    pub(crate) fn partition_identities(&self) -> impl Iterator<Item = (&str, &str, &str)> {
        self.partitions.iter().map(|(id, part)| (id.as_str(), part.parent.as_str(), part.name.as_str()))
    }
    pub(crate) fn statistical_scopes(&self) -> impl Iterator<Item = (&str, &str, &str, &[String])> {
        self.statistical_aggregates.iter().map(|(id, scope)|
            (id.as_str(), scope.parent.as_str(), scope.name.as_str(), scope.members.as_slice()))
    }
    pub(crate) fn residence_places(&self) -> impl Iterator<Item = (&str, &str)> {
        self.declared_places.iter().map(|(place, id)| (place.as_str(), id.as_str()))
    }
    pub(crate) fn standalone_ids(&self) -> impl Iterator<Item = &str> {
        self.standalone.keys().map(String::as_str)
    }

    pub(crate) fn collective_scope_name(&self, unit: &str) -> Option<&str> {
        self.collective_scopes.get(unit).map(String::as_str)
    }

    pub(crate) fn version(&self) -> u32 { self.version }

    pub(super) fn estimate(&self, unit: &str) -> Option<&OpeningPopulationEstimate> {
        self.estimates.get(unit)
    }

    pub(crate) fn bind_operating_places(&self, sites: &BTreeMap<String, String>) {
        self.places.get_or_init(|| {
            let mut places = self.declared_places.clone();
            places.extend(sites.iter().filter(|(_,unit)| self.partitions.contains_key(unit.as_str()))
                .map(|(place,unit)|(place.clone(),unit.clone())));
            places
        });
    }

    pub(crate) fn unit_at(&self, place: &str) -> Option<&str> {
        self.places.get().unwrap_or(&self.declared_places).get(place).map(String::as_str)
    }

    pub(super) fn coextensive_unit_at(&self, place: &str) -> Option<&str> {
        let unit = self.declared_places.get(place)?;
        self.partitions[unit].coextensive_place.then_some(unit.as_str())
    }

    pub(crate) fn totals(&self, legacy: &BTreeMap<String, u64>) -> BTreeMap<String, u64> {
        legacy.iter().map(|(unit, &legacy_total)| {
            (unit.clone(), self.estimate(unit).map_or(legacy_total, |row| row.population_value))
        }).collect()
    }
}
