use crate::{
    formal_ui::{self, Display, IVORY, MUTED},
    lobby::{self, Command, Opening, Selection},
    overlay::Mesh,
    ui::Hit,
};
use std::time::Instant;
use wwo_character_core::{
    Education, Family, Language, OpeningHealth, Prologue, Temperament, Youth,
};

const STAGES: [(&str, &str); 5] = [
    ("家庭", "Family"),
    ("教育", "Schooling"),
    ("青年经历", "Early work and study"),
    ("性情", "Temperament"),
    ("人物确认", "Review character"),
];
const FAMILIES: [Family; 3] = [Family::Poor, Family::Ordinary, Family::Wealthy];
const EDUCATION: [Education; 2] = [Education::HomeWork, Education::ReadingLessons];
const YOUTH: [Youth; 4] = [
    Youth::Labor,
    Youth::Apprentice,
    Youth::CommercialAssistant,
    Youth::AdvancedStudy,
];
const TEMPERAMENTS: [Temperament; 4] = [
    Temperament::Practice,
    Temperament::Persist,
    Temperament::Struggle,
    Temperament::Leave,
];
const HEALTH: [Option<OpeningHealth>; 4] = [
    None,
    Some(OpeningHealth::Strong),
    Some(OpeningHealth::OldInjury),
    Some(OpeningHealth::ProlongedIllness),
];

pub struct Draft {
    pub country: usize,
    pub stage: usize,
    pub place: String,
    pub changed: Instant,
    pub opening: Prologue,
    pub health: Option<OpeningHealth>,
    language: Option<Language>,
}

impl Draft {
    pub fn new(country: usize, place: String, language: Option<Language>) -> Self {
        Self {
            country,
            stage: 0,
            place,
            changed: Instant::now(),
            health: None,
            language,
            opening: Prologue {
                age: 20,
                family: Family::Ordinary,
                education: Education::HomeWork,
                youth: Youth::Labor,
                temperament: Temperament::Practice,
            },
        }
    }

    pub fn confirm(&self) -> bool {
        self.stage == STAGES.len() - 1
    }

    pub fn advance(&mut self) {
        self.stage = (self.stage + 1).min(STAGES.len() - 1);
        self.changed = Instant::now();
    }

    pub fn set_health(&mut self, index: usize) {
        if self.stage == 3 {
            if let Some(value) = HEALTH.get(index) {
                self.health = *value;
            }
        }
    }

    pub fn choose(&mut self, index: usize) {
        match self.stage {
            0 => {
                if let Some(&value) = FAMILIES.get(index) {
                    self.opening.family = value;
                }
            }
            1 => {
                if let Some(&value) = EDUCATION
                    .get(index)
                    .filter(|&&value| value != Education::ReadingLessons || self.language.is_some())
                {
                    self.opening.education = value;
                }
            }
            2 => {
                if let Some(&value) = YOUTH
                    .get(index)
                    .filter(|youth| youth.eligible(self.opening.age, self.opening.education))
                {
                    self.opening.youth = value;
                }
            }
            3 => {
                if let Some(&value) = TEMPERAMENTS.get(index) {
                    self.opening.temperament = value;
                }
            }
            _ => (),
        }
        if !self
            .opening
            .youth
            .eligible(self.opening.age, self.opening.education)
        {
            self.opening.youth = Youth::Labor;
        }
    }
}

struct Scene {
    polity: &'static str,
    city: (&'static str, &'static str),
    setting: (&'static str, &'static str),
    school: (&'static str, &'static str),
    work: (&'static str, &'static str),
}

const SCENES: [Scene; 6] = [
    Scene {
        polity: "state:country_fra",
        city: ("巴黎，里沃利街", "Rue de Rivoli, Paris"),
        setting: (
            "石砌公寓楼下，店铺在天亮时打开木百叶。赶集的人穿过街道。",
            "Shopkeepers opened their wooden shutters beneath stone apartments as people headed to market.",
        ),
        school: (
            "小学的课桌上有石板，也有练习写信和算账的本子。",
            "At primary school, slates and exercise books served for arithmetic and letter writing.",
        ),
        work: (
            "裁缝铺收布料，商号要清点货物。家里开始问你打算学哪一门手艺。",
            "Tailors took in cloth and merchants counted consignments. Your family asked which trade you would learn.",
        ),
    },
    Scene {
        polity: "state:british_isles_1900",
        city: ("伦敦，皮卡迪利广场", "Piccadilly Circus, London"),
        setting: (
            "砖房的窗台覆着煤灰。出门做活的人在街角等马拉公共车。",
            "Coal dust settled on brick windowsills. Workers waited at street corners for horse buses.",
        ),
        school: (
            "初等学校教读书和算术，同一条街上也有孩子早早进店帮工。",
            "Elementary schools taught reading and arithmetic. On the same streets, some children helped in shops.",
        ),
        work: (
            "工场看守工具，铺子登记赊账。能写字便多了一种谋生办法。",
            "Workshops kept track of tools and shops kept books of credit. Writing gave you another way to earn.",
        ),
    },
    Scene {
        polity: "state:german_empire",
        city: (
            "柏林，国会大厦与胜利纪念柱",
            "Reichstag and Victory Column, Berlin",
        ),
        setting: (
            "石铺街道通向新建的车站。工人在上工时换下外套，围上围裙。",
            "Paved streets led to new stations. Workers changed from coats into aprons at the workshop.",
        ),
        school: (
            "初等学校教读写和算术。要进工场学艺，还得让师傅愿意收徒。",
            "Elementary school taught literacy and arithmetic. A workshop apprenticeship still required a willing master.",
        ),
        work: (
            "工场靠图样和样件交班。商店则用账本核对货款和交运日期。",
            "Workshops passed on drawings and samples. Shops checked accounts against shipments.",
        ),
    },
    Scene {
        polity: "state:russian_empire",
        city: ("圣彼得堡，涅瓦大街", "Nevsky Prospect, Saint Petersburg"),
        setting: (
            "冬天的长外衣和柴火要早作打算。赶车的人沿着大道来到集市。",
            "Long winter coats and firewood had to be arranged early. Carriages came down the avenue toward market.",
        ),
        school: (
            "教区学校和地方自治机构办的小学都能教读写。能否上学取决于住处和家里的安排。",
            "Parish and local schools taught reading and writing. Access depended on where a family lived and what it could arrange.",
        ),
        work: (
            "运粮、修车和抄写订单都能谋生。家人问你要跟熟人干活，还是再读几年书。",
            "Hauling grain, fixing carts and copying orders could earn a living. Your family asked whether you would work or study longer.",
        ),
    },
    Scene {
        polity: "state:qing_empire",
        city: ("北京，皇城街道", "Street in the Imperial City, Beijing"),
        setting: (
            "灰砖院墙外是摆摊的街面。挑担的人把蔬菜和日用品送到铺前。",
            "Stalls lined the street outside gray brick courtyards. Porters carried vegetables and household goods to the shops.",
        ),
        school: (
            "有的孩子在家做活，有的跟塾师识字。笔墨纸张也占家里的开销。",
            "Some children worked at home, while others studied with a tutor. Brushes, ink and paper cost money.",
        ),
        work: (
            "铺里有人清点来货、抄记账目，也有人跟师傅学用工具。你得选一条路。",
            "Shops needed goods counted and ledgers copied. Others learned tools from a master. You had to choose a path.",
        ),
    },
    Scene {
        polity: "state:empire_of_japan",
        city: ("东京，银座街道", "Ginza Street, Tokyo"),
        setting: (
            "木铺仍在营业，别处已有砖楼。街上木屐声和人力车铃声交错。",
            "Wooden shops still did business where brick buildings were spreading. Wooden clogs sounded alongside rickshaw bells.",
        ),
        school: (
            "明治年间的小学校里，孩子读课本、练书写。家里的生计也影响能上多久学。",
            "Meiji-era pupils read textbooks and practised writing. Family livelihoods shaped how long they could stay at school.",
        ),
        work: (
            "商铺收货时要核对件数。学徒先看师傅怎样理货，熟练后才能独自做。",
            "Shops checked deliveries by the piece. Apprentices watched their masters sort goods before working alone.",
        ),
    },
];

impl Display<'_> {
    pub(crate) fn draw_prologue(
        &self,
        art: &mut Mesh,
        surface: &mut Mesh,
        text: &mut Mesh,
        hits: &mut Vec<Hit>,
        draft: &Draft,
        country: &Opening,
        navigation: &Selection,
    ) {
        let [width, height] = self.size.map(|n| n as f32);
        surface.rect(0., 0., width, height, [6, 14, 23, 255]);
        let compact = width < 740.;
        let margin = (width * 0.037).clamp(13., 52.);
        let frame_w = width - 2. * margin;
        let top = (height * 0.06).clamp(10., 42.);
        let bottom = height - top;
        let image_w = if compact {
            frame_w
        } else {
            (frame_w * 0.48).min(620.)
        };
        let image_h = if compact {
            (height * 0.23)
                .min(154.)
                .min((bottom - top - 318.).max(62.))
        } else {
            (image_w * 0.75).min(bottom - top - 73.)
        };
        let image_rect = [margin, top, image_w, image_h];
        let card_x = if compact {
            margin
        } else {
            margin + image_w + 19.
        };
        let card_y = if compact { top + image_h + 23. } else { top };
        let card_w = width - margin - card_x;
        let card_h = (bottom - card_y).max(184.);
        let scale = (card_h / 535.).clamp(0.52, 1.).min((card_h - 42.) / 366.);
        let selection = country.sites.iter().find(|site| site.id == draft.place);
        let place = selection.map_or(country.label.as_str(), |site| site.label.as_str());
        let skin = self.skin;
        let say = |zh, en| skin.choose(zh, en);
        let chosen = &draft.opening;
        let scene = SCENES
            .iter()
            .enumerate()
            .find(|(_, scene)| scene.polity == country.id);
        let alpha = if navigation.motion {
            let t = (draft.changed.elapsed().as_secs_f32() / 0.32).clamp(0., 1.);
            (100. + 155. * t) as u8
        } else {
            255
        };
        let ink = [IVORY[0], IVORY[1], IVORY[2], alpha];

        if let Some((index, scene)) = scene {
            let x = (index % 3) as f32 * 384.;
            let y = (index / 3) as f32 * 288.;
            let ratio = (image_w / image_h.max(1.)) * 0.75;
            let du = 191. * ratio.min(1.);
            let dv = 143. / ratio.max(1.);
            let [cx, cy] = [x + 192., y + 144.];
            art.image(
                image_rect,
                [
                    (cx - du) / 1152.,
                    (cy - dv) / 576.,
                    (cx + du) / 1152.,
                    (cy + dv) / 576.,
                ],
                [255, 255, 255, alpha],
            );
            let caption = format!(
                "{} · {}",
                say(scene.city.0, scene.city.1),
                say("同期影像参考", "Period reference")
            );
            skin.text(
                text,
                &caption,
                0,
                [margin + 1., top + image_h + 2.],
                image_w,
                MUTED,
            );
        } else {
            formal_ui::panel(surface, image_rect, [13, 26, 37, 255]);
            let metadata = format!("1880–1900  ·  {place}");
            skin.paragraph(
                text,
                &metadata,
                1,
                [margin + 18., top + image_h * 0.38, image_w - 36., 77.],
                ink,
                0.95,
            );
        }
        formal_ui::panel(surface, [card_x, card_y, card_w, card_h], [10, 20, 31, 255]);
        let left = card_x + 16.;
        let inner = card_w - 32.;
        let (zh, en) = STAGES[draft.stage];
        skin.text(
            text,
            say(zh, en),
            1,
            [left, card_y + 10. * scale],
            inner,
            ink,
        );
        let context = if compact {
            format!("{place} · 1880–1900")
        } else {
            format!("{} / {place} · 1880–1900", country.label)
        };
        skin.paragraph(
            text,
            &context,
            0,
            [left, card_y + 42. * scale, inner, 33. * scale],
            MUTED,
            scale,
        );

        let paragraph_top = card_y + 76. * scale;
        let menu_top = card_y + 154. * scale;
        let stride = 39. * scale;
        let mut choice = |index, title: &str, enabled: bool, selected| {
            self.row(
                surface,
                text,
                hits,
                [left, menu_top + stride * index as f32, inner, stride - 4.],
                "",
                enabled.then_some(lobby::action(Command::PrologueChoice(index))),
                selected,
            );
            skin.paragraph(
                text,
                title,
                0,
                [
                    left + 7.,
                    menu_top + stride * index as f32 + 3.,
                    inner - 14.,
                    stride - 4.,
                ],
                if enabled { ink } else { MUTED },
                scale,
            );
        };

        let prompt = match draft.stage {
            0 => {
                let choices = [
                    say(
                        "家里靠零工过日子，能留给你的东西不多。",
                        "Your family lived on day work and could spare little.",
                    ),
                    say(
                        "家里有稳定生计，可以供你慢慢学一门手艺。",
                        "A steady livelihood gave you time to learn a trade.",
                    ),
                    say(
                        "家里有余裕请人教导，也有钱让你继续求学。",
                        "Your family could afford a tutor and further studies.",
                    ),
                ];
                for (i, label) in choices.into_iter().enumerate() {
                    choice(i, label, true, FAMILIES[i] == chosen.family);
                }
                scene.map_or(
                    say(
                        "家里的生计，决定了你小时候可以把时间花在哪里。",
                        "Your household’s livelihood shaped how you spent your childhood.",
                    ),
                    |(_, scene)| say(scene.setting.0, scene.setting.1),
                )
            }
            1 => {
                let lesson = match chosen.family {
                    Family::Poor => say(
                        "借书，在能抽身时请人教读写。",
                        "Borrow books and find someone to teach you when work allows.",
                    ),
                    Family::Ordinary => say(
                        "到附近上课，学读写和算术。",
                        "Take lessons nearby and learn reading, writing and arithmetic.",
                    ),
                    Family::Wealthy => say(
                        "在家跟老师学读写和算术。",
                        "Study reading, writing and arithmetic with a tutor at home.",
                    ),
                };
                choice(
                    0,
                    say(
                        "留在家里帮工，没上读写课。",
                        "Help at home without reading lessons.",
                    ),
                    true,
                    chosen.education == Education::HomeWork,
                );
                choice(
                    1,
                    lesson,
                    draft.language.is_some(),
                    chosen.education == Education::ReadingLessons,
                );
                if draft.language.is_none() {
                    say(
                        "这里尚未接入可学的阅读语言。",
                        "No reading language is configured for this opening.",
                    )
                } else {
                    scene.map_or(
                        say(
                            "到了上学的年纪，家里要决定怎样安排你的白天。",
                            "At school age, your family had to arrange how you spent your days.",
                        ),
                        |(_, scene)| say(scene.school.0, scene.school.1),
                    )
                }
            }
            2 => {
                for (i, youth) in YOUTH.into_iter().enumerate() {
                    let labels = [
                        say(
                            "接体力活，跟着熟人上工。",
                            "Take manual work alongside people you know.",
                        ),
                        say(
                            "进工场，跟师傅学一门手艺。",
                            "Join a workshop and learn from a master.",
                        ),
                        say(
                            "帮商户记账、清点货物。",
                            "Keep a merchant’s books and count goods.",
                        ),
                        say(
                            "继续读书，准备需要读写的工作。",
                            "Continue studying for work that needs literacy.",
                        ),
                    ];
                    let enabled = youth.eligible(chosen.age, chosen.education);
                    let label = if enabled {
                        labels[i].to_owned()
                    } else {
                        format!("{} {}", labels[i], say("须识字", "Literacy required"))
                    };
                    choice(i, &label, enabled, chosen.youth == youth);
                }
                scene.map_or(say("接近成年时，你得决定先谋生，还是继续学习。", "As adulthood approached, you had to choose between earning a living and studying."),
                    |(_, scene)| say(scene.work.0, scene.work.1))
            }
            3 => {
                let labels = [
                    say(
                        "问清做法，再反复练习。",
                        "Ask how and practise until it works.",
                    ),
                    say(
                        "把事情分开，一件件做完。",
                        "Break the work into parts and finish each.",
                    ),
                    say(
                        "哪怕学得慢，也每天练。",
                        "Practise daily, even when learning is slow.",
                    ),
                    say(
                        "做到一半，常转去做别的。",
                        "Move on to something else before finishing.",
                    ),
                ];
                for (i, label) in labels.into_iter().enumerate() {
                    choice(i, label, true, TEMPERAMENTS[i] == chosen.temperament);
                }
                let y = menu_top + stride * 4. + 2. * scale;
                skin.text(
                    text,
                    say("身体经历", "Health history"),
                    0,
                    [left, y],
                    inner,
                    MUTED,
                );
                let health = [
                    say("平常", "Typical"),
                    say("强健", "Robust"),
                    say("旧伤", "Old injury"),
                    say("久病", "Long illness"),
                ];
                for (i, label) in health.into_iter().enumerate() {
                    let w = inner / 4.;
                    self.row(
                        surface,
                        text,
                        hits,
                        [left + w * i as f32, y + 23. * scale, w - 3., 28. * scale],
                        label,
                        Some(lobby::action(Command::PrologueHealth(i))),
                        HEALTH[i] == draft.health,
                    );
                }
                match chosen.youth {
                    Youth::Labor => say(
                        "遇到一件怎么也干不顺的活，你会怎么做？",
                        "A job is giving you trouble. How do you handle it?",
                    ),
                    Youth::Apprentice => say(
                        "师傅交代的功课总做不好，你会怎么做？",
                        "You keep getting a task from your master wrong. What do you do?",
                    ),
                    Youth::CommercialAssistant => say(
                        "铺子里的账目总对不上，你会怎么做？",
                        "The shop’s accounts won’t balance. What do you do?",
                    ),
                    Youth::AdvancedStudy => say(
                        "读书时遇到难解的一页，你会怎么做？",
                        "You keep getting stuck on a page. What do you do?",
                    ),
                }
            }
            _ => {
                if let Ok(development) = chosen.build_with_health(draft.language, draft.health) {
                    let health = match draft.health {
                        Some(OpeningHealth::OldInjury) => say("有旧伤", "Old injury"),
                        Some(OpeningHealth::ProlongedIllness) => say("久病", "History of illness"),
                        Some(OpeningHealth::Strong) => say("体魄强健", "Robust"),
                        None => say("健康良好", "In good health"),
                    };
                    let wealth = match chosen.family {
                        Family::Poor => say("家计紧张", "Limited means"),
                        Family::Ordinary => say("有基本积蓄", "Some savings"),
                        Family::Wealthy => say("家庭资助充足", "Family support"),
                    };
                    let education = if chosen.education == Education::ReadingLessons {
                        say("受过读写教育", "Reading and writing")
                    } else {
                        say("家中帮工", "Work at home")
                    };
                    let traits = development.trait_labels().collect::<Vec<_>>().join("、");
                    let youth_en = [
                        "Manual work",
                        "Apprenticeship",
                        "Merchant’s assistant",
                        "Continued study",
                    ];
                    let youth = if skin.english() {
                        youth_en[YOUTH
                            .iter()
                            .position(|&youth| youth == chosen.youth)
                            .unwrap_or(0)]
                    } else {
                        chosen.youth.label()
                    };
                    let details = [
                        format!("{} · {} · {}", say("20 岁", "Age 20"), education, youth),
                        format!("{} · {}   |   {}", say("健康", "Health"), health, wealth),
                        format!("{} · {}", say("特质", "Traits"), traits),
                    ];
                    for (i, label) in details.iter().enumerate() {
                        skin.paragraph(
                            text,
                            label,
                            0,
                            [left, menu_top + i as f32 * 42. * scale, inner, 40. * scale],
                            ink,
                            scale,
                        );
                    }
                }
                say(
                    "1900 年 1 月 1 日，你准备开始独立生活。",
                    "On 1 January 1900, you are ready to make a life of your own.",
                )
            }
        };
        skin.paragraph(
            text,
            prompt,
            0,
            [left, paragraph_top, inner, 68. * scale],
            ink,
            scale,
        );

        let foot = card_y + card_h - 38.;
        let back = [left, foot, 83., 29.];
        let next = [card_x + card_w - 114., foot, 98., 29.];
        self.row(
            surface,
            text,
            hits,
            back,
            say("返回", "Back"),
            Some(lobby::action(Command::PrologueBack)),
            false,
        );
        let next_label = if draft.confirm() {
            say("进入世界", "Enter world")
        } else {
            say("继续", "Continue")
        };
        self.row(
            surface,
            text,
            hits,
            next,
            next_label,
            Some(lobby::action(Command::PrologueNext)),
            true,
        );
        let progress_x = (back[0] + back[2] + next[0]) * 0.5 - 29.;
        for i in 0..STAGES.len() {
            let color = if i <= draft.stage {
                formal_ui::BRASS
            } else {
                [74, 82, 83, 255]
            };
            surface.rect(progress_x + i as f32 * 13., foot + 13., 8., 3., color);
        }
    }
}
