use crate::formal_save::{field, integer, invalid, lookup, map, tagged};
use serde_json::{json,Value};
use std::io;

const SELLER:&str="cohort:opening:rouen_farm";
const GOOD:&str="grain";
const MAX:i64=9_007_199_254_740_991;

pub(crate) fn buy(snapshot:&mut Value, quantity:i64, request:&str)->io::Result<String> {
    if !(1..=1_000_000).contains(&quantity) || request.is_empty() || request.len()>128 {return Err(invalid("invalid quantity or purchase request ID"));}
    let world=map(snapshot)?;
    let minute=integer(field(world,"total_minutes")?)?;
    let player=str_value(map(field(world,"player")?)?,"player_id")?.to_owned();
    let economy=map(field(world,"economy_native")?)?;
    let commands=map(field(economy,"commands")?)?;
    let native_id=format!("life:{}",integer(field(map(field(world,"personal_economy")?)?,"next_record_sequence")?)?);
    if let Some(command)=lookup(commands,request) {
        let envelope=map(field(map(command)?,"envelope")?)?;
        let command=map(field(envelope,"command")?)?;
        let payload=map(field(command,"payload")?)?;
        if integer(field(payload,"quantity")?)?!=quantity{return Err(invalid("purchase request already used with a different quantity"));}
        let order=tagged(field(economy,"orders")?,"map")?.iter().find_map(|pair|{
            let row=map(&pair[1]).ok()?;
            (str_value(row,"action_id").ok()==Some(request)).then(||pair[0].as_str()).flatten()
        }).ok_or_else(||invalid("accepted request has no order"))?;
        return Ok(order.to_owned());
    }
    if request!=native_id {return Err(invalid(format!("expected current purchase action ID {native_id}")));}
    if lookup(world, "rust_character").is_some() {
        return Err(invalid("this maintenance action cannot update the formal character state"));
    }
    if minute!=0 || !map(field(economy,"orders")?)?.is_empty() {return Err(invalid("native purchase currently supports the first transaction in the French opening only"));}
    let config=map(field(economy,"config")?)?;
    let arrays=|key|tagged(field(config,key)?,"array");
    let actor=record(arrays("actors")?,"id",&player)?;
    let seller=record(arrays("actors")?,"id",SELLER)?;
    let producer=record(arrays("resource_producers")?,"actor",SELLER)?;
    if str_value(actor,"control")?!="player"||str_value(producer,"good")?!=GOOD{return Err(invalid("purchase has no authorized buyer or producer"));}
    let from=str_value(seller,"place_id")?.to_owned();
    let to=str_value(actor,"place_id")?.to_owned();
    let buyer=str_value(actor,"account_id")?.to_owned();
    let seller_account=str_value(seller,"account_id")?.to_owned();
    let route=arrays("routes")?.iter().filter_map(|item|map(item).ok()).find(|row| {
        str_value(row,"from_place_id").ok()==Some(from.as_str())&&str_value(row,"to_place_id").ok()==Some(to.as_str())
            &&field(row,"known_to").and_then(|v|tagged(v,"array")).is_ok_and(|ids|ids.iter().any(|id|id.as_str()==Some(&player)))
    }).ok_or_else(||invalid("no known direct route for the purchase"))?;
    let route_id=str_value(route,"id")?.to_owned();
    let candidate=format!("{SELLER}|{GOOD}|{SELLER}");
    let known=arrays("information")?.iter().filter_map(|v|map(v).ok()).any(|row| {
        str_value(row,"actor").ok()==Some(&player)&&str_value(row,"kind").ok()==Some("supplier")
            &&str_value(row,"candidate").ok()==Some(&candidate)&&field(row,"delivery_day").and_then(integer).ok()==Some(0)
    });
    if !known {return Err(invalid("seller is not known to the player"));}
    let book=map(field(economy,"unified_market")?)?;
    let offer_key=format!("{SELLER}|{GOOD}");
    let quoted_milli=integer(field(map(field(book,"asks")?)?,&offer_key)?)?;
    if quoted_milli%1000!=0{return Err(invalid("fractional offer requires the native price rule"));}
    let price=quoted_milli/1000;
    let freight=integer(field(route,"freight_per_unit")?)?;
    let delay=integer(field(route,"delay")?)?;
    let capacity=integer(field(route,"capacity")?)?;
    let cost=price.checked_add(freight).and_then(|unit|unit.checked_mul(quantity)).filter(|n|(1..=MAX).contains(n))
        .ok_or_else(||invalid("purchase amount exceeds numeric bounds"))?;
    let carrier=record(arrays("carriers")?,"id",str_value(route,"carrier")?)?;
    let carrier_account=str_value(carrier,"account_id")?.to_owned();
    let ledger=map(field(world,"ledger")?)?;
    let account=record(tagged(field(ledger,"accounts")?,"array")?,"account_id",&buyer)?;
    let currency=str_value(account,"denomination")?.to_owned();
    let available=integer(field(account,"balance")?)?;
    if available<cost{return Err(invalid("insufficient available funds"));}
    let stock=map(field(economy,"stock")?)?;
    let total=integer(field(map(field(stock,SELLER)?)?,GOOD)?)?;
    let food_reserve=integer(field(map(field(producer,"resource")?)?,"food_reserve")?)?;
    if quantity>total.saturating_sub(food_reserve).min(capacity){return Err(invalid("quantity exceeds available stock or route capacity"));}
    let number=integer(field(economy,"next_order")?)?;
    let horizon=integer(field(config,"stock_horizon")?)?.min(30);
    let order=format!("order:{number}");
    let quote=format!("quote:{minute}:{player}:{SELLER}:{GOOD}:{route_id}:{SELLER}:");
    let legs=arr(vec![object(json!({"edge_id":route_id,"delay":delay,"freight_per_unit":freight,"carrier_account":carrier_account}))]);
    let order_record=object(json!({"id":order,"kind":"SALE","seller_site":SELLER,"buyer_site":"","need_category":"",
        "buyer":player,"seller":SELLER,"good":GOOD,"quantity":quantity,"pending":quantity,"transit":0,"delivered":0,"cancelled":0,
        "price":price,"action_id":native_id,"accepted_day":0,"accepted_minute":minute,"denomination":currency,"buyer_account":buyer,
        "seller_account":seller_account,"route_id":route_id,"from_place_id":from,"to_place_id":to}));
    let command=object(json!({"envelope":{"actor":player,"command":{"action_id":native_id,"minute":minute,"kind":"buy",
        "payload":{"quote_id":quote,"seller":SELLER,"seller_site":SELLER,"good":GOOD,"quantity":quantity,"denomination":currency,
        "max_price":price,"path_id":route_id,"purpose":"HOLDING","need_category":""}}},
        "result":{"accepted":true,"reason":"ACCEPTED","order_id":order,"quantity":quantity,"price":price,"denomination":currency,
        "route_id":route_id,"seller_site":SELLER,"buyer_site":""},"source":"player"}));
    let good=record(arrays("goods")?,"id",GOOD)?;
    let sequence=integer(field(map(field(world,"personal_economy")?)?,"next_record_sequence")?)?;
    let mut livelihood=object(json!({"commodity_id":"native:grain","good":GOOD,"name_zh":GOOD,"unit_id":str_value(good,"unit_id")?,
        "unit_name_zh":str_value(good,"unit_name_zh")?,"quantity_scale":1,"sale_supported":true,"consumable":true,
        "daily_supported":true,"need_category":"food","mode":"flow","source_id":order,"order_id":order,"seller_id":SELLER,
        "seller_site":SELLER,"buyer_account_id":buyer,"seller_account_id":seller_account,"quantity":quantity,"unit_price":price,
        "freight_per_unit":freight,"denomination":currency,"amount":cost,"effective_minute":minute,
        "record_id":format!("personal_life:{sequence}"),"kind":"native_order","person_id":player}));
    put(&mut livelihood,"services",field(good,"needs")?.clone())?;

    let economy=get(snapshot,"economy_native")?;
    let mut order_record=order_record;
    put(&mut order_record,"route_legs",legs)?;
    put(get(economy,"orders")?,&order,order_record)?;
    put(get(economy,"commands")?,&native_id,command)?;
    *get(economy,"next_order")?=int(number+1);
    put(get(economy,"request_window")?,&offer_key,arr(vec![object(json!({"day":0,"buyer":player,"quantity":quantity,
        "order_id":order,"action_id":native_id,"physical_unmet":0,"cash_refused":0,"price_refused":0,"need_by_day":horizon}))]))?;
    put(get(get(economy,"unified_market")?,"requests")?,&format!("{player}|{GOOD}"),object(json!({"buyer":player,
        "region":format!("{to}|{GOOD}"),"quantity":0,"unit_cost":price+freight,"until":horizon,"budgets":{}})))?;
    put(get(get(economy,"procurement_budget")?,"claims")?,&order,arr(Vec::new()))?;
    let transport=get(get(get(economy,"transport")?,"edges")?,&route_id)?;
    put(get(transport,"holds")?,&order,object(json!({"period":0,"quantity":quantity})))?;
    *get(transport,"input_used")?=int(quantity);
    let lots=get(economy,"stock_lots")?;
    let mut next=integer(get(lots,"next_id")?)?;
    let portions=get(lots,"portions")?;
    let mut candidates=map(portions)?.iter().filter_map(|pair|{
        let p=map(&pair[1]).ok()?;
        let id=pair[0].as_str()?;
        let rem=integer(field(p,"remaining").ok()?).ok()?;
        (str_value(p,"owner").ok()==Some(SELLER)&&str_value(p,"good").ok()==Some(GOOD)&&
            str_value(p,"reserved_for").ok()==Some("")&&rem>0).then_some((id.to_owned(),rem))
    }).collect::<Vec<_>>();
    candidates.sort_by_key(|(id,_)|id.strip_prefix("portion:").and_then(|n|n.parse::<i64>().ok()).unwrap_or(i64::MAX));
    let mut left=quantity;
    for (id,remaining) in candidates {
        if left==0{break;}
        let reserve=left.min(remaining);
        let source=get(portions,&id)?;
        let mut child=source.clone();
        let moved=integer(get(source,"moved")?)?;
        *get(source,"remaining")?=int(remaining-reserve);*get(source,"moved")?=int(moved+reserve);
        if remaining==reserve{*get(source,"closed_minute")?=int(minute);}
        let new=format!("portion:{next}");next+=1;
        for (key,value) in [("id",json!(new)),("parent_portion_id",json!(id)),("quantity",int(reserve)),("remaining",int(reserve)),
            ("moved",int(0)),("lost",int(0)),("consumed",int(0)),("closed_minute",int(-1)),("opened_minute",int(minute)),("reserved_for",json!(order))] {
            *get(&mut child,key)?=value;
        }
        put(portions,&new,child)?;
        left-=reserve;
    }
    if left!=0{return Err(invalid("insufficient unlocked stock portions"));}
    *get(lots,"next_id")?=int(next);
    let reservations=get(get(snapshot,"ledger")?,"r1_reservations")?;
    put(reservations,&order,object(json!({"account_id":buyer,"amount":cost})))?;
    let personal=get(snapshot,"personal_economy")?;
    let records=get(get(personal,"living_records")?,&player)?;
    records[1].as_array_mut().ok_or_else(||invalid("invalid personal living records"))?.push(livelihood);
    *get(personal,"next_record_sequence")?=int(sequence+1);
    Ok(order)
}

fn record<'a>(rows:&'a [Value],key:&str,want:&str)->io::Result<&'a [Value]> {
    rows.iter().filter_map(|v|map(v).ok()).find(|row|str_value(row,key).ok()==Some(want))
        .ok_or_else(||invalid(format!("missing record {want}")))
}
fn str_value<'a>(row:&'a [Value],key:&str)->io::Result<&'a str>{field(row,key)?.as_str().ok_or_else(||invalid(format!("expected string {key}")))}
fn int(n:i64)->Value{json!(["int",n.to_string()])}
fn arr(v:Vec<Value>)->Value{json!(["array",v])}
fn object(v:Value)->Value { match v {
    Value::Object(fields)=>json!(["map",fields.into_iter().map(|(k,v)| json!([k,object(v)])).collect::<Vec<_>>()]),
    Value::Array(values)=>arr(values.into_iter().map(object).collect()),
    Value::Number(n)=>int(n.as_i64().unwrap()),
    other=>other,
}}
fn get<'a>(v:&'a mut Value,key:&str)->io::Result<&'a mut Value>{
    let entries=v[1].as_array_mut().ok_or_else(||invalid("invalid mutable transfer map"))?;
    entries.iter_mut().find(|p|p[0].as_str()==Some(key)).map(|p|&mut p[1]).ok_or_else(||invalid(format!("missing {key}")))
}
fn put(v:&mut Value,key:&str,value:Value)->io::Result<()> {
    if lookup(map(v)?,key).is_some(){return Err(invalid(format!("duplicate {key}")));}
    v[1].as_array_mut().unwrap().push(json!([key,value]));Ok(())
}
