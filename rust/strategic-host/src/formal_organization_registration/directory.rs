use super::*;
use crate::formal_ledger::MAX_AMOUNT;

pub(crate) struct OrganizationDirectory {
    pub(super) rows: BTreeMap<String, Organization>,
    opening_ids: BTreeSet<String>,
    candidates: BTreeMap<String, Vec<String>>,
}

#[derive(Deserialize)]
struct Templates {
    basis: String,
    job_terms: RegionalJobTerms,
    industries: Vec<Industry>,
    local_preferences: BTreeMap<String, Preference>,
    paris_firm_names: BTreeMap<String, FirmName>,
}

#[derive(Deserialize)]
struct Industry { id: String, name: String, goods: Vec<String> }

#[derive(Default, Deserialize)]
struct Preference {
    industry: Option<String>,
    founder: Option<String>,
    coordinator: Option<String>,
    member: Option<String>,
}

#[derive(Deserialize)]
struct FirmName { name: String, founder: String }

#[derive(Deserialize)]
struct ParisOpening { firms: Vec<LocalFirm>, jobs: Vec<LocalJob> }

#[derive(Deserialize)]
struct LocalFirm {
    id: String,
    account_id: String,
    host_organization_id: String,
    sites: Vec<LocalSite>,
}

#[derive(Deserialize)]
struct LocalSite { id: String, place_id: String, prices: BTreeMap<String, i64> }

#[derive(Deserialize)]
struct LocalJob { id: String, employer: String, place: String, site_id: String }

impl OrganizationDirectory {
    pub(crate) fn load(world: &WorldSources, cities: &BTreeSet<String>, populations: &BTreeMap<String, u64>, markets: &MarketInputs) -> io::Result<Self> {
        let templates: Templates = serde_json::from_slice(include_bytes!("../../../../data/formal/regional_organizations_1900.json"))?;
        templates.validate()?;
        let paris: ParisOpening = serde_json::from_slice(include_bytes!("../../../../data/formal/paris_employment_opening_r1.json"))?;
        let mut directory = Self { rows: BTreeMap::new(), opening_ids: BTreeSet::new(), candidates: BTreeMap::new() };
        let mut existing = BTreeSet::new();
        for firm in &paris.firms {
            let [site] = firm.sites.as_slice() else { return Err(invalid("formal enterprise requires a registered site")); };
            let unit = world.population_unit_at(&site.place_id).ok_or_else(|| invalid("enterprise site has no population binding"))?;
            let names = templates.paris_firm_names.get(&firm.id).ok_or_else(|| invalid("missing native firm's public identity"))?;
            let firm_key = firm.id.strip_prefix("firm:").ok_or_else(|| invalid("invalid native opening firm"))?;
            let jobs: Vec<_> = paris.jobs.iter().filter(|job| job.employer == firm.id && job.site_id == site.id && job.place == site.place_id)
                .map(|job| job.id.clone()).collect();
            if jobs.is_empty() { return Err(invalid("enterprise site has no registered job")); }
            directory.insert(Organization {
                id: firm.host_organization_id.clone(), name: names.name.clone(), place: site.place_id.clone(), unit: unit.into(),
                kind: OrganizationKind::Enterprise, basis: "巴黎正式开局的模拟企业",
                firm: Some(firm.id.clone()), site: Some(site.id.clone()), account: Some(firm.account_id.clone()),
                goods: site.prices.keys().cloned().collect(), jobs, terms: None, opening_member: None,
                officer: Officer { person: format!("person:{firm_key}_manager"), name: names.founder.clone(), role: OrganizationRole::Manager },
            })?;
            existing.insert(site.place_id.as_str());
        }
        let opening_places: BTreeSet<_> = OPENINGS.iter().map(|(_, city)| format!("place:{city}")).collect();
        for city in cities {
            let place = format!("place:{city}");
            let Some(city_row) = world.places().get(&place) else { continue };
            let Some(unit) = world.opening_parent_at(&place) else { continue };
            let population = populations.get(unit).copied().unwrap_or_default();
            if population == 0 { continue; }
            let preference = templates.local_preferences.get(city);
            if !existing.contains(place.as_str()) {
                if let Some((industry, goods)) = templates.choose_industry(preference, markets, unit, population) {
                    let key = format!("opening_{city}_merchant");
                    directory.insert(Organization {
                        id: format!("organization:{key}"), name: format!("{}{}", city_row.name, industry.name),
                        place: place.clone(), unit: unit.into(), kind: OrganizationKind::Enterprise,
                        basis: "依据正式市场与当地人口设立的模拟商号", firm: Some(format!("firm:{key}")),
                        site: Some(format!("site:{key}:{city}")), account: Some(format!("account:{key}")), goods,
                        jobs: vec![format!("job:{key}")], terms: Some(templates.job_terms), opening_member: None,
                        officer: Officer {
                            person: format!("person:{key}_manager"),
                            name: preference.and_then(|p| p.founder.clone()).unwrap_or_else(|| format!("{}商号创办人", city_row.name)),
                            role: OrganizationRole::Owner,
                        },
                    })?;
                }
            }
            let key = format!("opening_{city}_association");
            let has_employer = directory.rows.values().any(|org| org.place == place && org.kind == OrganizationKind::Enterprise);
            if !has_employer && !opening_places.contains(&place) { continue; }
            directory.insert(Organization {
                id: format!("organization:{key}"), name: format!("{}居民互助会", city_row.name),
                place, unit: unit.into(), kind: OrganizationKind::MutualAid, basis: "依据正式居民与城市设立的模拟互助会",
                firm: None, site: None, account: None, goods: Vec::new(), jobs: Vec::new(), terms: None,
                opening_member: has_employer.then(|| Officer {
                    person: format!("person:{key}_jobseeker"),
                    name: preference.and_then(|p| p.member.clone()).unwrap_or_else(|| format!("{}互助会会员", city_row.name)),
                    role: OrganizationRole::Member,
                }),
                officer: Officer {
                    person: format!("person:{key}_coordinator"),
                    name: preference.and_then(|p| p.coordinator.clone()).unwrap_or_else(|| format!("{}互助会联络员", city_row.name)),
                    role: OrganizationRole::Coordinator,
                },
            })?;
        }
        for org in directory.rows.values() {
            if opening_places.contains(&org.place) {
                directory.opening_ids.insert(org.id.clone());
            } else {
                directory.candidates.entry(org.place.clone()).or_default().push(org.id.clone());
            }
        }
        Ok(directory)
    }

    pub(crate) fn opening(&self) -> impl Iterator<Item = &Organization> {
        self.opening_ids.iter().map(|id| &self.rows[id])
    }

    pub(super) fn at(&self, place: &str) -> impl Iterator<Item = &Organization> {
        self.candidates.get(place).into_iter().flatten().map(|id| &self.rows[id])
    }

    pub(super) fn is_opening(&self, id: &str) -> bool {
        self.opening_ids.contains(id)
    }

    fn insert(&mut self, org: Organization) -> io::Result<()> {
        if self.rows.insert(org.id.clone(), org).is_some() { return Err(invalid("duplicate formal organization")); }
        Ok(())
    }
}

impl Templates {
    fn validate(&self) -> io::Result<()> {
        let terms = self.job_terms;
        let mut ids = BTreeSet::new();
        if self.basis != "GENERATED_OPENING_CONFIGURATION" || terms.positions == 0 || !(1..=24).contains(&terms.hours)
            || !(1..=MAX_AMOUNT / terms.hours).contains(&terms.wage_per_hour) || !(0..=365).contains(&terms.wage_delay)
            || self.industries.is_empty() || self.industries.iter().any(|industry| {
                industry.id.is_empty() || !ids.insert(&industry.id) || industry.name.is_empty() || industry.goods.is_empty()
                    || industry.goods.iter().collect::<BTreeSet<_>>().len() != industry.goods.len()
            })
        { return Err(invalid("invalid formal organization or employment template")); }
        Ok(())
    }

    fn choose_industry<'a>(&'a self, preference: Option<&Preference>, markets: &MarketInputs, unit: &str, population: u64)
        -> Option<(&'a Industry, Vec<String>)> {
        let preferred = preference.and_then(|p| p.industry.as_deref());
        self.industries.iter().filter_map(|industry| {
            let mut demand = 0.0;
            let goods: Vec<_> = industry.goods.iter().filter_map(|good| {
                let value = markets.opening_demand_value(unit, good, population)?;
                if !value.is_finite() || value <= 0.0 { return None; }
                demand += value;
                Some(good.clone())
            }).collect();
            (!goods.is_empty()).then_some((industry, goods, demand))
        }).max_by(|(a, _, a_value), (b, _, b_value)| {
            (Some(a.id.as_str()) == preferred).cmp(&(Some(b.id.as_str()) == preferred))
                .then_with(|| a_value.total_cmp(b_value)).then_with(|| b.id.cmp(&a.id))
        }).map(|(industry, goods, _)| (industry, goods))
    }
}
