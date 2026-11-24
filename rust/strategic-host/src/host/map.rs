use super::{CountryClick, Focus, Host, Pose, COUNTRY_DOUBLE_CLICK};
use crate::{camera::{self, Camera}, formal_ui::{self, Command as HudCommand, Menu as HudMenu, Page as HudPage}, lobby, state::Request, timeline::Date, ui::{self, Action, CountryAction, CountryPanel, CountryView, Mode, Object}, world::World};
use std::time::Instant;

impl Host {
    pub(super) fn available(&self,object:Object)->bool {
        let day=self.state.date.to_string();
        match object {
            Object::Polity(i)=>self.world.polities.get(i).is_some_and(|p|p.active(&day)),
            Object::Place(i)=>self.world.places.get(i).is_some_and(|p|ui::active(&day,&p.from_date,&p.to_date)),
            Object::Administration(i)=>World::active_politics(&day)&&i<self.world.admin.len(),
        }
    }
    pub(super) fn id(&self,object:Object)->String {
        match object {Object::Place(i)=>self.world.places[i].id.clone(),Object::Polity(i)=>self.world.polities[i].map_id(),Object::Administration(i)=>self.world.admin[i].id.clone()}
    }
    fn select(&mut self,object:Option<Object>) {
        self.select_transport(None);
        self.country=None;
        self.details=false;
        self.selected=object.filter(|o|self.available(*o));
        if let Some(object)=self.selected {
            let display_only=match object {
                Object::Polity(i)=>self.world.polities[i].display_only,
                Object::Place(i)=>self.landmarks.as_ref().is_some_and(|landmarks|landmarks.contains(i)),
                Object::Administration(_)=>false,
            };
            if !display_only {
                self.emit(Request::Inspect{id:&self.id(object)});
            }
        }
        self.dirty=true;
    }
    pub(super) fn open_country(&mut self,polity:usize) {
        if !self.available(Object::Polity(polity)){return;}
        if self.country.is_some_and(|panel|panel.polity==polity){return;}
        self.select(Some(Object::Polity(polity)));
        let view=if self.player_polity()==Some(polity){CountryView::Record}else{CountryView::Summary};
        self.country=Some(CountryPanel{polity,view});
    }
    fn click_country(&mut self,polity:usize,point:[f64;2]) {
        let now=Instant::now();
        if self.country_click.take().is_some_and(|first|first.polity==polity && now<=first.deadline &&
            (point[0]-first.point[0]).hypot(point[1]-first.point[1])<=8.) {
            let object=Object::Polity(polity);
            self.country=None;
            self.details=false;
            self.selected=Some(object);
            let target=self.visuals.record(polity).focus(self.size).unwrap_or((self.world.polities[polity].coordinates,1800.));
            self.focus_on(object,target);
        }else{
            self.country_click=Some(CountryClick{polity,point,deadline:now+COUNTRY_DOUBLE_CLICK});
        }
    }
    pub(super) fn country_action(&mut self,action:CountryAction) {
        use CountryAction as Go;
        let Some(mut panel)=self.country.take() else{return;};
        let count=self.skin.admin_count(&self.world,&self.world.polities[panel.polity]);
        panel.view=match (action,panel.view) {
            (Go::Close,_)=>{
                if self.selected==Some(Object::Polity(panel.polity)){self.selected=None;}
                return;
            }
            (Go::Back,CountryView::Directory(_))=>CountryView::Record,
            (Go::Back,CountryView::Region{page,..})=>CountryView::Directory(page),
            (Go::Back,CountryView::Record) if self.player_polity()!=Some(panel.polity)=>CountryView::Summary,
            (Go::Record,CountryView::Summary)=>CountryView::Record,
            (Go::Directory,CountryView::Record) if count>0=>CountryView::Directory(0),
            (Go::Page(step),CountryView::Directory(page))=>{
                let last=count.saturating_sub(1)/panel.rows(self.size);
                CountryView::Directory(page.saturating_add_signed(step as isize).min(last))
            }
            (Go::Region(index),CountryView::Directory(_)) if index<count=>CountryView::Region{page:index/panel.rows(self.size),index},
            (Go::Boundary(index),view @ CountryView::Region{..})=>{
                if let Some(target)=camera::fit_bounds(self.world.admin[index].bounds,self.size){
                    self.focus_on(Object::Administration(index),target);
                }
                view
            }
            (_,view)=>view,
        };
        self.country=Some(panel);
    }
    fn save_pose(&mut self) {
        if self.history.len()>=24 {self.history.remove(0);}
        self.history.push(Pose{camera:self.camera.clone(),object:self.selected});
    }
    pub(super) fn locate(&mut self,target:[f64;2],mpp:f64) {
        self.focus=None;self.save_pose();self.camera.focus(target,mpp,self.size);
        self.velocity=[0.;2];self.details=false;self.search=None;self.dirty=true;
    }
    fn focus_on(&mut self,object:Object,(target,mpp):([f64;2],f64)) {
        if !matches!(object,Object::Polity(i) if self.world.polities[i].display_only) {
            self.emit(Request::Locate{id:&self.id(object)});
        }
        self.save_pose();
        self.focus=Some(Focus{start:Instant::now(),camera:self.camera.clone(),target,mpp});
        self.velocity=[0.;2];
        self.dirty=true;
    }
    fn locate_object(&mut self,object:Object) {
        let landmark=match object {
            Object::Place(index)=>self.landmarks.as_ref().and_then(|models|models.focus(index)),
            _=>None,
        };
        let (target,mpp)=match object {
            Object::Administration(i)=>{
                let Some(target)=camera::fit_bounds(self.world.admin[i].bounds,self.size) else{return;};
                target
            }
            Object::Place(i)=>landmark.unwrap_or_else(||(self.world.places[i].coordinates,if self.world.places[i].id=="place:paris" {36.}else{210.})),
            Object::Polity(i)=>self.visuals.record(i).focus(self.size).unwrap_or((self.world.polities[i].coordinates,1800.)),
        };
        if !matches!(object,Object::Place(_)) {
            self.focus_on(object,(target,mpp));
        } else {
            if landmark.is_none(){self.emit(Request::Locate{id:&self.id(object)});}
            self.locate(target,mpp);
        }
        self.search=None;
        if let Object::Polity(polity)=object{self.open_country(polity);}else{self.select(Some(object));}
    }
    pub(super) fn resources_available(&self) -> bool {
        !self.in_lobby() && self.population_debug.is_none() && self.search.is_none() && self.country.is_none() && !self.details
            && crate::resource_map::available(self.mode,self.hud.page,self.hud.menu,self.hud.market_map,self.transport_detail.is_some())
    }
    pub(super) fn action(&mut self,action:Action) {
        self.country_click=None;
        self.feedback.clear();
        match action {
            Action::Mode(mode)=>{
                if self.hud.page==HudPage::Market{self.market_command("close",0);}
                if mode==Mode::Military && self.mode!=Mode::Military && self.written_world().is_some(){self.hud.military_grid=true;}
                if self.mode!=mode {
                    self.hud.transport_detail_expanded=false;
                    self.transport_detail=None;
                }
                self.mode=mode;
                if self.hud.page!=HudPage::Travel {self.hud.page=HudPage::Map;}
                self.hud.menu=HudMenu::None;
                self.emit(Request::SetMapMode{mode:mode.key()});
            }
            Action::Home=>{
                self.focus=None;self.save_pose();self.camera.set_scale(Camera::overview(self.size));
                self.velocity=[0.;2];self.details=false;self.country=None;self.search=None;
            }
            Action::Back=>{
                self.focus=None;
                if let Some(p)=self.history.pop(){self.camera=p.camera;self.select(p.object);}
                self.velocity=[0.;2];self.details=false;self.country=None;self.search=None;
            }
            Action::Search=>{
                self.details=false;self.country=None;
                self.search=if self.search.is_some(){None}else{Some(String::new())};
                if self.search.is_some() { self.population_debug=None; }
            }
            Action::Close=>self.select(None),
            Action::Details=>self.details=!self.details,
            Action::Country(go)=>self.country_action(go),
            Action::Locate=>if let Some(o)=self.selected{self.locate_object(o);},
            Action::Select(o)=>if self.search.is_some(){self.locate_object(o);}else{
                self.select(Some(o));
                if let Object::Place(i)=o {
                    if self.hud.page==HudPage::Market {
                        let region=self.state.session.as_ref().and_then(|s|s.market.as_ref())
                            .and_then(|m|m.places.iter().position(|row|row.id==self.world.places[i].id));
                        if let Some(index)=region {self.market_command("region",index);}
                    }
                }
            },
            Action::Hud(command)=>self.hud_action(command),
            Action::Resources(command)=>{
                if self.resources_available() {
                    let polity = crate::resource_map::State::site(command)
                        .and_then(|site| self.resource_owner(site));
                    if matches!(command,crate::resource_map::Command::Toggle) && !self.resources.open {
                        self.select(None);
                    }
                    self.resources.command(command,polity);
                }
            }
        }
        self.dirty=true;
    }
    pub(super) fn search_results(&self)->Vec<Object> {
        let q=self.search.as_deref().unwrap_or("").trim().to_ascii_lowercase();
        if q.is_empty(){return Vec::new();}
        let items=self.world.places.iter().enumerate().map(|(i,p)|(Object::Place(i),p.rank,&p.name,&p.id))
            .chain(self.world.polities.iter().enumerate().map(|(i,p)|(Object::Polity(i),p.rank,&p.name,&p.id)));
        let mut rows:Vec<_>=items.filter_map(|(o,rank,name,id)| {
            if !ui::can_read_object(&self.world, self.written_world(), o) { return None; }
            let name=name.to_ascii_lowercase();
            let localized=ui::object_name(&self.world,&self.skin,o).to_ascii_lowercase();
            ((name.contains(&q)||localized.contains(&q)||id.contains(&q)||q.strip_prefix("state:")==Some(id))&&self.available(o))
                .then(||(localized!=q&&name!=q,!localized.starts_with(&q)&&!name.starts_with(&q),rank,localized,o))
        }).collect();
        rows.sort_by(|a,b|(&a.0,&a.1,&a.2,&a.3).cmp(&(&b.0,&b.1,&b.2,&b.3)));
        rows.into_iter().take(6).map(|r|r.4).collect()
    }
    pub(super) fn accept_search(&mut self) {
        if let Some(o)=self.search_results().first().copied(){self.locate_object(o);return;}
        if let Some(q)=self.search.as_ref() {
            let values:Result<Vec<f64>,_>=q.split(|c:char|c.is_whitespace()||c==',').filter(|s|!s.is_empty()).map(str::parse).collect();
            if let Ok(v)=values {
                if v.len()==2&&(-180. ..=180.).contains(&v[0])&&(-90. ..=90.).contains(&v[1]){
                    self.locate([v[0],v[1]],self.camera.mpp.min(1200.));return;
                }
            }
        }
        self.feedback=self.skin.choose("没有匹配的地点或国家","No matching place or country").into();
    }
    fn political_page_at(&self, point: [f64; 2]) -> Option<(&crate::world::Tile, &super::Page)> {
        self.visible.iter().rev().find_map(|&index| {
            let tile = &self.world.tiles[index];
            if !tile.ids || !camera::inside(point, tile.core) { return None; }
            self.cached.get(&index).map(|cached| (tile, &cached.page))
        }).or_else(|| self.base.as_ref().map(|base| (&self.world.tiles[0], base)))
    }

    pub(super) fn object_at(&self, point: [f64; 2]) -> [u8; 2] {
        let Some((tile, page)) = self.political_page_at(point) else { return [0, 0]; };
        let [owner, admin] = page.ids_at(tile, point);
        let Some(polity) = owner.checked_sub(1).map(usize::from)
            .filter(|&i| self.available(Object::Polity(i))) else { return [0, 0]; };
        [owner, if self.world.polities[polity].id == "country_fra" { admin } else { 0 }]
    }

    fn resource_owner(&self, site: &wwo_map_lab::resource_geography::Resource) -> Option<usize> {
        let [lon, lat] = site.geometry.anchor();
        let owner = self.object_at([lon, lat])[0];
        let polity = usize::from(owner.checked_sub(1)?);
        let (tile, _) = self.political_page_at([lon, lat])?;
        let [west, south, east, north] = tile.bounds;
        let uncertainty = (f64::from(site.spatial_accuracy_m.unwrap_or(0)) / camera::EARTH).to_degrees();
        // Rasterized boundary pixels can straddle even a precisely located site.
        let dx = uncertainty / lat.to_radians().cos().max(0.01)
            + 2. * (east - west) / f64::from(tile.size[0]);
        let dy = uncertainty + 2. * (north - south) / f64::from(tile.size[1]);
        let agrees = [-dx, 0., dx].into_iter().all(|x| {
            [-dy, 0., dy].into_iter().all(|y| {
                let longitude = (lon + x + 180.).rem_euclid(360.) - 180.;
                self.object_at([longitude, (lat + y).clamp(-90., 90.)])[0] == owner
            })
        });
        agrees.then_some(polity)
    }
    pub(super) fn click(&mut self,p:[f64;2]) {
        if self.opening_transition_active() {return;}
        if let (Some(view),Some((_,terrain)))=(&mut self.battle_view,&self.battle_terrain){
            let command=view.left_button(true,p,self.size,terrain);
            view.left_button(false,p,self.size,terrain);
            if let Some(command)=command {self.battle_command(command);}
            return;
        }
        if self.loading(){return;}
        if let Some(panel)=self.population_debug.as_mut().filter(|_|p[1]<f64::from(self.size[1].saturating_sub(92))) {
            if panel.contains(self.size,p) {
                if let Some(page) = panel.page_at(self.size, p) { self.population_page(page); }
                else { panel.click_control(self.size, p); self.dirty=true; }
                return;
            }
            let [x,y]=p.map(|v|v as f32);
            let object=self.hits.iter().rev().find_map(|hit| {
                let [left,top,width,height]=hit.area;
                match hit.action {
                    Action::Select(object @ Object::Place(_)) if x>=left&&x<=left+width&&y>=top&&y<=top+height => Some(object),
                    _ => None,
                }
            }).or_else(|| {
                let q=camera::geographic(self.camera.vector(p,self.size)?);
                let [polity,admin]=self.object_at(q);
                admin.checked_sub(1).map(|i|Object::Administration(usize::from(i)))
                    .filter(|&object|self.available(object))
                    .or_else(||polity.checked_sub(1).map(|i|Object::Polity(usize::from(i))).filter(|&object|self.available(object)))
            });
            self.population_location(object);
            return;
        }
        let [x,y]=p.map(|v|v as f32);
        let contains=|[a,b,w,h]:[f32;4]| x>=a&&x<=a+w&&y>=b&&y<=b+h;
        let resource_map=self.resources_available()&&self.resources.open;
        if self.hud.menu==HudMenu::MapModes&&contains(formal_ui::map_modes_rect(self.size)) {
            if let Some(hit)=self.hits.iter().find(|hit|matches!(hit.action,Action::Mode(_))&&contains(hit.area)) {
                self.action(hit.action);
            }
            return;
        }
        let radius=(self.size[0] as f32*0.056).clamp(52.,78.);
        let in_menu=self.hud.menu!=HudMenu::None&&contains(formal_ui::menu_rect(self.hud.menu,self.size,radius));
        let in_country=!self.hud.menu.modal()&&self.country.is_some_and(|panel|contains(panel.rect(self.size)));
        if let Some(hit)=self.hits.iter().rev().find(|h|{
            let gear=matches!(h.action,Action::Hud(HudCommand::Menu(HudMenu::System)))&&h.area[1]==0.;
            let portrait=match h.action{Action::Hud(HudCommand::PortraitAction(i,_))=>formal_ui::portrait_action_hit(i,self.size[1] as f32,p),_=>true};
            contains(h.area)&&(!gear||formal_ui::gear_hit(p,self.size[0]))
                &&portrait
                &&(!in_menu||!matches!(h.action,Action::Country(_)|Action::Select(_)))
                &&(!self.transport_panel_at(p)||!matches!(h.action,Action::Select(_)))
                &&(!resource_map||!matches!(h.action,Action::Select(_)))
                &&(!matches!(h.action,Action::Resources(crate::resource_map::Command::Site(_)))
                    || resource_map&&!contains(crate::resource_map::bounds(self.size)))
                &&(!in_country||in_menu||matches!(h.action,Action::Country(_)))
                &&(!self.details||!matches!(h.action,Action::Select(_))||self.search.is_some())
        }) {
            let action=hit.action;
            match action {
                Action::Hud(HudCommand::PlayerCountry) if self.search.is_none()&&self.hud.menu==HudMenu::None
                    && p[0]<=104. && p[1]<=76.=>{
                    if let Some(i)=self.player_polity(){self.click_country(i,p);}
                }
                Action::Select(_) if self.hud.market_map=>{},
                Action::Select(object) if self.search.is_none()
                    && (self.hud.page == HudPage::Travel || self.planning_transport()) => {
                    let place = match object { Object::Place(index) => Some(index), _ => None };
                    self.pick_transport_destination(p, place);
                }
                Action::Select(Object::Polity(i)) if self.search.is_none()&&self.hud.menu==HudMenu::None&&self.hud.page==HudPage::Map=>{
                    self.click_country(i,p);
                }
                Action::Select(Object::Place(_)) if !in_country && self.pick_transport(p)=>{},
                _=>self.action(action),
            }
            return;
        }
        if self.is_panel(p){return;}
        if resource_map {
            if let Some(point)=self.camera.vector(p,self.size).map(camera::geographic) {
                let owner=self.object_at(point)[0].checked_sub(1).map(usize::from);
                if self.resources.pick(point,owner) {self.dirty=true;return;}
            }
        }
        if self.pick_transport_destination(p,None)||self.pick_transport(p)||self.hud.market_map{return;}
        let coordinates=self.camera.vector(p,self.size).map(camera::geographic);
        let map_hit = coordinates.map(|q| self.object_at(q));
        let hit = map_hit.map(|owner| owner[0]);
        if self.in_lobby(){
            use lobby::SelectionStage;
            if self.lobby_page != lobby::Page::Selection { return; }
            self.opening_nav.last_input = Instant::now();
            if self.opening_nav.stage == SelectionStage::Globe {
                if coordinates.is_some() {
                    self.opening_nav.stage = SelectionStage::Directory;
                    self.filter_countries();
                    self.opening_shift(-0.11);
                }
                return;
            }
            let index = hit.and_then(|value| value.checked_sub(1)).map(usize::from)
                .filter(|&i| self.available(Object::Polity(i)));
            if self.opening_nav.stage == SelectionStage::Directory {
                if let Some(index) = index { self.lobby_action(lobby::Command::Country(index)); }
                return;
            }
            if self.world.polities[self.lobby_country].id == "country_fra" {
                let admin = map_hit.and_then(|owner| {
                    (index == Some(self.lobby_country)).then_some(owner[1])?.checked_sub(1).map(usize::from)
                });
                if let Some(admin) = admin { self.lobby_action(lobby::Command::MapArea(admin)); }
            }
            return;
        }
        let polity=hit.and_then(|v|v.checked_sub(1)).map(usize::from);
        self.select_transport(None);
        if coordinates.is_some_and(|q|self.click_military_cell(q,polity)){return;}
        if self.hud.page==HudPage::Map {
            if let Some(i)=polity.filter(|_|self.hud.menu==HudMenu::None){self.click_country(i,p);return;}
        }
        self.country_click=None;
        self.select(polity.map(Object::Polity));
    }

    fn transport_panel_at(&self, p: [f64; 2]) -> bool {
        let Some((_, detail))=self.transport_detail.as_ref().filter(|_|self.transport_detail_visible()) else{return false;};
        let [x,y,w,h]=detail.rect(self.size,self.hud.transport_detail_expanded).map(f64::from);
        p[0]>=x && p[0]<=x+w && p[1]>=y && p[1]<=y+h
    }
    pub(super) fn is_panel(&self,p:[f64;2])->bool {
        if self.loading(){return true;}
        let [x,y]=p;
        let contains=|[a,b,w,h]:[f32;4]| x>=f64::from(a)&&x<=f64::from(a+w)&&y>=f64::from(b)&&y<=f64::from(b+h);
        let [w,h]=self.size.map(|v|v as f32);
        if self.in_lobby(){
            return self.lobby_request||match self.lobby_page {
                lobby::Page::Selection => (match self.opening_nav.stage {
                    lobby::SelectionStage::Globe => false,
                    lobby::SelectionStage::Directory => lobby::contains(lobby::directory_rect(self.size), p),
                    lobby::SelectionStage::Profile => self.opening_layout().is_some_and(|layout| layout.contains(&self.opening_nav, p)),
                })
                    || lobby::contains([12., 14., 67., 30.], p)
                    || lobby::contains([12., h - 44., 124., 30.], p),
                _=>true,
            };
        }
        let radius=(w*0.056).clamp(52.,78.);
        let modal=self.hud.menu.modal();
        modal||self.search.is_some()||self.details||self.transport_panel_at(p)||
            (self.resources_available()&&self.resources.open&&contains(crate::resource_map::bounds(self.size)))||
            self.country.is_some_and(|country|contains(country.rect(self.size)))||
            formal_ui::page_rect(&self.hud,self.size).is_some_and(contains)||
            (self.hud.menu!=HudMenu::None&&contains(formal_ui::menu_rect(self.hud.menu,self.size,radius)))||
            (self.hud.messages&&contains(formal_ui::message_rect([w,h],((h+16.)*0.5).max(190.))))||
            self.hits.iter().any(|hit|{
                let gear=matches!(hit.action,Action::Hud(HudCommand::Menu(HudMenu::System)))&&hit.area[1]==0.;
                !matches!(hit.action,Action::Select(_)|Action::Resources(crate::resource_map::Command::Site(_)))&&contains(hit.area)&&(!gear||formal_ui::gear_hit(p,self.size[0]))
            })||
            (self.hud.page==HudPage::Map && match self.selected {
                Some(Object::Polity(_))=>false,
                Some(_)=>contains([17.,73.,300.,213.]),
                None=>false,
            })
    }
    pub(super) fn set_date(&mut self,date:Date) {
        if self.config.managed||self.config.world.is_some(){self.feedback="日期由正式世界时钟决定。".into();self.dirty=true;return;}
        self.state.date=date;
        if let Some(model)=self.state.timeline.as_mut(){model.set_date(date);}
        if self.selected.is_some_and(|o|!self.available(o)){self.select(None);}
        self.dirty=true;
    }
    pub(super) fn rotate(&mut self,from:[f64;2],to:[f64;2],bearing:bool) {
        self.focus=None;
        self.opening_nav.last_input = Instant::now();
        if bearing{self.camera.bearing_drag(from,to,self.size);}else{self.camera.drag(from,to,self.size);}
        self.camera.update_level();self.dirty=true;
    }
    pub(super) fn zoom(&mut self,p:[f64;2],steps:f64) {
        self.opening_nav.last_input = Instant::now();
        self.focus=None;self.velocity=[0.;2];self.camera.zoom(p,1.22f64.powf(-steps.clamp(-60.,60.)),self.size);self.dirty=true;
    }
}
