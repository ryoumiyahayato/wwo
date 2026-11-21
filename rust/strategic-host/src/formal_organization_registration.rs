use super::{InitialWorld, MarketInputs, WorldSources, OPENINGS};
use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, io, sync::Arc};

#[path = "formal_organization_registration/directory.rs"]
mod directory;
pub(crate) use directory::OrganizationDirectory;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OrganizationKind { Enterprise, MutualAid }

impl OrganizationKind {
    pub fn label(self) -> &'static str {
        match self { Self::Enterprise => "企业", Self::MutualAid => "互助会" }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OrganizationRole { Owner, Manager, Coordinator, Employee, Member }

impl OrganizationRole {
    pub fn label(self) -> &'static str {
        match self {
            Self::Owner => "创办人", Self::Manager => "经营负责人", Self::Coordinator => "联络员",
            Self::Employee => "雇员", Self::Member => "会员",
        }
    }
}

pub struct OrganizationMember<'a> {
    pub person: &'a str,
    pub role: OrganizationRole,
}

pub struct Organization {
    pub id: String,
    pub name: String,
    pub place: String,
    pub unit: String,
    pub kind: OrganizationKind,
    pub basis: &'static str,
    pub firm: Option<String>,
    pub site: Option<String>,
    pub account: Option<String>,
    pub goods: Vec<String>,
    pub jobs: Vec<String>,
    officer: Officer,
    opening_member: Option<Officer>,
    pub(crate) terms: Option<RegionalJobTerms>,
}

struct Officer {
    person: String,
    name: String,
    role: OrganizationRole,
}

#[derive(Clone, Copy, Deserialize)]
pub(crate) struct RegionalJobTerms {
    pub positions: usize,
    pub hours: i64,
    pub wage_per_hour: i64,
    pub wage_delay: i64,
    pub skill: u64,
}

impl Organization {
    pub fn is_merchant(&self) -> bool { self.terms.is_some() }
}

/// Contracts stay in WorkState and partnership capital stays in the Ledger.
#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct OrganizationMembers {
    appointments: BTreeSet<String>,
    volunteers: BTreeMap<String, BTreeSet<String>>,
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    visited_cities: BTreeSet<String>,
}

impl OrganizationMembers {
    fn appoint(&mut self, org: &Organization, resident: &Officer) {
        if resident.role == OrganizationRole::Member {
            self.volunteers.entry(org.id.clone()).or_default().insert(resident.person.clone());
        } else {
            self.appointments.insert(org.id.clone());
        }
    }
}

impl InitialWorld {
    pub fn organizations(&self) -> impl Iterator<Item = &Organization> {
        self.organization_directory.opening().chain(self.organization_members.visited_cities.iter()
            .flat_map(|place| self.organization_directory.at(place)))
    }

    pub fn organization(&self, id: &str) -> Option<&Organization> {
        self.organization_directory.rows.get(id).filter(|org| self.organization_directory.is_opening(id)
            || self.organization_members.visited_cities.contains(&org.place))
    }

    pub(crate) fn appointed_officers(&self) -> impl Iterator<Item = &str> {
        self.organization_members.appointments.iter().filter_map(|id| {
            let person = self.organization(id)?.officer.person.as_str();
            self.population.unit_for_person(person).map(|_| person)
        })
    }

    pub(crate) fn referral_members(&self) -> impl Iterator<Item = &str> {
        self.organization_members.volunteers.values().flatten().map(String::as_str)
    }

    pub(crate) fn appointed_coordinator(&self, id: &str) -> Option<&str> {
        let org = self.organization(id)?;
        (org.officer.role == OrganizationRole::Coordinator && self.organization_members.appointments.contains(id)
        ).then_some(org.officer.person.as_str())
    }

    pub(crate) fn active_coordinator(&self, id: &str) -> Option<&str> {
        let org = self.organization(id)?;
        let person = self.appointed_coordinator(id)?;
        (self.current_place(person) == Some(&org.place) && self.eligible_for_civil_work(person)
            && self.work.booking(person).is_none()).then_some(person)
    }

    pub(crate) fn initialize_organization_members(&mut self) -> io::Result<()> {
        let directory = self.organization_directory.clone();
        self.materialize_organization_members(directory.opening())
    }

    pub(super) fn register_arrival_organizations(&mut self, place: &str) -> io::Result<()> {
        if self.organization_members.visited_cities.contains(place) { return Ok(()); }
        let directory = Arc::clone(&self.organization_directory);
        let Some(shop) = directory.at(place).find(|org| org.is_merchant()) else { return Ok(()) };
        if self.market_unit_at(place) != Some(&shop.unit) { return Ok(()); }
        let residents: Vec<_> = directory.at(place).flat_map(|org| std::iter::once(&org.officer)
            .chain(org.opening_member.as_ref()).map(move |officer| (org, officer))).collect();
        let Some(unit) = self.residence_unit_at(place) else { return Ok(()); };
        if self.population.unclassified(unit).unwrap_or(0) < residents.len() as u64
            || residents.iter().any(|(_, officer)| self.person(&officer.person).is_some()
                || self.ledger.default_account(&officer.person).is_some()) { return Ok(()); }

        // Stage the claims, character roster and job. Publishing the accounts is the last fallible operation.
        let birth_year = u16::try_from(self.clock.current_date().year - 30).map_err(io::Error::other)?;
        let mut population = self.population.clone();
        let mut identities = self.identities.clone();
        let mut people = Vec::new();
        let mut character: Option<super::CharacterOutput> = None;
        for (_, resident) in &residents {
            let id = &resident.person;
            let row = super::RuntimePerson::at(id, resident.name.clone(), place, unit, birth_year, None);
            identities.insert(id.clone(), row.identity()?);
            let prior = character.as_ref().unwrap_or(&self.character);
            character = Some(super::formal_character::register_native_person(&self.player, &identities, id, prior.day, &prior.state)
                .map_err(io::Error::other)?);
            population.materialize_person(id, unit, None, self.clock.snapshot().total_minutes)?;
            people.push((id.clone(), row));
        }
        let mut work = Arc::clone(&self.work_opening);
        Arc::make_mut(&mut work).register_regional(directory.at(place))?;
        self.ledger.open_merchant_accounts(shop.firm.as_deref().unwrap(), shop.account.as_deref().unwrap(),
            residents.iter().map(|(_, officer)| officer.person.as_str()))?;
        self.population = population;
        self.identities = identities;
        self.character = character.expect("merchant has a founder");
        self.runtime_people.extend(people);
        self.work_opening = work;
        for (org, resident) in residents { self.organization_members.appoint(org, resident); }
        self.organization_members.visited_cities.insert(place.to_owned());
        Ok(())
    }

    pub(super) fn restore_organization_jobs(&mut self, members: &OrganizationMembers) -> io::Result<()> {
        for place in &members.visited_cities {
            let directory = &self.organization_directory;
            let shop = directory.at(place).find(|org| org.is_merchant()).ok_or_else(|| invalid("unknown visited merchant city"))?;
            if self.market_unit_at(place) != Some(&shop.unit) {
                return Err(invalid("visited merchant city has no statistical market"));
            }
            Arc::make_mut(&mut self.work_opening).register_regional(directory.at(place))?;
        }
        Ok(())
    }

    fn materialize_organization_members<'a>(&mut self, organizations: impl Iterator<Item = &'a Organization>) -> io::Result<()> {
        let birth_year = u16::try_from(self.clock.current_date().year - 30).map_err(io::Error::other)?;
        for org in organizations {
            for resident in std::iter::once(&org.officer).chain(org.opening_member.as_ref()) {
                // A previous slot may already use this identity or have no unassigned residents.
                if self.person(&resident.person).is_some()
                    || self.residence_unit_at(&org.place).and_then(|unit| self.population.unclassified(unit)).unwrap_or(0) == 0
                {
                    continue;
                }
                self.materialize_resident(&resident.person, resident.name.clone(), &org.place, birth_year, None)?;
                self.organization_members.appoint(org, resident);
            }
        }
        Ok(())
    }

    pub(crate) fn validate_organization_members(&self) -> io::Result<()> {
        for place in &self.organization_members.visited_cities {
            if self.organization_directory.at(place).any(|org| !self.organization_members.appointments.contains(&org.id)) {
                return Err(invalid("visited city lacks its founding appointments"));
            }
        }
        for id in &self.organization_members.appointments {
            let org = self.organization(id).ok_or_else(|| invalid("unknown organization appointment"))?;
            let officer = &org.officer;
            if !self.runtime_people.get(&officer.person).is_some_and(|row| {
                row.name == officer.name && row.origin.place_id == org.place && row.born_day.is_none()
                    && (1870..=self.clock.current_date().year - 30).contains(&i64::from(row.origin.birth_year))
            }) { return Err(invalid("organization officer differs from appointed resident")); }
        }
        for (id, people) in &self.organization_members.volunteers {
            if people.is_empty() || !self.organization(id).is_some_and(|org| {
                org.kind == OrganizationKind::MutualAid && people.iter().all(|person| {
                    person != &org.officer.person && self.person(person).is_some_and(|origin| {
                        let birth_year = if person == &self.player { self.player_birth_year() } else { origin.birth_year };
                        self.clock.current_date().year - i64::from(birth_year) >= 18
                    })
                })
            }) { return Err(invalid("unknown association or member")); }
        }
        let mut partnerships = 0;
        for org in self.organizations().filter(|org| org.kind == OrganizationKind::Enterprise) {
            let firm = org.firm.as_deref().unwrap();
            if self.ledger.default_account(firm).as_ref().map(|a| a.account_id) != org.account.as_deref() {
                return Err(invalid("organization settlement account differs from its registered firm"));
            }
            let held = self.has_partnership(org);
            if org.is_merchant() {
                let partner = self.ledger.default_account(&self.player).unwrap();
                let mut subscribed = false;
                for receipt in self.ledger.personal_receipts(firm).filter(|r| r.incoming && r.kind == "equity_issue") {
                    if held && receipt.id == format!("partnership:{}", org.id) {
                        subscribed = true;
                    } else if subscribed || !held || receipt.reference != org.id || !receipt.id.strip_prefix("contribution:")
                        .is_some_and(|suffix| suffix.parse::<u64>().is_ok_and(|n| (1..self.next_living_record).contains(&n) && n.to_string() == suffix))
                        || !self.ledger.has_payment(receipt.id, partner.account_id, org.account.as_deref().unwrap(),
                                                    receipt.amount, "equity_issue", &org.id) {
                        return Err(invalid("capital payment has no matching subscription or contribution"));
                    }
                }
                if subscribed != held { return Err(invalid("firm's capital differs from its subscription")); }
            }
            partnerships += usize::from(held);
        }
        if partnerships > 1 { return Err(invalid("player holds conflicting management appointments")); }
        Ok(())
    }

    fn has_partnership(&self, org: &Organization) -> bool {
        let Some(terms) = org.terms else { return false };
        let Some(from) = self.ledger.default_account(&self.player) else { return false };
        let Some(to) = org.account.as_deref() else { return false };
        self.ledger.has_payment(&format!("partnership:{}", org.id), from.account_id, to,
                                terms.hours * terms.wage_per_hour, "equity_issue", &org.id)
    }

    fn organization_role(&self, org: &Organization, person: &str) -> Option<OrganizationRole> {
        self.population.unit_for_person(person)?;
        if person == org.officer.person && self.organization_members.appointments.contains(&org.id) {
            return Some(org.officer.role);
        }
        if person == self.player && self.has_partnership(org) {
            return Some(OrganizationRole::Manager);
        }
        if self.work.contract(&self.work_opening, person)
            .is_some_and(|job| org.firm.as_deref() == Some(&job.employer)) {
            return Some(OrganizationRole::Employee);
        }
        self.organization_members.volunteers.get(&org.id)?.contains(person).then_some(OrganizationRole::Member)
    }

    pub fn organization_members(&self, id: &str) -> Vec<OrganizationMember<'_>> {
        let Some(org) = self.organization(id) else { return Vec::new() };
        self.named_people().filter_map(|person| {
            Some(OrganizationMember { person, role: self.organization_role(org, person)? })
        }).collect()
    }

    pub fn player_organization_role(&self, id: &str) -> Option<OrganizationRole> {
        self.organization_role(self.organization(id)?, &self.player)
    }

    pub fn organization_can_manage(&self, id: &str, person: &str) -> bool {
        self.organization(id).and_then(|org| self.organization_role(org, person))
            .is_some_and(|role| matches!(role, OrganizationRole::Owner | OrganizationRole::Manager))
    }

    pub(super) fn apply_organization_profile(&self, profile: &mut wwo_character_core::PersonView) {
        for org in self.organizations() {
            let Some(role) = self.organization_role(org, &self.player) else { continue };
            let label = format!("{} · {}", org.name, role.label());
            if matches!(role, OrganizationRole::Employee | OrganizationRole::Manager | OrganizationRole::Owner) {
                profile.social.occupation = Some(label.clone());
            }
            profile.social.relationships.get_or_insert_with(Vec::new).push(label);
        }
    }

    pub fn can_join_local_association(&self, id: &str) -> bool {
        let Some(org) = self.organization(id) else { return false };
        org.kind == OrganizationKind::MutualAid && self.organization_role(org, &self.player).is_none()
            && self.player_current_place() == Some(&org.place)
            && self.active_coordinator(id).is_some()
            && self.character.profile.age_years >= 18
    }

    pub fn join_local_association(&mut self, id: &str) -> io::Result<()> {
        if !self.can_join_local_association(id) { return Err(invalid("须由成年居民在当地向互助会联络员登记。")); }
        self.organization_members.volunteers.entry(id.into()).or_default().insert(self.player.clone());
        Ok(())
    }

    pub fn leave_local_association(&mut self, id: &str) -> io::Result<()> {
        if !self.player_alive() { return Err(invalid("人物已故。")); }
        let volunteers = self.organization_members.volunteers.get_mut(id).ok_or_else(|| invalid("未登记为该会会员。"))?;
        if !volunteers.remove(&self.player) { return Err(invalid("未登记为该会会员。")); }
        if volunteers.is_empty() { self.organization_members.volunteers.remove(id); }
        Ok(())
    }

    /// A local founder can admit the player before the firm's first receipt.
    /// The minimum contribution pays one shift at this employer's written terms.
    pub fn organization_partnership_offer(&self, id: &str) -> Option<i64> {
        let org = self.organization(id)?;
        let terms = org.terms?;
        let investment = terms.hours * terms.wage_per_hour;
        let firm = org.firm.as_deref()?;
        (self.player_current_place() == Some(&org.place) && self.eligible_for_civil_work(&self.player)
            && self.character.profile.age_years >= 18 && !self.has_committed_player_day()
            && !self.work.has_contract(&self.player)
            && !self.organizations().any(|other| self.has_partnership(other))
            && self.organization_members.appointments.contains(id)
            && self.current_place(&org.officer.person) == Some(&org.place)
            && self.eligible_for_civil_work(&org.officer.person)
            && self.ledger.default_account(&self.player)?.available >= investment
            && self.ledger.default_account(firm)?.cash == 0
            && !self.ledger.personal_receipts(firm).any(|row| row.incoming)).then_some(investment)
    }

    pub fn accept_organization_partnership(&mut self, id: &str) -> io::Result<()> {
        let amount = self.organization_partnership_offer(id).ok_or_else(|| invalid("当前不能签署当地商号的出资合伙约定。"))?;
        let from = self.ledger.default_account(&self.player).unwrap().account_id.to_owned();
        let to = self.organization(id).unwrap().account.clone().unwrap();
        self.ledger.transfer(&format!("partnership:{id}"), &from, &to, amount,
                             self.clock.snapshot().total_minutes, "equity_issue", id)
    }

    pub fn can_contribute_to_business(&self, shop: &str, amount: i64) -> bool {
        let Some(org) = self.organization(shop) else { return false };
        org.is_merchant() && self.has_partnership(org) && self.player_current_place() == Some(&org.place)
            && self.eligible_for_civil_work(&self.player) && self.next_living_record < crate::formal_ledger::MAX_AMOUNT as u64
            && self.balance().is_some_and(|a| (1..=a.available).contains(&amount))
    }

    pub fn contribute_to_business(&mut self, shop: &str, amount: i64) -> io::Result<()> {
        if !self.can_contribute_to_business(shop, amount) { return Err(invalid("须由在场合伙人使用本人的可用现款追加出资。")); }
        let from = self.balance().unwrap().account_id.to_owned();
        let to = self.organization(shop).unwrap().account.clone().unwrap();
        self.ledger.transfer(&format!("contribution:{}", self.next_living_record), &from, &to, amount,
                             self.clock.snapshot().total_minutes, "equity_issue", shop)?;
        self.next_living_record += 1;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::formal_bootstrap::WorldBootstrap;
    use crate::formal_ledger::Ledger;
    use crate::formal_save::{field, map, read_native_slot, NativeSlotSummary};
    use crate::formal_work::WorkOpening;

    #[test]
    fn merchant_registration_follows_an_actual_arrival_and_survives_a_slot() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let route = "rail_paris_rouen";
        let place = "place:rouen";
        let shop = "organization:opening_rouen_merchant";
        let firm = "firm:opening_rouen_merchant";
        let job = "job:opening_rouen_merchant";
        let pool = world.residence_unit_at(place).unwrap().to_owned();
        let anonymous = world.population.unclassified(&pool).unwrap();
        let national = world.population.totals()["country_fra"];
        let named = world.named_people().count();
        let duration = i64::from(world.transport().segment(route).unwrap().profile.travel_minutes);
        world.travel_player(route, place).unwrap();
        assert!(world.organization(shop).is_none());
        assert!(world.work_opening.job(job).is_none());
        assert!(world.ledger.default_account(firm).is_none());
        let underway = world.snapshot();
        let mut world = bootstrap.restore_native(serde_json::from_value(underway).unwrap()).unwrap();
        world.advance_migrated_domains(duration, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(place));
        assert_eq!(world.organization(shop).unwrap().unit, "country_fra");
        assert_eq!(world.work_opening.job(job).unwrap().place, place);
        assert_eq!(world.organization_members("organization:opening_rouen_association").len(), 2);
        assert_eq!(world.ledger.default_account(firm).unwrap().cash, 0);
        assert_eq!(world.population.totals()["country_fra"], national);
        assert_eq!(world.population.unclassified(&pool), Some(anonymous - 3));
        assert_eq!(world.named_people().count(), named + 3);
        assert!(world.organization("organization:opening_lyon_merchant").is_none());
        let capital = world.organization_partnership_offer(shop).unwrap();
        world.accept_organization_partnership(shop).unwrap();
        let saved = world.snapshot();
        let mut restored = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert!(restored.snapshot() == saved);
        assert_eq!(restored.ledger.default_account(firm).unwrap().cash, capital);
        restored.travel_player(route, "place:paris").unwrap();
        restored.advance_migrated_domains(duration, &BTreeMap::new()).unwrap();
        restored.travel_player(route, place).unwrap();
        restored.advance_migrated_domains(duration, &BTreeMap::new()).unwrap();
        assert_eq!(restored.named_people().count(), named + 3);
        assert_eq!(restored.population.unclassified(&pool), Some(anonymous - 3));

        let mut other = bootstrap.create("german_empire").unwrap();
        let traveler = "person:formal_generated_country_fra_0001";
        other.travel_person(traveler, route, place).unwrap();
        other.advance_migrated_domains(duration, &BTreeMap::new()).unwrap();
        assert_eq!(other.current_place(traveler), Some(place));
        assert!(other.organization(shop).is_some());
        assert_eq!(other.player_current_place(), Some("place:berlin"));
    }

    #[test]
    fn old_native_slot_registers_residents_and_zero_accounts_once() {
        for historical in [false, true] {
            check_old_native_slot(historical);
        }
    }

    fn check_old_native_slot(historical: bool) {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut old = bootstrap.base_opening("german_empire", None, historical).unwrap();
        if historical {
            let seine = old.residence_unit_at("place:paris").unwrap().to_owned();
            let anonymous = old.population.unclassified(&seine).unwrap();
            old.transfer_unmanaged_population(&seine, "country_fra", anonymous, 0).unwrap();
        }
        // Reproduce the preceding native account roster: named residents and the two Paris firms.
        old.ledger = Ledger::initialize_people(bootstrap.residents.iter().map(|(person, cash)| (person.as_str(), *cash))).unwrap();
        WorkOpening::load(|unit, place| (unit == "country_fra").then(|| place.to_owned())).unwrap().open_accounts(&mut old.ledger).unwrap();
        old.ledger.ensure_transport_account().unwrap();
        old.advance_migrated_domains(60, &BTreeMap::new()).unwrap();
        let price = old.macro_economy().markets()["german_empire"].commodities["bread"].price_centimes;
        old.buy_local_stock("market:legacy_aggregate:german_empire", "bread", 1, price, "old-purchase").unwrap();
        assert!(old.ledger.default_account("firm:opening_berlin_merchant").is_none());
        let mut old_snapshot = old.snapshot();
        for name in ["organization_members", "activity", "counters"] {
            old_snapshot.as_object_mut().unwrap().remove(name);
        }
        old_snapshot["work"].as_object_mut().unwrap().remove("referrals");
        old_snapshot["enterprises"].as_object_mut().unwrap().retain(|field, _| matches!(field.as_str(), "settled_day" | "sites"));
        let summary = NativeSlotSummary { opening: "german_empire".into(), clock: old.clock.snapshot(), written_access: None };
        let mut slot = serde_json::to_vec(&("wwo_rust_formal_world_v1", summary)).unwrap();
        slot.push(b'\n');
        serde_json::to_writer(&mut slot, &old_snapshot).unwrap();
        let path = std::env::temp_dir().join(format!("wwo-old-organization-slot-{}.json", std::process::id()));
        std::fs::write(&path, slot).unwrap();
        let migrated = read_native_slot(&path, &bootstrap);
        std::fs::remove_file(path).unwrap();
        let world = migrated.unwrap();
        assert_eq!(world.population.totals(), old.population.totals());
        assert_eq!(world.clock(), old.clock());
        assert_eq!(world.holding_milli("bread"), old.holding_milli("bread"));
        assert_eq!(world.balance().unwrap().cash, old.balance().unwrap().cash);
        assert_eq!(world.ledger.default_account("firm:opening_berlin_merchant").unwrap().cash, 0);
        let ledger = world.ledger.snapshot();
        for key in ["scenario_budget", "transactions"] {
            assert_eq!(field(map(&ledger).unwrap(), key).unwrap(), field(map(&old_snapshot["ledger"]).unwrap(), key).unwrap());
        }
        assert_eq!(world.organization_members("organization:opening_berlin_association").len(), 2);
        let association = world.organization("organization:opening_berlin_association").unwrap();
        let pool = if historical { "administrative_region:germany_preussen" } else { "german_empire" };
        assert_eq!(world.population.unit_for_person(&association.officer.person), Some(pool));
        assert_eq!(world.market_unit_for_person(&association.officer.person), Some("german_empire"));
        assert_eq!(world.population.unclassified(pool), old.population.unclassified(pool).map(|count| count - 3));
        if historical {
            let paris = world.organization("organization:opening_paris_association").unwrap();
            assert!(world.person(&paris.officer.person).is_none());
            assert_eq!(world.population.unclassified("country_fra"), old.population.unclassified("country_fra"));
        }
        let saved = world.snapshot();
        let resumed = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert!(resumed.snapshot() == saved, "second restore changed the migrated slot");
    }

    #[test]
    fn organization_capital_requires_owner_consent_and_real_cash() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("german_empire").unwrap();
        let shop = "organization:opening_berlin_merchant";
        let firm = "firm:opening_berlin_merchant";
        let cash = world.balance().unwrap().cash;
        let capital = world.organization_partnership_offer(shop).unwrap();
        assert!(world.contribute_to_business(shop, 1).is_err());
        assert!(world.accept_organization_partnership("organization:opening_london_merchant").is_err());
        world.accept_organization_partnership(shop).unwrap();
        assert!(world.accept_organization_partnership(shop).is_err());
        assert!(world.contribute_to_business(shop, cash).is_err());
        world.contribute_to_business(shop, 1).unwrap();
        assert_eq!(world.balance().unwrap().cash, cash - capital - 1);
        assert_eq!(world.ledger.default_account(firm).unwrap().cash, capital + 1);
        let saved = world.snapshot();
        let resumed = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert!(resumed.snapshot() == saved);
        assert!(resumed.organization_can_manage(shop, &resumed.player));
    }
}
