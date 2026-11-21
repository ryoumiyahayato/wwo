use crate::{
    formal_clock::{GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_ledger::{Ledger, MAX_AMOUNT},
    formal_save::invalid,
};
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, io};

#[derive(Deserialize)]
pub(crate) struct WorkOpening {
    jobs: Vec<Job>,
    firms: Vec<Firm>,
    actors: Vec<Actor>,
    information: Vec<Notice>,
}

#[derive(Deserialize)]
pub struct Job {
    pub id: String,
    pub employer: String,
    pub place: String,
    pub positions: usize,
    pub hours: i64,
    pub wage_per_hour: i64,
    pub wage_delay: i64,
    skill: u64,
}

#[derive(Deserialize)]
struct Firm { id: String, account_id: String, cash: i64, host_organization_id: String }

#[derive(Deserialize)]
struct Actor { id: String, skill: u64, control: String }

#[derive(Deserialize)]
struct Notice { actor: String, kind: String, candidate: String, delivery_day: i64 }

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorkState {
    contracts: BTreeMap<String, String>,
    bookings: BTreeMap<String, i64>,
    #[serde(default)]
    local_notices: BTreeMap<String, BTreeSet<String>>,
}

impl WorkOpening {
    pub(crate) fn load() -> io::Result<Self> {
        let opening: Self = serde_json::from_slice(include_bytes!("../../../data/formal/paris_employment_opening_r1.json"))?;
        let mut ids = BTreeSet::new();
        for job in &opening.jobs {
            if !ids.insert(&job.id) || !(1..=24).contains(&job.hours) || job.positions == 0
                || !(0..=MAX_AMOUNT / job.hours.max(1)).contains(&job.wage_per_hour)
                || !(0..=365).contains(&job.wage_delay)
                || !opening.firms.iter().any(|firm| firm.id == job.employer)
            {
                return Err(invalid("invalid formal opening employment terms"));
            }
        }
        Ok(opening)
    }

    pub(crate) fn open_accounts(&self, ledger: &mut Ledger) -> io::Result<()> {
        for firm in &self.firms {
            ledger.open_firm(&firm.id, &firm.account_id, firm.cash)?;
        }
        Ok(())
    }

    fn known_jobs<'a>(&'a self, actor_id: &'a str, day: i64) -> impl Iterator<Item = &'a Job> {
        self.jobs.iter().filter(move |job| {
            self.actors.iter().any(|actor| actor.id == actor_id && actor.skill >= job.skill)
                && self.information.iter().any(|notice| notice.actor == actor_id && notice.kind == "job"
                    && notice.candidate == job.id && notice.delivery_day <= day)
        })
    }

    pub(crate) fn jobs<'a>(&'a self, actor: &'a str, current_place: Option<&'a str>, day: i64) -> impl Iterator<Item = &'a Job> {
        self.known_jobs(actor, day).filter(move |job| current_place == Some(job.place.as_str()))
    }

    pub(crate) fn find<'a>(&'a self, actor: &str, job: &str) -> Option<&'a Job> {
        let actor = self.actors.iter().find(|row| row.id == actor)?;
        self.known_jobs(&actor.id, i64::MAX).find(|row| row.id == job)
    }

    pub(crate) fn entry_job(&self, id: &str) -> Option<&Job> {
        self.jobs.iter().find(|job| job.id == id && job.skill <= 1)
    }

    pub(crate) fn organization(&self, employer: &str) -> Option<&str> {
        self.firms.iter().find(|firm| firm.id == employer).map(|firm| firm.host_organization_id.as_str())
    }

    pub(crate) fn automatic(&self) -> impl Iterator<Item = &str> {
        self.actors.iter().filter(|actor| actor.control == "automatic").map(|actor| actor.id.as_str())
    }
}

impl WorkState {
    pub(crate) fn consult_local_notices(&mut self, opening: &WorkOpening, actor: &str, place: &str) {
        let seen = opening.jobs.iter().filter(|job| job.place == place && job.skill <= 1)
            .map(|job| job.id.clone()).collect::<BTreeSet<_>>();
        if !seen.is_empty() {
            self.local_notices.entry(actor.to_owned()).or_default().extend(seen);
        }
    }

    pub(crate) fn local_jobs<'a>(&'a self, opening: &'a WorkOpening, actor: &'a str, place: Option<&'a str>, day: i64) -> impl Iterator<Item = &'a Job> {
        opening.jobs.iter().filter(move |job| {
            place == Some(job.place.as_str()) && self.knows_job(opening, actor, job, day)
        })
    }

    fn knows_job(&self, opening: &WorkOpening, actor: &str, job: &Job, day: i64) -> bool {
        opening.known_jobs(actor, day).any(|row| row.id == job.id)
            || self.local_notices.get(actor).is_some_and(|seen| seen.contains(&job.id))
    }

    pub(crate) fn contract<'a>(&self, opening: &'a WorkOpening, actor: &str) -> Option<&'a Job> {
        let id = self.contracts.get(actor)?;
        opening.jobs.iter().find(|job| &job.id == id)
    }

    pub(crate) fn booking(&self, actor: &str) -> Option<i64> {
        self.bookings.get(actor).copied()
    }

    pub(crate) fn vacancies(&self, job: &Job) -> usize {
        job.positions.saturating_sub(self.contracts.values().filter(|id| **id == job.id).count())
    }

    pub(crate) fn apply(&mut self, opening: &WorkOpening, actor: &str, job_id: &str, current_place: Option<&str>, day: i64) -> io::Result<()> {
        let job = self.local_jobs(opening, actor, current_place, day).find(|job| job.id == job_id)
            .ok_or_else(|| invalid("该地点没有可以申请的这份工作。"))?;
        if self.contracts.contains_key(actor) || self.vacancies(job) == 0 {
            return Err(invalid("已有劳动合同，或该岗位已满。"));
        }
        self.contracts.insert(actor.into(), job.id.clone());
        Ok(())
    }

    pub(crate) fn release(&mut self, actor: &str) -> io::Result<()> {
        if self.booking(actor).is_some() {
            return Err(invalid("工作已登记，须等班次结算后离职。"));
        }
        self.contracts.remove(actor).ok_or_else(|| invalid("人物没有劳动合同。"))?;
        Ok(())
    }

    pub(crate) fn can_book(&self, opening: &WorkOpening, actor: &str, current_place: Option<&str>, clock: GameClock) -> bool {
        self.contract(opening, actor).is_some_and(|job| current_place == Some(job.place.as_str())
            && self.booking(actor).is_none() && shift_fits(job, clock.snapshot().total_minutes))
    }

    pub(crate) fn book(&mut self, opening: &WorkOpening, actor: &str, current_place: Option<&str>, clock: GameClock) -> io::Result<()> {
        let job = self.contract(opening, actor).ok_or_else(|| invalid("人物没有劳动合同。"))?;
        if current_place != Some(job.place.as_str()) {
            return Err(invalid("人物目前不在工作地点。"));
        }
        if !self.can_book(opening, actor, current_place, clock) {
            return Err(invalid("今日已登记工作，或剩余时间不足。"));
        }
        self.bookings.insert(actor.into(), clock.snapshot().total_minutes);
        Ok(())
    }

    pub(crate) fn book_automatic<'a>(&mut self, opening: &WorkOpening, clock: GameClock, present_place: impl Fn(&str) -> Option<&'a str>) {
        for (actor, place) in opening.automatic().filter_map(|actor| Some((actor, present_place(actor)?))) {
            let current_place = Some(place);
            if !self.contracts.contains_key(actor) {
                let jobs = opening.jobs(actor, current_place, clock.current_day()).filter(|job| self.vacancies(job) > 0);
                if let Some(job) = jobs.max_by_key(|job| (job.wage_per_hour, std::cmp::Reverse(&job.id))) {
                    let _ = self.apply(opening, actor, &job.id, current_place, clock.current_day());
                }
            }
            let _ = self.book(opening, actor, current_place, clock);
        }
    }

    pub(crate) fn booked_workers(&self) -> impl Iterator<Item = &String> { self.bookings.keys() }

    pub(crate) fn remove_actor(&mut self, actor: &str) {
        self.bookings.remove(actor);
        self.contracts.remove(actor);
    }

    pub(crate) fn has_contract(&self, actor: &str) -> bool { self.contracts.contains_key(actor) }

    pub(crate) fn forget_actor(&mut self, actor: &str) {
        self.remove_actor(actor);
        self.local_notices.remove(actor);
    }

    pub(crate) fn complete(&mut self) { self.bookings.clear(); }

    pub(crate) fn validate<'a>(&self, opening: &WorkOpening, clock: GameClock, present_place: impl Fn(&str) -> Option<&'a str>, alive: impl Fn(&str) -> bool) -> bool {
        self.local_notices.iter().all(|(actor, seen)| alive(actor) && !seen.is_empty() && seen.iter().all(|id| {
            opening.jobs.iter().any(|job| &job.id == id && job.skill <= 1)
        })) && self.contracts.iter().all(|(actor, job)| alive(actor) && opening.jobs.iter().any(|row| {
            row.id == *job && self.knows_job(opening, actor, row, clock.current_day())
                && self.contracts.values().filter(|id| *id == job).count() <= row.positions
        })) && self.bookings.iter().all(|(actor, &minute)| self.contract(opening, actor).is_some_and(|job| {
            (present_place(actor) == Some(job.place.as_str())
                || clock.snapshot().total_minutes >= minute + job.hours * MINUTES_PER_HOUR)
                && (clock.current_day() * MINUTES_PER_DAY..=clock.snapshot().total_minutes).contains(&minute)
                && shift_fits(job, minute)
        }))
    }
}

fn shift_fits(job: &Job, minute: i64) -> bool {
    MINUTES_PER_DAY - minute % MINUTES_PER_DAY >= job.hours * MINUTES_PER_HOUR
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn employment_persists_during_absence_but_work_requires_presence_and_time() {
        let opening = WorkOpening::load().unwrap();
        let person = "person:formal_generated_country_fra_0001";
        let workplace = Some("place:paris");
        let away = Some("place:rouen");
        let work_id = "job:opening_paris_workshop";
        let mut work = WorkState::default();
        let mut clock = GameClock::default();

        assert!(opening.jobs(person, None, 0).next().is_none());
        assert!(work.apply(&opening, person, work_id, away, 0).is_err());
        work.apply(&opening, person, work_id, workplace, 0).unwrap();
        let job = work.contract(&opening, person).unwrap();
        assert_eq!(job.id, work_id);
        assert_eq!(work.vacancies(job), 0);
        assert!(work.validate(&opening, clock, |_| away, |_| true));
        assert!(work.book(&opening, person, None, clock).is_err());
        assert!(work.book(&opening, person, away, clock).is_err());

        clock.advance_minutes(MINUTES_PER_DAY - job.hours * MINUTES_PER_HOUR + 1).unwrap();
        assert!(!work.can_book(&opening, person, workplace, clock));
        clock.advance_minutes(MINUTES_PER_DAY - clock.snapshot().total_minutes).unwrap();
        work.book(&opening, person, workplace, clock).unwrap();
        assert!(work.release(person).is_err());
        assert!(!work.validate(&opening, clock, |_| away, |_| true));
        work.complete();
        work.release(person).unwrap();
        assert_eq!(work.vacancies(job), 1);
    }
}
