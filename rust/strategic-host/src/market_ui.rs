use crate::{formal_ui::{Command,Display,BRASS,IVORY,MUTED},overlay::Mesh,ui::{Action,Hit}};
use serde::Deserialize;

pub(crate) const GOODS_GROUPS: [(&str, &str); 4] = [
    ("all", "全部"),
    ("谷物、薯类与干豆", "粮食"),
    ("工业制品", "工业品"),
    ("其他初级产品", "其他原料"),
];

#[derive(Deserialize)]
pub struct Market {
    pub scope:String,pub content:String,pub polity:String,pub country:String,pub market_id:String,
    pub region:String,pub good:String,pub window_days:u32,pub chart_kind:String,pub minute:u64,
    pub book:Vec<Book>,pub offers:Vec<Offer>,pub places:Vec<Choice>,pub countries:Vec<Choice>,
    pub quote:Option<Quote>,pub orders:Vec<Order>,logistics:Vec<Logistics>,chart:Vec<Sample>,pub result:String,
    pub collections:Vec<Collection>,
    pub focus:Option<MarketFocus>,
    #[serde(default)] pub catalog:Vec<Book>,
    #[serde(default)] goods_group:String,
    #[serde(default)] pub good_label:String,
    #[serde(default)] good_unit:String,
    #[serde(default)] pub sites:Vec<MarketSite>,
    #[serde(default)] enterprise_offer:Option<EnterpriseOffer>,
    #[serde(default)] selected_site:Option<String>,
}
#[derive(Deserialize)]
pub struct MarketSite {
    pub unit:String,pub place:String,pub point:[f64;2],pub name:String,pub country:String,
    pub ask:Option<i64>,pub bid:Option<i64>,pub carrier:bool,stock:i64,production:f64,demand:f64,
    #[serde(default)] pending_order:i64,
}
#[derive(Deserialize)]
struct EnterpriseOffer {name:String,price:i64,stock:i64,affordable:bool}
impl Market {
    pub fn matching_sites<'a>(&'a self, query:&str) -> impl Iterator<Item=(usize,&'a MarketSite)> + 'a {
        let query=query.trim().to_lowercase();
        self.sites.iter().enumerate().filter(move |(_,r)|
            query.is_empty() || r.name.to_lowercase().contains(&query) || r.country.to_lowercase().contains(&query))
    }
}
#[derive(Clone, Copy, Deserialize)]
pub struct MarketFocus {
    pub serial:u64,
    pub point:[f64;2],
    pub mpp:f64,
    pub shift:f64,
}
#[derive(Deserialize)]
pub struct Book {pub id:String,pub label:String,price:String,quantity:String}
#[derive(Deserialize)]
pub struct Offer {
    pub good:String,pub commodity:String,pub site:String,place:String,seller:String,
    currency:String,available:i64,
}
#[derive(Deserialize)]
pub struct Choice {pub id:String,label:String}
#[derive(Deserialize)]
pub struct Quote {
    pub token:u64,pub accepted:bool,pub commodity:String,pub name:String,pub quantity:u64,
    pub scale:u64,quoted_quantity:u64,amount:Option<i64>,
    currency_name:String,error:String,onsite:bool,
    #[serde(default)] unit:String,
}
#[derive(Deserialize)]
pub struct Order {
    pub id:String,good:String,buyer:String,seller:String,from:String,to:String,
    pub pending:i64,pub transit:i64,pub arrived:i64,pub delivered:i64,pub cancelled:i64,
    pub goods_amount:Option<i64>,pub freight_amount:i64,currency:String,
    #[serde(default)] onsite:bool,
}
#[derive(Deserialize)]
pub struct Collection {pub order:String,pub shipment:String,pub quantity:u64}
#[derive(Deserialize)]
struct Logistics {name:String,details:String}
#[derive(Deserialize)]
struct Sample {minute:u64,value:f64}
#[derive(Deserialize)]
pub struct Holding {
    pub id: String,
    label: String,
    pub quantity: i64,
    scale: i64,
    unit: String,
    #[serde(default)]
    pub consume_quantity: Option<i64>,
}

impl Market {
    pub fn logistics_len(&self)->usize{self.logistics.len()}
    pub fn status(&self)->serde_json::Value {
        let quote=self.quote.as_ref().map(|q|serde_json::json!({"id":q.commodity,"token":q.token,
            "accepted":q.accepted,"quantity":q.quantity,"amount":q.amount}));
        let orders:Vec<_>=self.orders.iter().map(|r|serde_json::json!({"id":r.id,"buyer":r.buyer,"seller":r.seller,
            "delivered":r.delivered,"pending":r.pending,"goods":r.goods_amount})).collect();
        serde_json::json!({"scope":self.scope,"content":self.content,"polity":self.polity,"market_id":self.market_id,
            "region":self.region,"book":self.book.iter().map(|r|&r.id).collect::<Vec<_>>(),
            "offer_ids":self.offers.iter().map(|r|(&r.commodity,&r.site,&r.place,&r.currency)).collect::<Vec<_>>(),
            "quote":quote,"orders":orders,"result":self.result,
            "collections":self.collections.iter().map(|c|(&c.order,&c.shipment,c.quantity)).collect::<Vec<_>>()})
    }
}

pub fn format_quantity(value:i64,scale:i64)->String {
    if scale<=1 {return value.to_string();}
    format!("{:.3}", value as f64/scale as f64).trim_end_matches('0').trim_end_matches('.').to_owned()
}

pub fn parse_quantity(input:&str,scale:u64)->Option<u64>{
    let (whole,fraction)=input.split_once('.').unwrap_or((input,""));
    if !whole.bytes().chain(fraction.bytes()).all(|v|v.is_ascii_digit())||fraction.len()>6{return None;}
    let denominator=10u64.pow(fraction.len() as u32);
    let numerator=if fraction.is_empty(){0}else{fraction.parse::<u64>().ok()?};
    let scaled=numerator.checked_mul(scale)?;
    if scaled%denominator!=0{return None;}
    let whole=if whole.is_empty(){0}else{whole.parse::<u64>().ok()?};
    let value=whole.checked_mul(scale)?.checked_add(scaled/denominator)?;
    (value>0 && value<=1_000_000).then_some(value)
}

fn command(verb:&'static str,index:usize)->Option<Action>{Some(Action::Hud(Command::Market(verb,index)))}

impl Display<'_> {
    pub(crate) fn property(&self,m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>){
        let Some([x,y,w,h])=self.page_rect() else{return;};
        self.folio(m,art,t,hits,[x,y,w,h],"人物 · 持有物");
        let Some(s)=self.session else{self.skin.text(t,"正式世界未连接",0,[x+20.,y+75.],w-40.,MUTED);return;};
        if s.property.is_empty(){self.skin.text(t,"暂无个人持有物品。",0,[x+20.,y+75.],w-40.,MUTED);}
        for (index, row) in s.property.iter().enumerate().skip(self.hud.market_offset).take(((h-114.)/33.) as usize) {
            let top=y+74.+(index-self.hud.market_offset) as f32*33.;
            self.skin.text(t,&row.label,0,[x+22.,top],w*0.36,IVORY);
            self.skin.text(t,&format!("{} {}",format_quantity(row.quantity,row.scale),row.unit),0,[x+w*0.4,top],w*0.30,IVORY);
            if let Some(quantity) = row.consume_quantity {
                self.row(m,t,hits,[x+w-138.,top-2.,114.,25.],
                    &format!("消费 {}", format_quantity(quantity, row.scale)),
                    Some(Action::Hud(Command::Consume(index))),false);
            }
            m.line([x+22.,top+26.],[x+w-24.,top+26.],0.7,BRASS);
        }
        if !s.property_feedback.is_empty() {
            self.skin.text(t,&s.property_feedback,0,[x+22.,y+h-30.],w-44.,MUTED);
        }
    }

    pub(crate) fn market(&self,m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>){
        let Some([x,y,w,h])=self.page_rect() else{return;};
        let market=self.session.and_then(|s|s.market.as_ref());
        let title=market.map(|view|match view.scope.as_str(){
            "international"=>"国际大宗市场".to_owned(),
            "regional"=>format!("{} · 区域市场",view.places.iter().find(|p|p.id==view.region).map_or("",|p|p.label.as_str())),
            _=>format!("{} · 国内市场",view.country),
        }).unwrap_or_else(||"市场".into());
        self.decorated_folio(m,art,t,hits,[x,y,w,h],&title,"market_crest");
        let Some(v)=market else {
            self.skin.text(t,if self.session.is_some(){"正在读取正式市场。"}else{"正式世界未连接"},0,[x+20.,y+72.],w-40.,MUTED);return;
        };
        if let Some(q)=&v.quote {self.quote_panel(m,t,hits,[x,y,w,h],q);return;}
        let bx=x+20.;let bw=w-40.;
        let scope_width=bw/5.;
        for (i,(id,label)) in [("international","国际市场"),("domestic","国内市场")].into_iter().enumerate(){
            self.row(m,t,hits,[bx+i as f32*scope_width,y+62.,scope_width-5.,27.],label,
                command(id,0),v.scope==id);
        }
        self.row(m,t,hits,[bx+4.*scope_width,y+62.,scope_width-5.,27.],"选择国家",
            (!v.countries.is_empty()).then(|| command("countries",0)).flatten(),self.hud.market_chooser==Some("countries"));
        let mut tabs = vec![("quotes","报价簿"),("trends","商品地点"),("goods","商品目录"),("transport","仓储与运输"),("activity","活动记录")];
        if self.session.is_some_and(|s| s.transport.is_some()) { tabs.push(("freight","实物货运")); }
        let tab_width = bw / tabs.len() as f32;
        for (i,(id,label)) in tabs.into_iter().enumerate(){
            let selected=match id{"trends"=>v.content=="good",_=>v.content==id};
            self.row(m,t,hits,[bx+i as f32*tab_width,y+100.,tab_width-5.,28.],label,
                if id=="trends"&&v.book.is_empty(){None}else{command(id,0)},selected&&self.hud.market_chooser.is_none());
        }
        let footer=&v.result;
        self.skin.text(t,footer,0,[bx,y+h-34.],bw,MUTED);
        let top=y+145.;let floor=y+h-49.;
        let first=self.hud.market_offset;
        if let Some(query)=self.hud.market_search.as_deref() {
            self.skin.text(t,&format!("搜索地点或国家  {query}▏"),1,[bx,top],bw-82.,IVORY);
            self.row(m,t,hits,[bx+bw-76.,top,76.,27.],"地图",command("map_locations",0),false);
            let start=top+39.;
            let count=v.matching_sites(query).count();
            if count==0 { self.skin.text(t,"暂无符合条件的交易地点",0,[bx,start],bw,MUTED); }
            for (row,(index,site)) in v.matching_sites(query).skip(first).take(((floor-start)/38.) as usize).enumerate() {
                let yy=start+row as f32*38.;
                let label=if site.name==site.country {site.name.clone()} else {format!("{} · {}",site.name,site.country)};
                self.row(m,t,hits,[bx,yy,bw*0.51,31.],&label,command("location",index),false);
                self.skin.text(t,&location_prices(site),0,[bx+bw*0.54,yy+6.],bw*0.46,IVORY);
            }
            return;
        }
        if let Some(which)=self.hud.market_chooser {
            let list=if which=="places"{&v.places}else{&v.countries};
            let rows=((floor-top)/30.) as usize;
            for (i,row) in list.iter().enumerate().skip(first).take(rows){
                self.row(m,t,hits,[bx,top+(i-first) as f32*30.,bw,27.],&row.label,command(if which=="places"{"region"}else{"country"},i),false);
            }
            return;
        }
        match v.content.as_str() {
            "freight"=>self.freight_page(m,t,hits,[bx,top,bw,floor-top]),
            "good"=>self.good_panel(m,t,hits,v,[bx,top,bw,floor-top]),
            "trend"=>self.trend_panel(m,t,hits,v,[bx,top,bw,floor-top]),
            "activity"=>{
                if v.orders.is_empty(){self.skin.text(t,"此范围暂无本人或获准企业的订单记录",0,[bx,top],bw,MUTED);}
                for (i,row) in v.orders.iter().skip(first).take(((floor-top)/64.) as usize).enumerate(){
                    let yy=top+i as f32*64.;
                    self.skin.text(t,&format!("{} · {} → {}",row.good,row.from,row.to),0,[bx,yy],bw,IVORY);
                    self.skin.text(t,&format!("待发 {} · 在途 {} · 待领 {} · 已交付 {} · 已取消 {}",row.pending,row.transit,row.arrived,row.delivered,row.cancelled),0,[bx,yy+19.],bw,MUTED);
                    let paid=row.goods_amount.map_or_else(|| "货款未公开或未结算".into(),|amount|format!("已付货款 {amount} {}",row.currency));
                    let delivery=if row.onsite {"现场交割".into()}else{format!("运费 {}",row.freight_amount)};
                    self.skin.text(t,&format!("{paid} · {delivery}"),0,[bx,yy+37.],bw-96.,MUTED);
                    if let Some((index,collection))=v.collections.iter().enumerate().find(|(_,c)|c.order==row.id){
                        self.row(m,t,hits,[bx+bw-93.,yy+30.,93.,24.],&format!("提货 {}",collection.quantity),command("collect",index),false);
                    }
                    m.line([bx,yy+57.],[bx+bw,yy+57.],0.7,BRASS);
                }
            },
            "transport"=>{
                if v.logistics.is_empty(){self.skin.text(t,"暂无可查看的仓储或运输记录",0,[bx,top],bw,MUTED);}
                for (i,row) in v.logistics.iter().skip(first).take(((floor-top)/66.) as usize).enumerate(){
                    let yy=top+i as f32*66.;
                    self.skin.text(t,&row.name,0,[bx,yy],bw,IVORY);
                    for (j,line) in row.details.lines().take(2).enumerate(){
                        self.skin.text(t,line,0,[bx,yy+19.+j as f32*18.],bw,MUTED);
                    }
                }
            },
            _=>{
                let catalog = v.content == "goods";
                let list = if catalog { &v.catalog } else { &v.book };
                let header = if catalog {
                    let width = bw / GOODS_GROUPS.len() as f32;
                    for (i, (id, label)) in GOODS_GROUPS.into_iter().enumerate() {
                        self.row(m, t, hits, [bx+i as f32*width,top,width-5.,26.], label,
                            command("goods_group",i), v.goods_group == id);
                    }
                    top + 36.
                } else {
                    self.skin.text(t,&format!("{} 种报价商品 · {} 笔可见订单",list.len(),v.orders.len()),0,[bx,top],bw,IVORY);
                    top + 23.
                };
                for (i,label) in ["商品","生丁 / 单位","现有库存"].into_iter().enumerate(){
                    self.skin.text(t,label,0,[bx+bw*[0.,0.41,0.73][i],header],bw*0.27,MUTED);
                }
                let start = header + 24.;
                if list.is_empty() {
                    let message = if catalog { "此类暂无登记商品" } else { "此范围暂无已知卖家报价" };
                    self.skin.text(t,message,0,[bx,start],bw,MUTED);
                }
                let rows=((floor-start)/33.) as usize;
                for (i,row) in list.iter().enumerate().skip(first).take(rows){
                    let yy=start+(i-first) as f32*33.;
                    self.row(m,t,hits,[bx,yy,bw*0.39,28.],&row.label,command(if catalog {"catalog_good"} else {"good"},i),false);
                    self.skin.text(t,&row.price,0,[bx+bw*0.41,yy+4.],bw*0.31,IVORY);
                    self.skin.text(t,&row.quantity,0,[bx+bw*0.73,yy+4.],bw*0.27,MUTED);
                }
            }
        }
    }

    fn good_panel(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,v:&Market,[x,y,w,_]:[f32;4]){
        let name=if v.good_label.is_empty() {
            v.book.iter().find(|row|row.id==v.good).map_or(v.good.as_str(),|row|row.label.as_str())
        } else {&v.good_label};
        self.skin.text(t,name,1,[x,y],w-128.,IVORY);
        self.row(m,t,hits,[x+w-118.,y,118.,27.],"返回报价簿",command("quotes",0),false);
        self.row(m,t,hits,[x,y+36.,129.,28.],"地图选点",command("map_locations",0),false);
        self.row(m,t,hits,[x+139.,y+36.,136.,28.],"搜索交易地点",command("search_locations",0),false);
        self.skin.text(t,&format!("{} 个已知交易地点",v.sites.len()),0,[x+287.,y+41.],w-378.,MUTED);
        self.row(m,t,hits,[x+w-82.,y+36.,82.,28.],"趋势",command("trend",0),false);
        let site=v.sites.iter().enumerate().find(|(_,r)|v.selected_site.as_deref()==Some(r.place.as_str()));
        if let Some((index,site))=site {
            self.skin.text(t,&format!("{} · {}",site.country,site.name),0,[x,y+85.],w-125.,IVORY);
            self.skin.text(t,&location_prices(site),0,[x,y+111.],w,IVORY);
            if site.pending_order==0 {
                self.skin.text(t,&format!("库存 {} {}  ·  日产 {}  ·  日需 {}",
                    format_quantity(site.stock,1000),v.good_unit,compact_amount(site.production),compact_amount(site.demand)),
                    0,[x,y+135.],w,MUTED);
            }
            if site.carrier && self.session.is_some_and(|s| s.place != site.place) {
                self.row(m,t,hits,[x+w-120.,y+81.,120.,28.],"查询运输",command("carrier",index),false);
            }
        } else {
            self.skin.text(t,"此市场暂无可办理的交易",0,[x,y+86.],w,MUTED);
        }
        let mut yy=y+190.;
        for (i,offer) in v.offers.iter().enumerate() {
            self.skin.text(t,&format!("{}库存可现场交付",offer.seller),0,[x,yy+4.],w-124.,IVORY);
            if offer.available>0 {
                self.row(m,t,hits,[x+w-114.,yy,114.,29.],"查看报价",command("offer",i),false);
            }
            yy+=36.;
        }
        if let Some(offer)=&v.enterprise_offer {
            self.skin.text(t,&format!("{} · {} 千克 · {} 生丁 / 千克",offer.name,offer.stock,offer.price),
                0,[x,yy+4.],w-124.,IVORY);
            self.row(m,t,hits,[x+w-114.,yy,114.,29.],"购买 1 千克",
                offer.affordable.then(||command("local_bread",0)).flatten(),false);
        }
    }

    fn trend_panel(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,v:&Market,[x,y,w,_]:[f32;4]){
        self.row(m,t,hits,[x,y,115.,27.],"返回商品",command("back_good",0),false);
        for (i,(id,label)) in [("price","产地价格"),("supply","可见供给")].into_iter().enumerate(){
            self.row(m,t,hits,[x+i as f32*95.,y+34.,88.,25.],label,command(id,0),v.chart_kind==id);
        }
        for (i,days) in [7,30,90].into_iter().enumerate(){
            self.row(m,t,hits,[x+w-153.+i as f32*51.,y+34.,47.,25.],&format!("{days}日"),command("window",days),v.window_days==days as u32);
        }
        let bottom=y+123.;
        let from=v.minute.saturating_sub(u64::from(v.window_days)*1440);
        let visible:Vec<_>=v.chart.iter().filter(|row|row.minute>=from&&row.minute<=v.minute).collect();
        if let (Some(a),Some(b))=(visible.first(),visible.last()) {
            if a.minute!=b.minute {
                let (min,max)=visible.iter().fold((f64::INFINITY,f64::NEG_INFINITY),|(a,b),v|(a.min(v.value),b.max(v.value)));
                for rows in visible.windows(2) {
                    let pos=|s:&Sample|[x+((s.minute-from) as f64/(v.minute-from).max(1) as f64) as f32*w,
                        bottom-5.-((s.value-min)/(max-min).max(0.001)) as f32*48.];
                    m.line(pos(rows[0]),pos(rows[1]),1.3,BRASS);
                }
            }else{self.skin.text(t,"只有一个记录时点",0,[x,y+72.],w,MUTED);}
        }else{self.skin.text(t,"该期间暂无可见记录",0,[x,y+72.],w,MUTED);}
    }

    fn quote_panel(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,[x,y,w,h]:[f32;4],q:&Quote){
        let left=x+23.;let width=w-46.;
        self.row(m,t,hits,[left,y+132.,105.,27.],"返回行情",command("quote_back",0),false);
        self.skin.text(t,&q.name,1,[left,y+110.],width,IVORY);
        self.skin.text(t,&q.unit,0,[left+187.,y+181.],width-190.,MUTED);
        let quantity=self.hud.quantity.clone().unwrap_or_else(||format_quantity(q.quantity as i64,q.scale as i64));
        self.skin.text(t,"数量",0,[left,y+181.],75.,IVORY);
        self.row(m,t,hits,[left+58.,y+176.,116.,28.],&quantity,command("edit",0),self.hud.quantity.is_some());
        self.row(m,t,hits,[left+275.,y+176.,97.,28.],"更新报价",command("requote",0),false);
        let ready=q.accepted&&self.hud.quantity.is_none()&&self.hud.purchase_token!=Some(q.token);
        self.row(m,t,hits,[left,y+236.,130.,31.],"购买",if ready{command("buy",0)}else{None},ready);
        if self.session.is_some_and(|s| s.transport.is_some()) {
            self.row(m,t,hits,[left,y+320.,130.,30.],"采购货批",if ready{command("freight_buy",0)}else{None},false);
        }
        if let Some(amount)=q.amount {
            self.skin.text(t,&format!("应付 {amount} {}",q.currency_name),1,[left+150.,y+238.],width-150.,IVORY);
            self.skin.text(t,&format!("交付 {} {}",format_quantity(q.quoted_quantity as i64,q.scale as i64),q.unit),0,[left,y+280.],width,IVORY);
            self.skin.text(t,if q.onsite{"现场交付后取得。"}else{"接受后预留资金；实际到货后取得物品。"},0,[left,y+307.],width,MUTED);
        }else{self.skin.text(t,&q.error,0,[left,y+280.],width,MUTED);}
        if let Some(v)=self.session.and_then(|s|s.market.as_ref()){
            self.skin.text(t,&v.result,0,[left,y+h-40.],width,MUTED);
        }
    }
}

fn compact_amount(amount:f64)->String {
    format!("{amount:.2}").trim_end_matches('0').trim_end_matches('.').to_owned()
}

fn location_prices(site:&MarketSite)->String {
    if site.pending_order > 0 { return format!("企业待交 {} 千克",site.pending_order); }
    match (site.ask,site.bid) {
        (Some(ask),Some(bid))=>format!("卖 {ask} · 收 {bid} 生丁 / 单位"),
        (Some(ask),None)=>format!("卖 {ask} 生丁 / 单位"),
        (None,Some(bid))=>format!("收 {bid} 生丁 / 单位"),
        _=>String::new(),
    }
}
