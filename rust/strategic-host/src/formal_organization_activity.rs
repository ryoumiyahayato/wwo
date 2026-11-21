use super::{
    organization_registration::OrganizationKind,
    InitialWorld,
};
use crate::{
    formal_clock::{GameClock, MINUTES_PER_DAY},
    formal_enterprise::MaterialOrder,
    formal_save::invalid,
    formal_work::Job,
};
use serde::{Deserialize, Serialize};
use std::{cmp::Reverse, collections::BTreeSet, io};

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct OrganizationActivity {
    pending: Vec<MaterialOrder>,
    events: Vec<OrganizationEvent>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OrganizationEvent {
    pub organization: String,
    pub initiator: String,
    pub target: String,
    pub reason: String,
    pub action: String,
    pub resources: String,
    pub result: String,
    pub consequence: String,
    pub start_minute: i64,
    pub end_minute: i64,
}

impl OrganizationActivity {
    fn record(&mut self, event: OrganizationEvent) {
        // Keep the latest occurrence of each actual interaction. Receipts, employment and
        // deliveries retain their authoritative histories in their respective components.
        self.events.retain(|old| !(old.organization == event.organization && old.initiator == event.initiator
            && old.action == event.action && old.target == event.target
            && (event.action != "介绍就业" || old.resources == event.resources)));
        self.events.push(event);
    }
}

impl InitialWorld {
    pub fn organization_events<'a>(&'a self, organization: &'a str) -> impl DoubleEndedIterator<Item = &'a OrganizationEvent> {
        let manager = self.organization_can_manage(organization, &self.player);
        let firm = self.organization(organization).and_then(|org| org.firm.as_deref());
        self.activity.events.iter().filter(move |event| (event.organization == organization || event.target == organization)
            && (manager || event.initiator == self.player || event.target == self.player
                || (event.action == "原料交割" && firm.is_some_and(|firm| self.worked_at(firm, event.end_minute)))))
    }

    pub fn organization_site_goods(&self, organization: &str) -> Option<(i64, i64)> {
        if !self.organization_can_manage(organization, &self.player) { return None; }
        let firm = self.organization(organization)?.firm.as_deref()?;
        self.enterprises.site_goods(&self.enterprise_opening, firm)
    }

    pub fn organization_relations(&self, organization: &str) -> Vec<String> {
        let Some(org) = self.organization(organization) else { return Vec::new() };
        let manager = self.organization_can_manage(organization, &self.player);
        let local = self.player_current_place() == Some(&org.place);
        let mut relations = Vec::new();
        for other in self.organizations() {
            if other.id == org.id { continue; }
            let (office, employer) = if org.kind == OrganizationKind::MutualAid { (org, other) } else { (other, org) };
            if office.kind == OrganizationKind::MutualAid && self.activity.events.iter().any(|e| e.action == "介绍就业"
                && e.organization == office.id && employer.jobs.contains(&e.resources)
                && (manager || local || e.target == self.player)) {
                relations.push(format!("{}与{}有实际岗位介绍记录。相同工资条件下优先介绍已联系的岗位。", office.name, employer.name));
            }
            let (Some(firm), Some(counterparty)) = (org.firm.as_deref(), other.firm.as_deref()) else { continue };
            for (buyer, seller, direction) in [(firm, counterparty, "购入"), (counterparty, firm, "售出")] {
                let (count, grain) = self.enterprises.delivered_grain(buyer, seller);
                if count > 0 && (manager || self.enterprises.witnessed_delivery(firm, counterparty, &self.player, &self.wages)) {
                    let terms = if self.enterprises.established_supplier(&self.enterprise_opening, buyer, seller, self.clock.current_day())
                        { "可在本班续订" } else { "再次订货须等候供方确认" };
                    if manager {
                        relations.push(format!("与{}现场交割 {count} 次，{direction}粮食 {grain}。{terms}。", other.name));
                    } else {
                        relations.push(format!("当班见过与{}的粮食交割。{terms}。", other.name));
                    }
                }
            }
            for (winner, rival, outcome) in [(firm, counterparty, "本方成交"), (counterparty, firm, "对方成交")] {
                if let Some(sale) = self.enterprises.contested_sale(winner, rival) {
                    if manager {
                        relations.push(format!("与{}竞争当地面包订单，{outcome}，实收 {}。", other.name, sale.amount));
                    } else if self.worked_at(firm, sale.minute) {
                        relations.push(format!("当班时与{}同时供应面包，{outcome}。", other.name));
                    } else if local {
                        relations.push(format!("{}与{}在此地供应同一面包订单，最终由{outcome}。", org.name, other.name));
                    }
                }
            }
        }
        relations
    }

    fn worked_at(&self, firm: &str, minute: i64) -> bool {
        self.wages.completed_firm_work(firm, minute / MINUTES_PER_DAY).iter().any(|work| work.worker == self.player)
    }

    pub(crate) fn settle_organization_activity(&mut self, boundary: GameClock) -> io::Result<()> {
        let day = boundary.current_day();
        for order in std::mem::take(&mut self.activity.pending) {
            self.complete_material_order(&order, boundary)?;
        }
        for order in self.enterprises.material_requests(&self.enterprise_opening, &self.wages, day) {
            let buyer = self.work_opening.organization(&order.buyer).ok_or_else(|| invalid("采购方组织缺失"))?;
            let seller = self.work_opening.organization(&order.seller).ok_or_else(|| invalid("供方组织缺失"))?;
            let start = self.work.booking(&order.worker).unwrap_or(boundary.snapshot().total_minutes);
            let end = self.work.contract(&self.work_opening, &order.worker).map_or(start, |job| start + job.hours * 60);
            let established = self.enterprises.established_supplier(&self.enterprise_opening, &order.buyer, &order.seller, day);
            self.activity.record(OrganizationEvent {
                organization: buyer.into(), initiator: order.worker.clone(), target: seller.into(),
                reason: "本站余粮低于实际在岗班次在计划期内的用量，已知供货消息到达".into(), action: "原料采购申请".into(),
                resources: format!("粮食 {}；企业原有采购授权", order.quantity),
                start_minute: start, end_minute: end, result: "采购方已向获授权的当地供方下单".into(),
                consequence: if established { "已有现场交割记录，可在本班向同一供应商续订" }
                    else { "新接洽或中断后的采购等候供方次日确认" }.into(),
            });
            if established { self.complete_material_order(&order, boundary)?; }
            else { self.activity.pending.push(order); }
        }
        Ok(())
    }

    fn complete_material_order(&mut self, order: &MaterialOrder, boundary: GameClock) -> io::Result<()> {
        let buyer = self.work_opening.organization(&order.buyer).ok_or_else(|| invalid("采购方组织缺失"))?;
        let seller = self.work_opening.organization(&order.seller).ok_or_else(|| invalid("供方组织缺失"))?;
        let outcome = self.enterprises.deliver_material(&self.enterprise_opening, &mut self.ledger, order, boundary.current_day());
        let (result, consequence) = match outcome {
            Ok((quantity, _)) => (format!("已当场交粮 {quantity}，货款结清"),
                "收货站点可在下一班投产。双方剩余交接能力与累计授权数量已扣减。".into()),
            Err(error) => {
                self.enterprises.interrupt_supply(order, boundary.current_day());
                (error.to_string(), "本次订单未成交。下次采购需重办供方确认。".into())
            }
        };
        self.activity.record(OrganizationEvent {
            organization: buyer.into(), initiator: order.worker.clone(), target: seller.into(),
            reason: "生产岗位报告实际原料缺口，企业执行既有采购授权".into(), action: "原料交割".into(),
            resources: format!("申请粮食 {}；双方须有在岗交接能力，采购方须能支付", order.quantity),
            start_minute: order.day * MINUTES_PER_DAY, end_minute: boundary.snapshot().total_minutes,
            result, consequence,
        });
        Ok(())
    }

    pub(crate) fn can_take_organization_job(&self, person: &str, job: &Job) -> bool {
        let Some(id) = self.work_opening.organization(&job.employer) else { return false };
        !self.organization_can_manage(id, person)
            && (self.enterprise_opening.has_firm(&job.employer) || self.merchant_needs_worker(&job.employer))
    }

    fn employer_current(&self, person: &str, job: &Job) -> bool {
        !self.work_opening.refuses_arrears(person, || self.wages.oldest_unpaid_day(person, &job.employer), self.clock.current_day())
    }

    fn referral_for(&self, organization: &str, person: &str) -> Option<(String, String)> {
        let association = self.organization(organization)?;
        if !matches!(association.kind, OrganizationKind::MutualAid) || self.current_place(person)? != association.place
            || self.work.has_contract(person) || !self.eligible_for_civil_work(person) { return None; }
        let coordinator = self.active_coordinator(organization).filter(|id| *id != person)?;
        let job = self.work_opening.entry_jobs_at(&association.place).filter(|job| {
            self.work.vacancies(job) > 0 && self.can_take_organization_job(person, job) && self.employer_current(person, job)
        }).max_by_key(|job| (job.wage_per_hour, self.previously_referred(organization, &job.id), Reverse(&job.id)))?;
        (self.person_profile(person).ok()?.age_years >= 18).then(|| (coordinator.into(), job.id.clone()))
    }

    fn previously_referred(&self, organization: &str, job: &str) -> bool {
        self.activity.events.iter().any(|e| e.action == "介绍就业" && e.organization == organization && e.resources == job)
    }

    fn record_referral(&mut self, organization: &str, person: &str, coordinator: String, job: String) -> String {
        let minute = self.clock.snapshot().total_minutes;
        self.work.learn_referral(person, &job, self.clock.current_day());
        self.activity.record(OrganizationEvent {
            organization: organization.into(), initiator: coordinator, target: person.into(), action: "介绍就业".into(),
            reason: "用人组织有当地入门空缺，求职者可以在场申请".into(), resources: job.clone(),
            start_minute: minute, end_minute: minute, result: "求职者已获知岗位与合同条件".into(),
            consequence: "求职者可向用人组织应聘；获聘后按实际班次结算工资".into(),
        });
        job
    }

    pub fn available_job_referral(&self, organization: &str) -> Option<String> {
        self.referral_for(organization, &self.player).map(|(_, job)| job)
    }

    pub fn request_job_referral(&mut self, organization: &str) -> io::Result<String> {
        let (coordinator, job) = self.referral_for(organization, &self.player)
            .ok_or_else(|| invalid("当前无法当面介绍可申请的本地空缺。"))?;
        Ok(self.record_referral(organization, &self.player.clone(), coordinator, job))
    }

    pub(crate) fn settle_organization_employment(&mut self) -> io::Result<()> {
        let offices: Vec<_> = self.organizations().filter(|org| matches!(org.kind, OrganizationKind::MutualAid))
            .map(|org| (org.id.clone(), org.place.clone())).collect();
        let officers: BTreeSet<_> = self.appointed_officers().collect();
        let jobseekers = self.referral_members().chain(self.work_opening.automatic()).collect::<BTreeSet<_>>();
        let candidates: Vec<_> = jobseekers.into_iter().filter(|&person| person != self.player && !officers.contains(person)
            && self.eligible_for_civil_work(person) && self.work.booking(person).is_none() && self.population.unit_for_person(person).is_some())
            .map(str::to_owned).collect();
        for person in candidates {
            let Some(place) = self.current_place(&person).map(str::to_owned) else { continue };
            if self.clock.current_day() == 0 && self.player_current_place() == Some(place.as_str()) { continue; }
            if let Some(job) = self.work.contract(&self.work_opening, &person) {
                if !self.employer_current(&person, job) { self.work.release(&person)?; }
            }
            if !self.work.has_contract(&person) {
                if let Some((office, _)) = offices.iter().find(|(_, town)| *town == place) {
                    if let Some((coordinator, job)) = self.referral_for(office, &person) {
                        if !self.work.has_referral(&person, &job) { self.record_referral(office, &person, coordinator, job); }
                    }
                }
                let job = self.work.local_jobs(&self.work_opening, &person, Some(&place), self.clock.current_day())
                    .filter(|job| self.work.vacancies(job) > 0 && self.can_take_organization_job(&person, job)
                        && self.employer_current(&person, job) && self.work.ready_to_apply(&self.work_opening, &person, job, self.clock.current_day()))
                    .max_by_key(|job| (job.wage_per_hour, Reverse(&job.id))).map(|job| job.id.clone());
                if let Some(job) = job { self.apply_for_work_as(&person, &job)?; }
            }
            if self.work.contract(&self.work_opening, &person).is_some_and(|job| self.can_take_organization_job(&person, job))
                && self.work.can_book(&self.work_opening, &person, Some(&place), self.clock) {
                self.book_work_as(&person)?;
            }
        }
        Ok(())
    }

    pub(crate) fn validate_organization_activity(&self) -> io::Result<()> {
        let day = self.clock.current_day();
        let minute = self.clock.snapshot().total_minutes;
        let expected = self.enterprises.material_requests(&self.enterprise_opening, &self.wages, day);
        let mut pending_buyers = BTreeSet::new();
        if !self.enterprises.validate_sales(&self.enterprise_opening, &self.ledger, minute)
            || !self.enterprises.validate_orders(&self.enterprise_opening, &self.ledger, &self.wages, day)
            || !self.activity.pending.iter().all(|order| pending_buyers.insert(&order.buyer)
                && expected.iter().any(|candidate| candidate == order))
            || !self.activity.events.iter().all(|e| (0..=minute).contains(&e.start_minute)
                && (e.start_minute..=minute).contains(&e.end_minute) && self.organization(&e.organization).is_some()
                && self.person(&e.initiator).is_some() && (self.person(&e.target).is_some() || self.organization(&e.target).is_some())
                && [&e.reason, &e.resources, &e.result, &e.consequence].iter().all(|s| !s.is_empty() && s.len() <= 1024)
                && matches!(e.action.as_str(), "原料采购申请" | "原料交割" | "介绍就业")) {
            return Err(invalid("组织活动、原料交割或招聘消息与正式记录不符。"));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_bootstrap::WorldBootstrap, transport::ModeSet};
    use std::collections::BTreeMap;

    #[test]
    fn organization_activity_remote_firms_trade_compete_and_continue_after_restore() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("british_isles_1900").unwrap();
        let baker = "firm:opening_paris_bakery";
        let supplier = "firm:opening_paris_workshop";
        world.advance_migrated_domains(23 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some("place:london"));
        assert_eq!(world.activity.pending.len(), 1);
        let mut world = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        world.advance_migrated_domains(3 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        let (deliveries, quantity) = world.enterprises.delivered_grain(baker, supplier);
        assert!(deliveries >= 2 && quantity >= deliveries as i64);
        assert!(world.enterprises.contested_sale(baker, supplier).is_some() || world.enterprises.contested_sale(supplier, baker).is_some());
        let org = "organization:opening_paris_workshop";
        assert!(world.organization_relations(org).is_empty());
        let arrival = world.preview_travel("place:paris", ModeSet::ALL).unwrap().arrival_minute();
        world.depart_player().unwrap();
        world.advance_migrated_domains(arrival - world.clock.snapshot().total_minutes, &BTreeMap::new()).unwrap();
        let relations = world.organization_relations(org);
        assert!(relations.iter().any(|line| line.contains("面包订单")));
        assert!(relations.iter().any(|line| line.contains("岗位介绍")));
        assert!(world.organization_site_goods(org).is_none());
        let restored = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        assert_eq!(restored.organization_relations(org), relations);
    }

    #[test]
    fn organization_activity_local_referral_changes_job_knowledge_and_respects_employee_permissions() {
        use wwo_character_core::{Education, Family, Prologue, Temperament, Youth};
        let bootstrap = WorldBootstrap::load().unwrap();
        let opening = Prologue { age: 18, family: Family::Poor, education: Education::HomeWork,
            youth: Youth::Apprentice, temperament: Temperament::Practice };
        let mut world = bootstrap.create_with_prologue("country_fra", opening).unwrap();
        let job = "job:opening_paris_workshop";
        let firm = "organization:opening_paris_workshop";
        let office = "organization:opening_paris_association";
        assert!(world.apply_for_work(job).is_err());
        assert_eq!(world.request_job_referral(office).unwrap(), job);
        assert!(!world.can_read_opening_language());
        world.apply_for_work(job).unwrap();
        world.book_work().unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert_eq!(world.completed_firm_work("firm:opening_paris_workshop", 1).unwrap()[0].worker, world.player);
        assert!(world.organization_relations(office).iter().any(|line| line.contains("岗位介绍")));
        assert!(world.organization_site_goods(firm).is_none());
        assert!(!world.organization_can_manage(firm, &world.player));
        world.advance_migrated_domains(22 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert!(world.organization_events(firm).all(|e| e.action != "原料交割"));
        world.book_work().unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        let handover = world.organization_events(firm).find(|e| e.action == "原料交割").unwrap();
        assert!(handover.result.contains("已当场交粮"));
        assert!(world.organization_relations(firm).iter().any(|line| line.contains("当班见过")));
        assert!(world.organization_site_goods(firm).is_none());
    }
}
