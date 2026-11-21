use super::{minute_text, place_label, work_action};
use serde_json::{json, Value};
use std::io;
use wwo_map_lab::formal_bootstrap::{
    organization_registration::{Organization, OrganizationKind, OrganizationRole},
    InitialWorld,
};

pub(super) fn accessible(world: &InitialWorld, org: &Organization, drawer: &str) -> bool {
    match drawer {
        "local" => world.player_current_place() == Some(org.place.as_str()),
        "relations" => world.player_organization_role(&org.id).is_some(),
        _ => false,
    }
}

pub(super) fn directory(world: &InitialWorld, drawer: &str) -> Vec<Value> {
    world
        .organizations()
        .filter(|org| accessible(world, org, drawer))
        .map(|org| {
            let role = world.player_organization_role(&org.id);
            json!({"id":org.id, "label":org.name, "kind":org.kind.label(),
            "role":role.map_or("当地可接触", |role| role.label()),
            "place":place_label(world, &org.place), "basis":org.basis})
        })
        .collect()
}

fn section(title: &str, details: Vec<String>, actions: Vec<Value>) -> Value {
    json!({"label":title, "details":details, "actions":actions})
}

fn person_name(world: &InitialWorld, person: &str) -> String {
    if person == world.player().id {
        return "本人".into();
    }
    if let Some(org) = world.organization(person) {
        return org.name.clone();
    }
    world
        .person_profile(person)
        .map(|view| view.name)
        .unwrap_or_else(|_| person.into())
}

pub(super) fn details(world: &InitialWorld, org: &Organization) -> Vec<Value> {
    let role = world.player_organization_role(&org.id);
    let local = world.player_current_place() == Some(org.place.as_str());
    let manager = world.organization_can_manage(&org.id, &world.player().id);
    let mut rows = Vec::new();
    let public = format!("{} · {}", org.kind.label(), place_label(world, &org.place));
    let status = role.map_or_else(
        || "当地公开信息".into(),
        |role| format!("本人职务 · {}", role.label()),
    );
    rows.push(section(&public, vec![status, org.basis.into()], vec![]));

    if let Some((job, booked, _)) = world.employment().filter(|(_, _, id)| *id == org.id) {
        rows.push(section(
            "我的劳动合同",
            vec![
                format!(
                    "每班 {} 小时 · 时薪 {} · {} 日后发薪",
                    job.hours, job.wage_per_hour, job.wage_delay
                ),
                if booked {
                    "本日已登记工作"
                } else {
                    "本日未登记工作"
                }
                .into(),
            ],
            vec![
                work_action("登记工作", "native:work", world.can_book_work()),
                work_action("离职", "native:leave_employment", !booked),
            ],
        ));
    } else if local && world.employment().is_none() {
        for (job, vacancies) in world.jobs().filter(|(job, _)| org.jobs.contains(&job.id)) {
            rows.push(section(
                "招聘岗位",
                vec![format!(
                    "空缺 {vacancies} · 每班 {} 小时 · 时薪 {} · {} 日后发薪",
                    job.hours, job.wage_per_hour, job.wage_delay
                )],
                vec![work_action(
                    "申请岗位",
                    &format!("person:job_request:{}", job.id),
                    vacancies > 0,
                )],
            ));
        }
    }

    if let Some(amount) = world.organization_partnership_offer(&org.id) {
        rows.push(section(
            "经营合伙",
            vec![format!("向企业账户实缴 {amount}，成为经营合伙人。")],
            vec![work_action(
                &format!("出资 {amount} 并签约"),
                "organization:invest",
                true,
            )],
        ));
    }
    if matches!(org.kind, OrganizationKind::MutualAid) && local {
        let mut actions = Vec::new();
        if world.can_join_local_association(&org.id) {
            actions.push(work_action("申请入会", "organization:join", true));
        }
        if matches!(role, Some(OrganizationRole::Member)) {
            actions.push(work_action("退会", "organization:leave", true));
        }
        let available = world.available_job_referral(&org.id).is_some();
        if available {
            actions.push(work_action("请人介绍工作", "organization:referral", true));
        }
        let notice = if available {
            "联络人有可介绍的当地空缺。"
        } else {
            "当前没有可为本人介绍的空缺。"
        };
        rows.push(section("会员与工作介绍", vec![notice.into()], actions));
    }
    if manager {
        if let Some((grain, bread)) = world.organization_site_goods(&org.id) {
            rows.push(section(
                "站点库存",
                vec![format!("粮食 {grain} · 面包 {bread}")],
                vec![],
            ));
        }
        if let Some(balance) = org
            .firm
            .as_deref()
            .and_then(|firm| world.ledger().default_account(firm))
        {
            let mut actions: Vec<_> = [100, 1000]
                .into_iter()
                .filter(|amount| world.can_contribute_to_business(&org.id, *amount))
                .map(|amount| {
                    work_action(
                        &format!("追加 {amount} 生丁"),
                        &format!("organization:capital|{amount}"),
                        true,
                    )
                })
                .collect();
            if world
                .freight_lots()
                .any(|lot| Some(lot.owner()) == org.firm.as_deref())
            {
                actions.push(work_action("实物货运", "organization:freight_page", true));
            }
            rows.push(section(
                "企业账户",
                vec![format!(
                    "现金 {} · 可用 {} · 预留 {}",
                    balance.cash, balance.available, balance.reserved
                )],
                actions,
            ));
        }
    }
    for member in world.organization_members(&org.id) {
        let contact = matches!(member.role, OrganizationRole::Coordinator);
        if role.is_none() && !contact {
            continue;
        }
        let title = if contact { "联络人" } else { "组织成员" };
        rows.push(section(
            title,
            vec![format!(
                "{} · {}",
                person_name(world, member.person),
                member.role.label()
            )],
            vec![],
        ));
    }
    if manager {
        for good in &org.goods {
            let (name, _, unit) = world
                .macro_economy()
                .commodity_info(good)
                .unwrap_or((good, "", ""));
            let mut terms = Vec::new();
            let mut actions = Vec::new();
            let mut previous = None;
            for (label, requested) in [("小批", None), ("整批", Some(1000))] {
                let Some((amount, price, total)) =
                    world.organization_freight_offer(&org.id, good, requested)
                else {
                    continue;
                };
                if previous == Some(amount) {
                    continue;
                }
                previous = Some(amount);
                terms.push(format!(
                    "{label} · {} {unit} · {total} 生丁",
                    amount as f64 / 1000.
                ));
                actions.push(work_action(
                    &format!("购入{label}"),
                    &format!("organization:freight|{good}|{amount}|{price}"),
                    true,
                ));
            }
            if !actions.is_empty() {
                rows.push(section(&format!("企业货批 · {name}"), terms, actions));
            }
        }
    }
    for relation in world.organization_relations(&org.id) {
        rows.push(section("业务往来", vec![relation], vec![]));
    }
    if let Some(status) = world.counter_status(&org.id) {
        let open = world.counter_open(&org.id);
        let actions = if manager {
            vec![work_action(
                if open { "暂停接单" } else { "恢复接单" },
                if open {
                    "organization:close"
                } else {
                    "organization:open"
                },
                local,
            )]
        } else {
            vec![]
        };
        rows.push(section(
            "代购柜台",
            vec![
                status,
                "顾客预约后预留款项，有工时和货源时于日结交付。".into(),
            ],
            actions,
        ));
        if local {
            for good in &org.goods {
                if let Some(offer) = world.organization_counter_offer(&org.id, good) {
                    let total = offer.goods_centimes + offer.service_centimes;
                    let (name, _, unit) = world.macro_economy().commodity_info(good).unwrap_or((
                        good.as_str(),
                        "",
                        "",
                    ));
                    let quantity = offer.quantity_milli as f64 / 1000.;
                    rows.push(section(
                        name,
                        vec![format!(
                            "{quantity} {unit} · 货款 {} 生丁 · 代办费 {} 生丁",
                            offer.goods_centimes, offer.service_centimes
                        )],
                        vec![work_action(
                            &format!("预约 · {total} 生丁"),
                            &format!("organization:order|{good}|{total}"),
                            true,
                        )],
                    ));
                }
            }
        }
    }

    for event in world.organization_events(&org.id).rev().take(12) {
        rows.push(section(
            event.action.label(),
            vec![
                format!(
                    "{} 至 {}",
                    minute_text(event.start_minute),
                    minute_text(event.end_minute)
                ),
                format!(
                    "{} → {}",
                    person_name(world, &event.initiator),
                    person_name(world, &event.target)
                ),
                format!("原因 · {}", event.reason),
                format!("资源 · {}", event.resources),
                format!("结果 · {}", event.result),
                format!("影响 · {}", event.consequence),
            ],
            vec![],
        ));
    }
    rows
}

pub(super) fn act(world: &mut InitialWorld, id: &str, action: &str) -> io::Result<String> {
    match action {
        "organization:join" => {
            world.join_local_association(id)?;
            Ok("已成为会员。".into())
        }
        "organization:leave" => {
            world.leave_local_association(id)?;
            Ok("已退出协会。".into())
        }
        "organization:invest" => {
            world.accept_organization_partnership(id)?;
            Ok("出资已入账，经营合伙已生效。".into())
        }
        "organization:open" | "organization:close" => {
            let open = action == "organization:open";
            world.set_counter_open(id, open)?;
            Ok(if open {
                "柜台已恢复接单。"
            } else {
                "柜台已暂停接单。"
            }
            .into())
        }
        "organization:referral" => {
            let job = world.request_job_referral(id)?;
            let employer = world
                .jobs()
                .find(|(row, _)| row.id == job)
                .map(|(row, _)| super::employer_label(world, &row.employer).to_owned())
                .unwrap_or(job);
            Ok(format!("已获工作介绍 · {employer}。可在招聘岗位申请。"))
        }
        _ => {
            if let Some(amount) = action.strip_prefix("organization:capital|") {
                let amount = amount
                    .parse()
                    .map_err(|_| io::Error::other("出资额无效。"))?;
                world.contribute_to_business(id, amount)?;
                return Ok(format!("已从本人账户向企业追加 {amount} 生丁。"));
            }
            let (good, total) = action
                .strip_prefix("organization:order|")
                .and_then(|value| value.rsplit_once('|'))
                .ok_or_else(|| io::Error::other("无法识别组织操作。"))?;
            let total = total.parse().map_err(|_| io::Error::other("报价无效。"))?;
            let reserved = world.order_at_counter(id, good, total)?;
            Ok(format!("已预约代购，预留 {reserved} 生丁。"))
        }
    }
}

pub(super) fn buy_freight(world: &mut InitialWorld, id: &str, quote: &str) -> io::Result<u64> {
    let (item, price) = quote
        .rsplit_once('|')
        .ok_or_else(|| io::Error::other("报价无效。"))?;
    let (good, amount) = item
        .rsplit_once('|')
        .ok_or_else(|| io::Error::other("货批数量无效。"))?;
    let amount = amount.parse().map_err(|_| io::Error::other("货批数量无效。"))?;
    let price = price.parse().map_err(|_| io::Error::other("报价无效。"))?;
    world.buy_organization_freight(id, good, amount, price)
}
