use crate::{
    formal_ui::{self, Display, IVORY, MUTED},
    lobby::{Command, Opening},
    overlay::Mesh,
    ui::{Action, Hit},
};
use wwo_character_core::{Education, Family, Prologue, Temperament, Youth};

const STAGES: [(&str, &str); 6] = [
    ("年龄", "Age"),
    ("家庭", "Family"),
    ("童年教育", "Childhood education"),
    ("青年经历", "Early work and study"),
    ("性情", "Temperament"),
    ("人物确认", "Review character"),
];
const AGES: [u8; 3] = [18, 20, 25];
const FAMILIES: [Family; 3] = [Family::Poor, Family::Ordinary, Family::Wealthy];
const EDUCATION: [Education; 2] = [Education::HomeWork, Education::ReadingLessons];
const YOUTH: [Youth; 4] = [
    Youth::Labor,
    Youth::Apprentice,
    Youth::CommercialAssistant,
    Youth::AdvancedStudy,
];
const TEMPERAMENTS: [Temperament; 7] = [
    Temperament::Practice,
    Temperament::Persist,
    Temperament::Endure,
    Temperament::Recover,
    Temperament::Struggle,
    Temperament::Leave,
    Temperament::Illness,
];

pub struct Draft {
    pub country: usize,
    pub stage: usize,
    pub opening: Prologue,
}

impl Draft {
    pub fn new(country: usize) -> Self {
        Self {
            country,
            stage: 0,
            opening: Prologue {
                age: 18,
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
    }

    pub fn choose(&mut self, index: usize) {
        let current = &mut self.opening;
        match self.stage {
            0 => {
                if let Some(&value) = AGES.get(index) {
                    current.age = value;
                }
            }
            1 => {
                if let Some(&value) = FAMILIES.get(index) {
                    current.family = value;
                }
            }
            2 => {
                if let Some(&value) = EDUCATION.get(index) {
                    current.education = value;
                }
            }
            3 => {
                if let Some(&value) = YOUTH
                    .get(index)
                    .filter(|youth| youth.eligible(current.age, current.education))
                {
                    current.youth = value;
                }
            }
            4 => {
                if let Some(&value) = TEMPERAMENTS.get(index) {
                    current.temperament = value;
                }
            }
            _ => (),
        }
        if !current.youth.eligible(current.age, current.education) {
            current.youth = Youth::Labor;
        }
    }
}

impl Display<'_> {
    pub(crate) fn draw_prologue(
        &self,
        m: &mut Mesh,
        t: &mut Mesh,
        hits: &mut Vec<Hit>,
        draft: &Draft,
        country: &Opening,
    ) {
        let [width, height] = self.size.map(|n| n as f32);
        let w = (width - 40.).min(664.);
        let h = 454.;
        let x = (width - w) * 0.5;
        let y = ((height - h) * 0.5).max(12.);
        formal_ui::panel(m, [x, y, w, h], [8, 17, 26, 251]);
        let skin = self.skin;
        let say = |zh, en| skin.choose(zh, en);
        let stage = draft.stage;
        let action = |command| Some(Action::Hud(formal_ui::Command::Lobby(command)));
        let (zh, en) = STAGES[stage];
        skin.text(t, say(zh, en), 1, [x + 26., y + 17.], w - 52., IVORY);
        skin.text(
            t,
            &format!(
                "{} · 1900 · {} / {}",
                country.label,
                stage + 1,
                STAGES.len()
            ),
            0,
            [x + 26., y + 53.],
            w - 52.,
            MUTED,
        );
        m.rect(x + 26., y + 80., w - 52., 1., formal_ui::BRASS);
        let opening = draft.opening;
        let mut row = |index, label: &str, enabled, selected| {
            let stride = if stage == 4 { 33. } else { 43. };
            self.row(
                m,
                t,
                hits,
                [
                    x + 26.,
                    y + 147. + index as f32 * stride,
                    w - 52.,
                    stride - 5.,
                ],
                label,
                if enabled {
                    action(Command::PrologueChoice(index))
                } else {
                    None
                },
                selected,
            );
        };
        if draft.confirm() {
            let development = opening
                .build(country.language.expect("native opening language"))
                .expect("validated draft");
            let cash = opening
                .family
                .opening_cash(country.cash.unwrap_or_default());
            skin.text(
                t,
                &format!(
                    "{} · {} {} · {}",
                    country.place,
                    opening.age,
                    say("岁", "years old"),
                    opening.family.label()
                ),
                0,
                [x + 26., y + 97.],
                w - 52.,
                IVORY,
            );
            for (index, past) in development.history().iter().enumerate().skip(1) {
                skin.text(
                    t,
                    &format!("{}-{}  {}", past.start_year, past.end_year, past.label),
                    0,
                    [x + 26., y + 122. + index as f32 * 29.],
                    w - 52.,
                    IVORY,
                );
            }
            let reading = if development.can_read(development.language()) {
                say("识字", "Reads")
            } else {
                say("未识字", "Cannot read")
            };
            skin.text(
                t,
                &format!(
                    "{reading} · {} · {} {}",
                    development.language().label(),
                    say("开局现金", "Opening cash"),
                    cash
                ),
                0,
                [x + 26., y + 249.],
                w - 52.,
                IVORY,
            );
            let traits = development.trait_labels().collect::<Vec<_>>().join("、");
            skin.text(
                t,
                &format!(
                    "{} · {}  |  {}",
                    say("特质", "Traits"),
                    traits,
                    if development.opening_injury() > 0 {
                        say("有旧伤", "Old injury")
                    } else if opening.temperament == Temperament::Illness {
                        say("病后恢复中", "Recovering from illness")
                    } else {
                        say("健康良好", "In good health")
                    }
                ),
                0,
                [x + 26., y + 278.],
                w - 52.,
                IVORY,
            );
            skin.text(
                t,
                say(
                    "开局财产采用开发假设。",
                    "Opening cash is a simulation assumption.",
                ),
                0,
                [x + 26., y + 313.],
                w - 52.,
                MUTED,
            );
        } else {
            match stage {
                0 => {
                    for (i, age) in AGES.into_iter().enumerate() {
                        row(
                            i,
                            &format!("{age} {}", say("岁", "years old")),
                            true,
                            age == opening.age,
                        );
                    }
                }
                1 => {
                    for (i, family) in FAMILIES.into_iter().enumerate() {
                        let name = if skin.english() {
                            ["Poor", "Ordinary", "Wealthy"][i]
                        } else {
                            family.label()
                        };
                        let cash = family.opening_cash(country.cash.unwrap_or_default());
                        row(
                            i,
                            &format!("{name}  ·  {} {cash}", say("开局现金", "Opening cash")),
                            true,
                            family == opening.family,
                        );
                    }
                }
                2 => {
                    for (i, education) in EDUCATION.into_iter().enumerate() {
                        let label = match (skin.english(), education, opening.family) {
                            (true, Education::HomeWork, _) => {
                                "Helped at home without reading lessons"
                            }
                            (true, _, Family::Poor) => "Borrowed books and learned from neighbours",
                            (true, _, Family::Ordinary) => "Learned at a local school",
                            (true, _, Family::Wealthy) => "Learned with a private tutor",
                            (false, Education::HomeWork, _) => education.label(),
                            (false, _, family) => family.childhood_schooling(),
                        };
                        row(i, label, true, education == opening.education);
                    }
                }
                3 => {
                    for (i, youth) in YOUTH.into_iter().enumerate() {
                        let label = if skin.english() {
                            [
                                "Manual work",
                                "Workshop apprenticeship",
                                "Helped a merchant with stock and deliveries",
                                "Continued in education",
                            ][i]
                        } else {
                            youth.label()
                        };
                        let allowed = youth.eligible(opening.age, opening.education);
                        let row_label = if allowed {
                            label.to_owned()
                        } else {
                            format!(
                                "{label} · {}",
                                say("须年满 20 岁并识字", "Requires age 20 and reading lessons")
                            )
                        };
                        row(i, &row_label, allowed, youth == opening.youth);
                    }
                }
                4 => {
                    for (i, choice) in TEMPERAMENTS.into_iter().enumerate() {
                        let label = if skin.english() {
                            [
                                "Ask for help, learn quickly and practise",
                                "Divide the work and finish each part",
                                "Build strength gradually",
                                "Rest for a season after an injury",
                                "Learn slowly but practise daily",
                                "Often move on before a task is done",
                                "Return to work after a long illness",
                            ][i]
                        } else {
                            choice.label()
                        };
                        row(i, label, true, choice == opening.temperament);
                    }
                }
                _ => (),
            }
            let prompt = match stage {
                0 => say(
                    "1900 年初，你几岁？",
                    "How old are you at the start of 1900?",
                ),
                1 => say(
                    "离家时，家里能给你留下多少现钱？",
                    "How much cash can your family leave you?",
                ),
                2 => say(
                    "小时候，你如何度过白天？",
                    "How did you spend your days as a child?",
                ),
                3 => say(
                    "成年以前及开局前，你做过什么？",
                    "What did you do before the opening?",
                ),
                _ => say(
                    "十六岁那年，你如何面对工作或身体上的难处？",
                    "At sixteen, how did you deal with difficulties at work or with your health?",
                ),
            };
            skin.paragraph(t, prompt, 0, [x + 26., y + 97., w - 52., 47.], IVORY, 1.);
        }
        self.row(
            m,
            t,
            hits,
            [x + 26., y + h - 53., 151., 32.],
            say("返回", "Back"),
            action(Command::PrologueBack),
            false,
        );
        self.row(
            m,
            t,
            hits,
            [x + w - 177., y + h - 53., 151., 32.],
            if draft.confirm() {
                say("进入世界", "Enter world")
            } else {
                say("继续", "Continue")
            },
            action(Command::PrologueNext),
            true,
        );
    }
}
