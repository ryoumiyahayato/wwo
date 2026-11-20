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
struct Actor { id: String, place_id: String, skill: u64, control: String }

#[derive(Deserialize)]
struct Notice { actor: String, kind: String, candidate: String, delivery_day: i64 }

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorkState {
    contracts: BTreeMap<String, String>,
    bookings: BTreeMap<String, i64>,
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

    pub(crate) fn jobs<'a>(&'a self, actor_id: &'a str, day: i64) -> impl Iterator<Item = &'a Job> {
        self.jobs.iter().filter(move |job| {
            self.actors.iter().any(|actor| actor.id == actor_id && actor.place_id == job.place && actor.skill >= job.skill)
                && self.information.iter().any(|notice| notice.actor == actor_id && notice.kind == "job"
                    && notice.candidate == job.id && notice.delivery_day <= day)
        })
    }

    pub(crate) fn find<'a>(&'a self, actor: &str, job: &str) -> Option<&'a Job> {
        let actor = self.actors.iter().find(|row| row.id == actor)?;
        self.jobs(&actor.id, i64::MAX).find(|row| row.id == job)
    }

    pub(crate) fn organization(&self, employer: &str) -> Option<&str> {
        self.firms.iter().find(|firm| firm.id == employer).map(|firm| firm.host_organization_id.as_str())
    }

    pub(crate) fn automatic(&self) -> impl Iterator<Item = &str> {
        self.actors.iter().filter(|actor| actor.control == "automatic").map(|actor| actor.id.as_str())
    }
}

impl WorkState {
    pub(crate) fn contract<'a>(&self, opening: &'a WorkOpening, actor: &str) -> Option<&'a Job> {
        opening.find(actor, self.contracts.get(actor)?)
    }

    pub(crate) fn booking(&self, actor: &str) -> Option<i64> {
        self.bookings.get(actor).copied()
    }

    pub(crate) fn vacancies(&self, job: &Job) -> usize {
        job.positions.saturating_sub(self.contracts.values().filter(|id| **id == job.id).count())
    }

    pub(crate) fn apply(&mut self, opening: &WorkOpening, actor: &str, job_id: &str, day: i64) -> io::Result<()> {
        let job = opening.jobs(actor, day).find(|job| job.id == job_id)
            .ok_or_else(|| invalid("该地点没有可以申请的这份工作。"))?;
        if self.contracts.contains_key(actor) || self.vacancies(job) == 0 {
            return Err(invalid("已有劳动合同，或该岗位已满。"));
        }
        self.contracts.insert(actor.into(), job.id.clone());
        Ok(())
    }

    pub(crate) fn book(&mut self, opening: &WorkOpening, actor: &str, clock: GameClock) -> io::Result<()> {
        let job = self.contract(opening, actor).ok_or_else(|| invalid("人物没有劳动合同。"))?;
        let minute = clock.snapshot().total_minutes;
        if self.bookings.contains_key(actor) || MINUTES_PER_DAY - minute % MINUTES_PER_DAY < job.hours * MINUTES_PER_HOUR {
            return Err(invalid("今日已登记工作，或剩余时间不足。"));
        }
        self.bookings.insert(actor.into(), minute);
        Ok(())
    }

    pub(crate) fn book_automatic(&mut self, opening: &WorkOpening, clock: GameClock, alive: impl Fn(&str) -> bool) {
        for actor in opening.automatic().filter(|actor| alive(actor)) {
            if !self.contracts.contains_key(actor) {
                let jobs = opening.jobs(actor, clock.current_day()).filter(|job| self.vacancies(job) > 0);
                if let Some(job) = jobs.max_by_key(|job| (job.wage_per_hour, std::cmp::Reverse(&job.id))) {
                    let _ = self.apply(opening, actor, &job.id, clock.current_day());
                }
            }
            let _ = self.book(opening, actor, clock);
        }
    }

    pub(crate) fn booked_workers(&self) -> impl Iterator<Item = &String> { self.bookings.keys() }

    pub(crate) fn record_death(&mut self, actor: &str) {
        self.bookings.remove(actor);
        self.contracts.remove(actor);
    }

    pub(crate) fn has_contract(&self, actor: &str) -> bool { self.contracts.contains_key(actor) }

    pub(crate) fn complete(&mut self) { self.bookings.clear(); }

    pub(crate) fn validate(&self, opening: &WorkOpening, clock: GameClock) -> bool {
        self.contracts.iter().all(|(actor, job)| opening.jobs(actor, clock.current_day()).any(|row| {
            row.id == *job && self.contracts.values().filter(|id| *id == job).count() <= row.positions
        })) && self.bookings.iter().all(|(actor, &minute)| self.contract(opening, actor).is_some_and(|job| {
            (clock.current_day() * MINUTES_PER_DAY..=clock.snapshot().total_minutes).contains(&minute)
                && MINUTES_PER_DAY - minute % MINUTES_PER_DAY >= job.hours * MINUTES_PER_HOUR
        }))
    }
}
