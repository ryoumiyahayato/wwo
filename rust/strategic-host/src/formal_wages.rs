use crate::{
    formal_clock::{GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_ledger::{Ledger, CURRENCY, MAX_AMOUNT},
    formal_save::{field, integer, invalid, lookup, map, tagged, typed_int, typed_map},
};
use serde_json::{json, Value};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Claim {
    worker: String,
    job: String,
    employer: String,
    denomination: String,
    work_day: i64,
    due_day: i64,
    hours: i64,
    amount: i64,
    paid: i64,
    from: String,
    to: String,
}

pub struct WageClaims {
    claims: BTreeMap<String, Claim>,
    through: GameClock,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct CompletedFirmWork<'a> {
    pub work_id: &'a str,
    pub worker: &'a str,
    pub job: &'a str,
    pub hours: i64,
    pub denomination: &'a str,
    pub accrued_wages: i64,
    pub paid_wages: i64,
    pub unpaid_wages: i64,
}

impl WageClaims {
    pub(crate) fn initialize() -> Self {
        Self { claims: BTreeMap::new(), through: GameClock::default() }
    }

    pub(crate) fn record_shift(
        &mut self, worker: &str, job: &crate::formal_work::Job, day: i64, ledger: &Ledger,
    ) -> io::Result<()> {
        let id = format!("work:{day}:{worker}:{}", job.id);
        let from = ledger.default_account(&job.employer).ok_or_else(|| invalid("missing wage payer"))?;
        let to = ledger.default_account(worker).ok_or_else(|| invalid("missing wage recipient"))?;
        if day <= self.through.current_day() {
            return Err(invalid("completed work was already recorded"));
        }
        self.claims.entry(id).or_insert_with(|| Claim {
            worker: worker.into(), job: job.id.clone(), employer: job.employer.clone(), denomination: CURRENCY.into(),
            work_day: day, due_day: day + job.wage_delay, hours: job.hours, amount: job.hours * job.wage_per_hour,
            paid: 0, from: from.account_id.into(), to: to.account_id.into(),
        });
        Ok(())
    }

    pub(crate) fn claims(&self) -> &BTreeMap<String, Claim> { &self.claims }

    pub(crate) fn oldest_unpaid_day(&self, person: &str, employer: &str) -> Option<i64> {
        self.claims.values().filter(|claim| claim.worker == person && claim.employer == employer && claim.paid < claim.amount)
            .map(|claim| claim.due_day).min()
    }

    pub(crate) fn completed_firm_work<'a>(
        &'a self, firm: &str, day: i64,
    ) -> Vec<CompletedFirmWork<'a>> {
        self.claims.iter().filter(|(_, claim)| claim.employer == firm && claim.work_day == day)
            .map(|(id, claim)| CompletedFirmWork {
                work_id: id,
                worker: &claim.worker,
                job: &claim.job,
                hours: claim.hours,
                denomination: &claim.denomination,
                accrued_wages: claim.amount,
                paid_wages: claim.paid,
                unpaid_wages: claim.amount - claim.paid,
            }).collect()
    }

    pub(crate) fn restore_shifts(
        claims: BTreeMap<String, Claim>, opening: &crate::formal_work::WorkOpening, ledger: &Ledger, clock: GameClock,
        runtime_actor: impl Fn(&str) -> bool,
    ) -> io::Result<Self> {
        let mut worker_days = std::collections::BTreeSet::new();
        for (id, claim) in &claims {
            let job = opening.find(&claim.worker, &claim.job)
                .or_else(|| runtime_actor(&claim.worker).then(|| opening.entry_job(&claim.job)).flatten())
                .ok_or_else(|| invalid("unknown work terms"))?;
            if id != &format!("work:{}:{}:{}", claim.work_day, claim.worker, claim.job)
                || !worker_days.insert((&claim.worker, claim.work_day))
                || !(1..=clock.current_day()).contains(&claim.work_day)
                || claim.employer != job.employer || claim.denomination != CURRENCY
                || claim.hours != job.hours || claim.amount != job.hours * job.wage_per_hour
                || claim.due_day != claim.work_day + job.wage_delay || !(0..=claim.amount).contains(&claim.paid)
                || ledger.default_account(&claim.employer).map(|account| account.account_id) != Some(&claim.from)
                || ledger.default_account(&claim.worker).map(|account| account.account_id) != Some(&claim.to)
            { return Err(invalid("invalid formal work history")); }
        }
        ledger.validate_wage_history(claims.iter().map(|(id, claim)| (
            id.as_str(), claim.from.as_str(), claim.to.as_str(), claim.due_day * MINUTES_PER_DAY, claim.paid,
        )), clock.snapshot().total_minutes)?;
        Ok(Self { claims, through: clock })
    }

    pub(crate) fn restore(native: &Value, ledger: &Ledger, clock: GameClock) -> io::Result<Self> {
        let native = map(native)?;
        let day = integer(field(native, "day")?)?;
        let wages = map(field(native, "wages")?)?;
        let works = indexed(field(native, "work_records")?)?;
        if day != clock.current_day() || wages.len() != works.len() {
            return Err(invalid("wages and completed work do not match the formal day"));
        }
        let commands = indexed(field(native, "commands")?)?;
        let config = map(field(native, "config")?)?;
        let mut jobs = BTreeMap::new();
        for row in tagged(field(config, "jobs")?, "array")? {
            let job = map(row)?;
            if jobs.insert(string(job, "id")?, job).is_some() {
                return Err(invalid("duplicate configured job"));
            }
        }
        let mut claims = BTreeMap::new();
        for pair in wages {
            let id = pair[0].as_str().ok_or_else(|| invalid("invalid wage claim ID"))?;
            let row = map(&pair[1])?;
            let work = works.get(id).ok_or_else(|| invalid("wage has no completed work"))?;
            let worker = string(row, "worker")?;
            let job = string(work, "job")?;
            let employer = string(row, "employer")?;
            let denomination = currency(row)?;
            let work_day = integer(field(row, "work_day")?)?;
            let due_day = integer(field(row, "due_day")?)?;
            let hours = integer(field(row, "hours")?)?;
            let amount = integer(field(row, "amount")?)?;
            let paid = integer(field(row, "paid")?)?;
            let remaining = integer(field(row, "remaining")?)?;
            let work_id = format!("work:{work_day}:{worker}");
            if string(row, "id")? != id || (id != work_id && id != format!("{work_id}:{job}"))
                || !(1..=day).contains(&work_day) || !(work_day..=i64::MAX / MINUTES_PER_DAY).contains(&due_day)
                || hours <= 0 || integer(field(work, "hours")?)? != hours
                || string(work, "actor")? != worker || integer(field(work, "day")?)? != work_day
                || !(0..=MAX_AMOUNT).contains(&amount) || !(0..=amount).contains(&paid) || remaining != amount - paid
            {
                return Err(invalid("wage differs from its completed work"));
            }
            let job_source = jobs.get(job).ok_or_else(|| invalid("completed work has no configured job"))?;
            if string(job_source, "employer")? != employer || currency(job_source)? != denomination {
                return Err(invalid("wage differs from configured employer or currency"));
            }
            let action = string(work, "action_id")?;
            let (command, _) = accepted(&commands, action, worker)?;
            let minute = integer(field(command, "minute")?)?;
            let payload = map(field(command, "payload")?)?;
            if string(command, "kind")? != "work" || !(0..work_day * MINUTES_PER_DAY).contains(&minute)
                || integer(field(payload, "hours")?)? != hours
                || id != work_id && string(payload, "job_id")? != job
            {
                return Err(invalid("wages must come from an accepted work action"));
            }
            let (terms, workers) = if lookup(work, "employment_action_id").is_some() {
                let employment = string(work, "employment_action_id")?;
                let (_, outcome) = accepted(&commands, employment, worker)?;
                let contract = map(field(outcome, "employment")?)?;
                let terms = map(field(contract, "terms")?)?;
                if string(contract, "job")? != job || string(contract, "employment_action_id")? != employment
                    || currency(terms)? != denomination || integer(field(terms, "effective_minute")?)? > minute
                {
                    return Err(invalid("completed work differs from agreed employment"));
                }
                (terms, Some(integer(field(contract, "workers")?)?))
            } else {
                (job_source.as_ref(), (id == work_id).then_some(1))
            };
            let rate = integer(field(terms, "wage_per_hour")?)?;
            let delay = integer(field(terms, "wage_delay")?)?;
            let shift_hours = integer(field(terms, "hours")?)?;
            let elapsed_hours = (work_day * MINUTES_PER_DAY - minute) / MINUTES_PER_HOUR;
            let hours_per_worker = shift_hours.min(elapsed_hours);
            if !(0..=MAX_AMOUNT).contains(&rate) || rate.checked_mul(hours) != Some(amount)
                || delay < 0 || work_day.checked_add(delay) != Some(due_day)
                || hours_per_worker <= 0
                || workers.is_some_and(|workers| workers <= (hours - 1) / hours_per_worker)
            {
                return Err(invalid("wage amount or maturity differs from accepted work terms"));
            }
            let from = ledger.account_for(employer, denomination).ok_or_else(|| invalid("missing wage payer"))?;
            let to = ledger.account_for(worker, denomination).ok_or_else(|| invalid("missing wage recipient"))?;
            if from.account_id == to.account_id {
                return Err(invalid("wage payer is also its recipient"));
            }
            let claim = Claim {
                worker: worker.to_owned(), job: job.to_owned(), employer: employer.to_owned(),
                denomination: denomination.to_owned(), work_day, due_day, hours, amount, paid,
                from: from.account_id.to_owned(), to: to.account_id.to_owned(),
            };
            if claims.insert(id.to_owned(), claim).is_some() {
                return Err(invalid("duplicate wage claim"));
            }
        }
        ledger.validate_wage_history(claims.iter().map(|(id, claim)| (
            id.as_str(), claim.from.as_str(), claim.to.as_str(), claim.due_day * MINUTES_PER_DAY, claim.paid,
        )), clock.snapshot().total_minutes)?;
        Ok(Self { claims, through: clock })
    }

    pub fn open_count(&self) -> usize {
        self.claims.values().filter(|claim| claim.amount > claim.paid).count()
    }

    pub fn snapshot(&self) -> Value {
        typed_map(self.claims.iter().map(|(id, claim)| (id, typed_map([
            ("id", json!(id)), ("worker", json!(claim.worker)), ("employer", json!(claim.employer)),
            ("hours", typed_int(claim.hours)), ("amount", typed_int(claim.amount)),
            ("remaining", typed_int(claim.amount - claim.paid)), ("work_day", typed_int(claim.work_day)),
            ("due_day", typed_int(claim.due_day)), ("paid", typed_int(claim.paid)),
            ("denomination", json!(claim.denomination)),
        ]))))
    }

    /// Revisit unpaid work in R68 order. Enterprises with an active wind-down
    /// authority use the separate closure settlement path.
    pub fn settle_due(
        &mut self, ledger: &mut Ledger, clock: GameClock, manual_wind_down: impl Fn(&str) -> bool,
    ) -> io::Result<usize> {
        let minute = clock.snapshot().total_minutes;
        if minute < self.through.snapshot().total_minutes {
            return Err(invalid("wage settlement cannot move the formal clock backwards"));
        }
        let mut due: Vec<_> = self.claims.iter_mut().filter(|(_, claim)| {
            claim.due_day <= clock.current_day() && claim.amount > claim.paid && !manual_wind_down(&claim.employer)
        }).collect();
        due.sort_by(|(id_a, a), (id_b, b)| {
            (a.work_day, &a.worker, &a.job, id_a).cmp(&(b.work_day, &b.worker, &b.job, id_b))
        });
        let mut payments = 0;
        for (id, claim) in due {
            let payer = ledger.account_for(&claim.employer, &claim.denomination)
                .filter(|account| account.account_id == claim.from).ok_or_else(|| invalid("wage payer account changed"))?;
            let amount = (claim.amount - claim.paid).min(payer.available);
            if amount > 0 {
                let transaction = format!("r1:wage:{id}:{}", claim.paid);
                ledger.transfer(&transaction, &claim.from, &claim.to, amount, minute, "wage", id)?;
                claim.paid += amount;
                payments += 1;
            }
        }
        self.through = clock;
        Ok(payments)
    }
}

fn string<'a>(row: &'a [Value], key: &str) -> io::Result<&'a str> {
    field(row, key)?.as_str().filter(|value| !value.is_empty()).ok_or_else(|| invalid("missing wage or work identity"))
}

fn currency(row: &[Value]) -> io::Result<&str> {
    lookup(row, "denomination").map_or(Ok(CURRENCY), |_| string(row, "denomination"))
}

fn indexed(value: &Value) -> io::Result<BTreeMap<&str, &[Value]>> {
    let mut rows = BTreeMap::new();
    for pair in map(value)? {
        let id = pair[0].as_str().ok_or_else(|| invalid("invalid work history ID"))?;
        if rows.insert(id, map(&pair[1])?).is_some() {
            return Err(invalid("duplicate work history ID"));
        }
    }
    Ok(rows)
}

fn accepted<'a>(commands: &BTreeMap<&str, &'a [Value]>, id: &str, actor: &str) -> io::Result<(&'a [Value], &'a [Value])> {
    let entry = commands.get(id).ok_or_else(|| invalid("missing accepted work history"))?;
    let envelope = map(field(entry, "envelope")?)?;
    let outcome = map(field(entry, "result")?)?;
    let command = map(field(envelope, "command")?)?;
    if string(envelope, "actor")? != actor || string(command, "action_id")? != id
        || field(outcome, "accepted")?.as_bool() != Some(true)
    {
        return Err(invalid("work history action was not accepted for this worker"));
    }
    Ok((command, outcome))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restored_wage_matures_and_pays_from_spendable_cash_without_repeating() {
        const EMPLOYER: &str = "firm:opening_paris_workshop";
        const PAYER: &str = "account:firm:opening_paris_workshop";
        const WORKER: &str = "person:formal_generated_country_fra_0001";
        const RECIPIENT: &str = "account:personal:formal_generated_country_fra_0001";
        const WORK: &str = "work:1:person:formal_generated_country_fra_0001";
        let seed = Ledger::initialize_people([(WORKER, 2500)]).unwrap().snapshot();
        let mut fields = map(&seed).unwrap().to_vec();
        let accounts = fields.iter_mut().find(|entry| entry[0] == "accounts").unwrap()[1][1].as_array_mut().unwrap();
        accounts.push(typed_map([
            ("account_id", json!(PAYER)), ("owner_id", json!(EMPLOYER)), ("denomination", json!(CURRENCY)),
            ("role", json!("r1_firm")), ("balance", typed_int(0)),
        ]));
        fields.push(json!(["r1_reservations", typed_map::<&str>([])]));
        let mut ledger = Ledger::restore(&json!(["map", fields]), true).unwrap();
        ledger.transfer("working_capital:1", RECIPIENT, PAYER, 6, 0, "goods", "order:1").unwrap();
        ledger.reserve("order:2", PAYER, 4).unwrap();
        let job = "job:opening_paris_workshop";
        let action = "action:work:1";
        let mut native = typed_map([
            ("day", typed_int(1)),
            ("config", typed_map([("jobs", json!(["array", [typed_map([
                ("id", json!(job)), ("employer", json!(EMPLOYER)), ("hours", typed_int(2)),
                ("wage_per_hour", typed_int(3)), ("wage_delay", typed_int(1)),
            ])]]))])),
            ("wages", typed_map([(WORK, typed_map([
                ("id", json!(WORK)), ("worker", json!(WORKER)), ("employer", json!(EMPLOYER)),
                ("work_day", typed_int(1)), ("due_day", typed_int(2)), ("hours", typed_int(2)),
                ("amount", typed_int(6)), ("paid", typed_int(0)), ("remaining", typed_int(6)),
            ]))])),
            ("work_records", typed_map([(WORK, typed_map([
                ("actor", json!(WORKER)), ("day", typed_int(1)), ("hours", typed_int(2)),
                ("job", json!(job)), ("action_id", json!(action)),
            ]))])),
            ("commands", typed_map([(action, typed_map([
                ("envelope", typed_map([("actor", json!(WORKER)), ("command", typed_map([
                    ("action_id", json!(action)), ("kind", json!("work")), ("minute", typed_int(0)),
                    ("payload", typed_map([("hours", typed_int(2))])),
                ]))])),
                ("result", typed_map([("accepted", json!(true))])),
            ]))])),
        ]);
        let mut clock = GameClock::default();
        clock.advance_minutes(MINUTES_PER_DAY).unwrap();
        let mut wages = WageClaims::restore(&native, &ledger, clock).unwrap();
        assert_eq!(wages.settle_due(&mut ledger, clock, |_| false).unwrap(), 0);
        clock.advance_minutes(MINUTES_PER_DAY).unwrap();
        assert_eq!(wages.settle_due(&mut ledger, clock, |firm| firm == EMPLOYER).unwrap(), 0);
        assert_eq!(wages.settle_due(&mut ledger, clock, |_| false).unwrap(), 1);
        assert_eq!(ledger.default_account(WORKER).unwrap().cash, 2496);
        assert_eq!(wages.open_count(), 1);

        for field in native[1].as_array_mut().unwrap() {
            match field[0].as_str().unwrap() {
                "day" => field[1] = typed_int(2),
                "wages" => field[1] = wages.snapshot(),
                _ => (),
            }
        }
        let mut ledger = Ledger::restore(&ledger.snapshot(), true).unwrap();
        let mut wages = WageClaims::restore(&native, &ledger, clock).unwrap();
        assert_eq!(wages.settle_due(&mut ledger, clock, |_| false).unwrap(), 0);
        ledger.release("order:2", 4).unwrap();
        assert_eq!(wages.settle_due(&mut ledger, clock, |_| false).unwrap(), 1);
        assert_eq!(ledger.default_account(WORKER).unwrap().cash, 2500);
        assert_eq!(wages.open_count(), 0);
        assert_eq!(wages.settle_due(&mut ledger, clock, |_| false).unwrap(), 0);
    }
}
