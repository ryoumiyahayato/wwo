use super::*;
use crate::transport::{ModeSet, operations::Traffic};

// Generated simulation assumption. Historical population inputs do not include
// migration rates. Income per head selects candidates, not individual decisions.
const REVIEW_DAYS: i64 = 30;
const MAX_BATCH_MEMBERS: u32 = 8;

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct MigrationState {
    pending: BTreeMap<String, Migration>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Migration {
    destination: String,
    members: u32,
    reservation: u64,
    from: String,
    traversed: Vec<String>,
}

pub struct BackgroundMigration<'a> {
    pub source: &'a str,
    pub destination: &'a str,
    pub members: u32,
    pub station: &'a str,
    pub blocked: bool,
    pub arrival_minute: i64,
}

impl InitialWorld {
    pub fn background_migration(&self, source: &str) -> Option<BackgroundMigration<'_>> {
        let (source, row) = self.migration.pending.get_key_value(source)?;
        let reservation = row.reservation;
        Some(BackgroundMigration {
            source,
            destination: &row.destination,
            members: row.members,
            station: self.transport.location(reservation)?,
            blocked: self.transport.held(reservation).is_some(),
            arrival_minute: self.transport.plan(reservation)?.arrival_minute(),
        })
    }

    pub(super) fn migration_reserved_at(&self, unit: &str) -> u64 {
        self.migration.pending.get(unit).map_or(0, |row| u64::from(row.members))
    }

    /// Reserve one group of unclassified residents on the world's passenger services.
    pub fn dispatch_background_migration(
        &mut self, source: &str, destination: &str, members: u32, source_managed_background: u64,
    ) -> io::Result<()> {
        if source == destination || self.migration.pending.contains_key(source) || members == 0
            || self.population.unclassified(source).and_then(|count| count.checked_sub(source_managed_background))
                .is_none_or(|free| free < u64::from(members))
        {
            return Err(invalid("迁移批次超出可用背景人口，或该地区已有在途批次。"));
        }
        let from = self.transport.network().area_node(source)
            .ok_or_else(|| invalid("出发区没有正式交通节点。"))?.to_owned();
        let to = self.transport.network().area_node(destination)
            .ok_or_else(|| invalid("到达区没有正式交通节点。"))?.to_owned();
        let plan = self.transport.quote_service(&from, &to, ModeSet::ALL, members,
            self.clock.snapshot().total_minutes, Traffic::Migration)?;
        let reservation = self.transport.reserve_migration(plan)?;
        self.migration.pending.insert(source.to_owned(), Migration {
            destination: destination.to_owned(), members, reservation, from, traversed: Vec::new(),
        });
        Ok(())
    }

    pub(super) fn settle_background_migrations(&mut self, minute: i64) -> io::Result<()> {
        let completed: Vec<_> = self.migration.pending.iter().filter_map(|(source, row)| {
            self.transport.completed(row.reservation).map(|_| source.clone())
        }).collect();
        for source in completed {
            let row = &self.migration.pending[&source];
            self.population.transfer_unmanaged(&source, &row.destination, u64::from(row.members), 0, minute)?;
            self.transport.finish(row.reservation);
            self.migration.pending.remove(&source);
        }
        Ok(())
    }

    pub(super) fn review_background_migration(&mut self, externally_managed: &BTreeMap<String, u64>) {
        let now = self.clock.snapshot().total_minutes;
        let held: Vec<_> = self.migration.pending.values_mut().filter_map(|row| {
            let from = self.transport.held(row.reservation)?.to_owned();
            let to = self.transport.network().area_node(&row.destination)?.to_owned();
            Some((row, from, to))
        }).collect();
        for (row, from, to) in held {
            let passed: Vec<_> = self.transport.plan(row.reservation).expect("held reservation has a plan")
                .route().legs.iter().take_while(|leg| leg.from != from).map(|leg| leg.segment_id.clone()).collect();
            let plan = self.transport.quote_service(&from, &to, ModeSet::ALL, row.members, now, Traffic::Migration);
            if let Ok(reservation) = plan.and_then(|plan| self.transport.reserve_migration(plan)) {
                self.transport.finish(row.reservation);
                row.reservation = reservation;
                row.from = from;
                row.traversed.extend(passed);
            }
        }

        if self.clock.current_day() % REVIEW_DAYS != 0 { return; }
        let mut destinations: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        let network = self.transport.network();
        for segment in network.segments() {
            if !network.availability(&segment.id).is_some_and(|access| access.open) { continue; }
            let Some((from, to)) = network.unit_at(&segment.from).zip(network.unit_at(&segment.to)) else { continue; };
            if from == to { continue; }
            destinations.entry(from.to_owned()).or_default().insert(to.to_owned());
            if segment.bidirectional {
                destinations.entry(to.to_owned()).or_default().insert(from.to_owned());
            }
        }
        for (source, targets) in destinations {
            if self.migration.pending.contains_key(&source) { continue; }
            let Some(&income) = self.sources.population_income.get(&source) else { continue; };
            let managed = externally_managed.get(&source).copied().unwrap_or(0);
            let available = self.population.unclassified(&source).unwrap_or(0).saturating_sub(managed);
            let members = available.min(u64::from(MAX_BATCH_MEMBERS)) as u32;
            if members == 0 || income == 0 { continue; }
            let mut candidates: Vec<_> = targets.into_iter().filter_map(|target| {
                let &income_to = self.sources.population_income.get(&target)?;
                // A 25% income gap is the minimum threshold for this review.
                (income_to.saturating_mul(4) >= income.saturating_mul(5))
                    .then_some((std::cmp::Reverse(income_to), target))
            }).collect();
            candidates.sort_unstable();
            for (_, target) in candidates {
                if self.dispatch_background_migration(&source, &target, members, managed).is_ok() { break; }
            }
        }
    }

    pub(super) fn validate_migrations(&self, reservations: &mut BTreeSet<u64>) -> bool {
        let network = self.transport.network();
        self.migration.pending.iter().all(|(source, row)| {
            let traversed = network.area_node(source).and_then(|origin| {
                row.traversed.iter().try_fold(origin, |station, id| {
                    let segment = network.segment(id)?;
                    if segment.from == station { Some(segment.to.as_str()) }
                    else if segment.bidirectional && segment.to == station { Some(segment.from.as_str()) }
                    else { None }
                })
            });
            source != &row.destination && traversed == Some(row.from.as_str())
                && row.members > 0 && self.population.unclassified(source)
                    .is_some_and(|pop| pop >= u64::from(row.members))
                && reservations.insert(row.reservation)
                && self.transport.traffic(row.reservation) == Some(Traffic::Migration)
                && self.transport.completed(row.reservation).is_none()
                && self.transport.plan(row.reservation).is_some_and(|plan| {
                    plan.load_units() == row.members && plan.route().from == row.from
                        && Some(plan.route().to.as_str()) == network.area_node(&row.destination)
                })
        })
    }
}
