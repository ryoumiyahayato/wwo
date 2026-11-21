use crate::{formal_ui::{self, Display, IVORY, MUTED}, lobby::{self, Command, Page}, overlay::Mesh, ui::Hit};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status { Complete, Partial, Missing, Cancelled }

const PER_PAGE: usize = 4;
type Entry = (&'static str, &'static str, &'static str);

impl Status {
    fn entries(self) -> &'static [Entry] {
        match self {
            Self::Complete => &[
                ("地图与交互", "Rust 绘制全球地貌、历史边界和专题图层。", "支持搜索、地点定位、标注、地图缩放和 PNG 截图。"),
                ("统一开局与时钟", "各人口统计区均可开局，六国保留原有人物序章。", "市场、人口、人物活动和工资共用正式时钟。"),
                ("Rust 原生存档", "支持手动保存、保存并退出和重启读档。", "恢复时钟、人物、人口、账本、合同、库存和市场。"),
                ("现有地标 3D", "铁塔、巴黎北站、耶拿桥、威斯敏斯特钟楼与桥已进入 Rust。", "柏林车站和吉萨金字塔也可搜索定位。"),
            ],
            Self::Partial => &[
                ("装甲陆战", "特鲁瓦军事网格实测 20 辆车交战及读档复查战果。", "战略部队、补给、更高精度高程和其他网格待接入或核查。"),
                ("海岸、水域与陆地", "Z0 至 Z7、几何水面、海面变化和农业地表已接入地图。", "继续核查海岸与水域，改善 Z5 至 Z7 材质和跨级切换。"),
                ("城市 3D", "巴黎和伦敦已有局部街区模型。", "仅对约 1900 年人口达到 10 万的城市建设完整景观。"),
                ("人物、工作与人口", "人物可跨区出行、迁居和通勤，人口迁移批次共用客座。", "更广的岗位与人口覆盖、医疗和继承待接入。"),
                ("市场、企业与运输", "宏观贸易、实物货运和人口流动按区间占用同一线路。", "港口货流按收货地交割。城市岗位目录与历史班表仍有缺口。"),
                ("政治与行政", "Rust 有历史边界、旗图、国家档案和部分行政资料。", "动态权属、正式组织操作和科技项目待接入。"),
                ("设置", "Rust 保存全屏、语言和音量设置。", "翻译补全、游戏音频和主题切换待接入。"),
            ],
            Self::Missing => &[
                ("战略军事、火炮与步兵", "R68 对照保留部署、补给和步兵训练。", "正式军队编制、部署、补给、独立火炮和步兵待接入。"),
                ("空战与海战", "空战沿用独立 Rust 开发。", "共享单位身份与状态后，继续接入正式世界。"),
            ],
            Self::Cancelled => &[
                ("Godot / R68 旧存档兼容", "已取消要求。正式游戏使用 Rust 原生存档。", "R68 工程保留作实现和素材参考。"),
            ],
        }
    }
}

impl Display<'_> {
    pub(crate) fn migration_status(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>, status: Status, page: usize, native: bool) {
        let [width, height] = self.size.map(|n| n as f32);
        let card_width = (width - 32.).min(990.);
        let x = (width - card_width) * 0.5;
        let y = (height - 450.) * 0.5;
        let left = x + 23.;
        let content_width = card_width - 46.;
        formal_ui::panel(panels, [x, y, card_width, 450.], [6, 14, 23, 250]);
        self.skin.text(text, "R68 迁移状态", 2, [left, y + 15.], content_width, IVORY);
        let runtime = if native {"当前会话使用 Rust 原生世界。"} else {"当前会话使用 R68 对照入口。以下为 Rust 迁移状态。"};
        self.skin.text(text, runtime, 0, [left, y + 47.], content_width, MUTED);

        let entries = status.entries();
        let pages = entries.len().div_ceil(PER_PAGE);
        let action = |status, page| Some(lobby::action(Command::Page(Page::Migration(status, page))));
        let tabs = [(Status::Complete, "已进入 Rust"), (Status::Partial, "部分实现"),
            (Status::Missing, "未接入"), (Status::Cancelled, "已取消要求")];
        let tab_width = (content_width - 24.) / tabs.len() as f32;
        for (index, (item, label)) in tabs.into_iter().enumerate() {
            self.row(panels, text, hits, [left + index as f32 * (tab_width + 8.), y + 77., tab_width, 30.],
                label, action(item, 0), status == item);
        }
        for (index, (title, running, missing)) in entries.iter().skip(page * PER_PAGE).take(PER_PAGE).enumerate() {
            let top = y + 117. + index as f32 * 70.;
            panels.rect(left, top, content_width, 65., [13, 24, 33, 255]);
            self.skin.text(text, title, 1, [left + 10., top + 3.], content_width - 20., IVORY);
            self.skin.text(text, running, 0, [left + 10., top + 27.], content_width - 20., IVORY);
            self.skin.text(text, missing, 0, [left + 10., top + 44.], content_width - 20., MUTED);
        }

        if pages > 1 {
            self.row(panels, text, hits, [left, y + 405., 92., 30.], "上一页", page.checked_sub(1).and_then(|previous| action(status, previous)), false);
            self.skin.text(text, &format!("{} / {pages}", page + 1), 0, [left + 102., y + 412.], 70., MUTED);
            self.row(panels, text, hits, [left + 176., y + 405., 92., 30.], "下一页", (page + 1 < pages).then(|| action(status, page + 1)).flatten(), false);
        }
        self.row(panels, text, hits, [x + card_width - 135., y + 405., 112., 30.], "返回主菜单", Some(lobby::action(Command::Page(Page::Home))), false);
    }
}
