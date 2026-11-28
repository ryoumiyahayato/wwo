use crate::{
    formal_ui::{self, Display},
    lobby::{self, Command, Opening},
    overlay::Mesh,
    ui::Hit,
    compact::Raster,
    world::World,
};
use std::time::Instant;
use wwo_character_core::{
    Education, Family, Language, OpeningHealth, Prologue, Temperament, Youth,
};

pub const CHAPTER_FADE: std::time::Duration = std::time::Duration::from_millis(340);

const STAGES: [(&str, &str); 5] = [
    ("家庭", "Family"),
    ("教育", "Schooling"),
    ("青年经历", "Early work and study"),
    ("往事", "A past experience"),
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
struct Experience {
    story: (&'static str, &'static str),
    temperament: Temperament,
    health: Option<OpeningHealth>,
}

const EXPERIENCES: [Experience; 4] = [
    Experience {
        story: ("你跟熟人学做一件活，练了一个冬天，终于能独自做完。",
            "You spent a winter learning a job and could finally do it alone."),
        temperament: Temperament::Practice,
        health: None,
    },
    Experience {
        story: ("你跟家人送了一季货，渐渐能把重货搬完。",
            "You spent a season delivering goods and grew strong enough to carry heavy loads."),
        temperament: Temperament::Persist,
        health: Some(OpeningHealth::Strong),
    },
    Experience {
        story: ("邻家起火，你把人扶了出来，自己的腿受了伤。",
            "You helped someone escape a fire next door and injured your leg."),
        temperament: Temperament::Rescue,
        health: Some(OpeningHealth::OldInjury),
    },
    Experience {
        story: ("你病了大半年，后来才慢慢恢复做活。",
            "You were ill for most of a year and only slowly returned to work."),
        temperament: Temperament::Persist,
        health: Some(OpeningHealth::ProlongedIllness),
    },
];

#[derive(Clone)]
pub struct Draft {
    pub country: usize,
    pub stage: usize,
    pub previous_stage: Option<usize>,
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
            previous_stage: None,
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

    pub fn change_stage(&mut self, stage: usize) {
        self.previous_stage = Some(self.stage);
        self.stage = stage;
        self.changed = Instant::now();
    }

    fn experienced(&self, event: &Experience) -> bool {
        self.opening.temperament == event.temperament && self.health == event.health
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
                if let Some(event) = EXPERIENCES.get(index) {
                    self.opening.temperament = event.temperament;
                    self.health = event.health;
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
    setting: (&'static str, &'static str),
    school: (&'static str, &'static str),
    work: (&'static str, &'static str),
}

const SCENES: [Scene; 6] = [
    Scene {
        polity: "state:country_fra",
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

pub const SCENE_SIZE: [u32; 2] = [1672, 941];
const INK: [u8; 4] = [54, 33, 22, 255];
const FAINT_INK: [u8; 4] = [94, 67, 48, 255];

struct Art {
    data: &'static [u8],
    places: &'static [&'static str],
    anchor: [f32; 2],
    safe_width: f32,
}

const ART: [Art; 8] = [
    Art { data: include_bytes!("../../../data/character/prologue/paris.png"),
        places: &["place:paris"],
        anchor: [0.96, 0.40], safe_width: 0.40 },
    Art { data: include_bytes!("../../../data/character/prologue/london.png"),
        places: &["place:london"],
        anchor: [0.965, 0.42], safe_width: 0.41 },
    Art { data: include_bytes!("../../../data/character/prologue/berlin.png"),
        places: &["place:berlin"],
        anchor: [0.965, 0.48], safe_width: 0.42 },
    Art { data: include_bytes!("../../../data/character/prologue/petersburg.png"),
        places: &["place:st_petersburg", "place:saint_petersburg"],
        anchor: [0.96, 0.48], safe_width: 0.39 },
    Art { data: include_bytes!("../../../data/character/prologue/beijing.png"),
        places: &["place:beijing", "place:peking"],
        anchor: [0.04, 0.42], safe_width: 0.40 },
    Art { data: include_bytes!("../../../data/character/prologue/tokyo.png"),
        places: &["place:tokyo"],
        anchor: [0.045, 0.61], safe_width: 0.40 },
    Art { data: include_bytes!("../../../data/character/prologue/marseille.png"),
        places: &["place:marseille"],
        anchor: [0.044, 0.43], safe_width: 0.41 },
    Art { data: include_bytes!("../../../data/character/prologue/period.png"),
        places: &[],
        anchor: [0.96, 0.43], safe_width: 0.41 },
];

pub(crate) fn scene_index(opening: &Opening, place: &str) -> usize {
    ART.iter().position(|art| art.places.contains(&place))
        .or_else(|| SCENES.iter().position(|scene| scene.polity == opening.id)).unwrap_or(ART.len() - 1)
}

pub(crate) fn scene_raster(index: usize) -> std::io::Result<Raster> {
    let mut decoder = png::Decoder::new(ART[index].data);
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info()?;
    let mut bytes = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut bytes)?;
    bytes.truncate(info.buffer_size());
    let pixels = match info.color_type {
        png::ColorType::Rgb => bytes.chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect(),
        png::ColorType::Rgba => bytes,
        _ => return Err(std::io::Error::other("invalid opening scene pixels")),
    };
    Ok(Raster { size: [info.width, info.height], pixels })
}

fn paper_choice(
    skin: &formal_ui::Skin, surface: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>,
    area: [f32; 4], label: &str, command: Option<Command>, selected: bool, scale: f32,
) {
    let [x, y, w, h] = area;
    let fill = if selected { [190, 133, 70, 98] }
        else if command.is_some() { [245, 222, 177, 59] }
        else { [235, 219, 190, 45] };
    surface.rect(x, y, w, h, fill);
    if selected { surface.rect(x, y, 3., h, [112, 63, 31, 148]); }
    skin.paragraph(text, label, 0, [x + 9., y + 3., w - 18., h - 3.],
        if command.is_some() { INK } else { FAINT_INK }, scale);
    if let Some(command) = command { hits.push(Hit { area, action: lobby::action(command) }); }
}

impl Display<'_> {
    pub(crate) fn draw_prologue_reference(&self, surface: &mut Mesh, text: &mut Mesh, draft: &Draft, country: &Opening) {
        let image = &ART[scene_index(country, &draft.place)];
        if image.places.contains(&draft.place.as_str()) {
            return;
        }
        let label = if image.places.is_empty() {
            self.skin.choose("时代场景示意", "Illustrative period scene")
        } else {
            self.skin.choose("区域时代场景示意", "Illustrative regional scene")
        };
        let width = self.skin.width(label, 0) + 20.;
        let y = self.size[1] as f32 - 27.;
        surface.rect(14., y, width, 21., [52, 36, 25, 209]);
        self.skin.text(text, label, 0, [23., y + 2.], width - 16., formal_ui::IVORY);
    }

    pub(crate) fn draw_prologue(
        &self,
        art: &mut Mesh,
        paper: &mut Mesh,
        surface: &mut Mesh,
        text: &mut Mesh,
        hits: &mut Vec<Hit>,
        draft: &Draft,
        country: &Opening,
        world: &World,
    ) {
        let [width, height] = self.size.map(|n| n as f32);
        let skin = self.skin;
        let say = |zh, en| skin.choose(zh, en);
        let selection = country.sites.iter().find(|site| site.id == draft.place);
        let place = selection.map_or(country.label.as_str(), |site| skin.opening_name(world, &site.id, &site.label));
        let chosen = &draft.opening;
        let scene = SCENES.iter().find(|scene| scene.polity == country.id);
        let image = &ART[scene_index(country, &draft.place)];
        let aspect = width * SCENE_SIZE[1] as f32 / (height * SCENE_SIZE[0] as f32);
        let [u, v] = [0.5 * aspect.min(1.), 0.5 / aspect.max(1.)];
        art.image([0., 0., width, height], [0.5 - u, 0.5 - v, 0.5 + u, 0.5 + v], [255; 4]);

        let margin = (width * 0.028).clamp(14., 55.);
        let card_w = (width * image.safe_width).clamp(340., 635.).min(width - 2. * margin);
        let inner = card_w - 42.;
        let scale = (height / 635.).clamp(0.83, 1.10);
        let [horizontal, vertical] = image.anchor;
        let card_x = (width * horizontal - if horizontal >= 0.5 { card_w } else { 0. })
            .clamp(margin, width - margin - card_w);
        let text_width = inner;
        let context = format!("{place}  ·  1880–1900");
        let context_lines = skin.wrapped_lines(&context, 0, text_width, scale).len().max(1);
        let header_height = (57. + context_lines as f32 * 23.) * scale;
        let prompt_height = if draft.stage == 4 { 53. } else { 70. } * scale;
        let stride = if width < 1040. || skin.english() { 48. } else { 40. } * scale;
        let option_count = [3, 2, 4, EXPERIENCES.len(), 4][draft.stage];
        let card_h = header_height + prompt_height + option_count as f32 * stride + 57. * scale;
        let card_y = (height * vertical - card_h * 0.5).clamp(12., (height - card_h - 28.).max(12.));
        paper.image([card_x, card_y, card_w, card_h], [0., 0., 1., 1.], [255, 255, 255, 148]);
        surface.rect(card_x + 7., card_y + 4., card_w - 14., 1., [120, 82, 51, 73]);
        surface.rect(card_x + 7., card_y + card_h - 5., card_w - 14., 1., [120, 82, 51, 73]);
        let left = card_x + 21.;
        let (zh, en) = STAGES[draft.stage];
        skin.paragraph(text, say(zh, en), 1, [left, card_y + 16. * scale, text_width, 36. * scale], INK, 1.08 * scale);
        skin.paragraph(text, &context, 0, [left, card_y + 51. * scale, text_width, 23. * context_lines as f32 * scale],
            FAINT_INK, scale);
        let paragraph_top = card_y + header_height;
        let menu_top = paragraph_top + prompt_height;
        let ink = INK;
        let mut choice = |index, title: &str, enabled: bool, selected| {
            paper_choice(skin, surface, text, hits, [left, menu_top + stride * index as f32, inner, stride - 5.],
                title, enabled.then_some(Command::PrologueChoice(index)), selected, scale);
        };
        let family_intro;
        let prompt: &str = match draft.stage {
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
                family_intro = scene.map_or_else(
                    || say("你在这里出生。家里的生计，决定了你小时候可以把时间花在哪里。",
                        "You were born here. Your household’s livelihood shaped how you spent your childhood.").to_owned(),
                    |scene| format!("{}{}", say(scene.setting.0, scene.setting.1),
                        say("而你，就出生在这里。", " This is where you were born.")),
                );
                &family_intro
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
                        |scene| say(scene.school.0, scene.school.1),
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
                    |scene| say(scene.work.0, scene.work.1))
            }
            3 => {
                for (i, experience) in EXPERIENCES.iter().enumerate() {
                    choice(i, say(experience.story.0, experience.story.1), true, draft.experienced(experience));
                }
                say("独立生活前，你记得一件事。", "One event stands out from the years before you set out on your own.")
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
                    let story = EXPERIENCES.iter().find(|event| draft.experienced(event))
                        .map_or("", |event| say(event.story.0, event.story.1));
                    let details = [
                        format!("{} · {} · {}", say("20 岁", "Age 20"), education, youth),
                        story.to_owned(),
                        format!("{} · {}   |   {}", say("健康", "Health"), health, wealth),
                        format!("{} · {}", say("特质", "Traits"), traits),
                    ];
                    for (i, label) in details.iter().enumerate() {
                        skin.paragraph(
                            text,
                            label,
                            0,
                            [left, menu_top + i as f32 * stride, inner, stride - 5.],
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

        let foot = card_y + card_h - 44. * scale;
        let back = [left, foot, 86., 30. * scale];
        let next = [card_x + card_w - 134., foot, 113., 30. * scale];
        paper_choice(skin, surface, text, hits, back, say("返回", "Back"),
            Some(Command::PrologueBack), false, scale);
        let next_label = if draft.confirm() { say("进入世界", "Enter world") } else { say("继续", "Continue") };
        paper_choice(skin, surface, text, hits, next, next_label,
            Some(Command::PrologueNext), true, scale);
        let progress_x = (back[0] + back[2] + next[0]) * 0.5 - 29.;
        for i in 0..STAGES.len() {
            let color = if i <= draft.stage { [107, 65, 31, 255] } else { [152, 125, 92, 141] };
            surface.rect(progress_x + i as f32 * 13., foot + 13. * scale, 8., 3., color);
        }
    }
}
