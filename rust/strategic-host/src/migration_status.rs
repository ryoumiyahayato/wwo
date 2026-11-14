use crate::{formal_ui::{self, Display, IVORY, MUTED}, lobby::{self, Command, Page}, overlay::Mesh, ui::Hit};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status { Complete, Partial, Missing }

const PER_PAGE: usize = 4;
type Entry = (&'static str, &'static str, &'static str);

impl Status {
    fn entries(self) -> &'static [Entry] {
        match self {
            Self::Complete => &[
                ("全球与区域地图", "Rust 绘制地球和区域地貌，处理旋转、惯性、指针缩放、方位和返回。", "底图和分片由 Rust 读取。数据复用 R68，城市与局部场景见部分迁移。"),
                ("地图基础交互", "Rust 执行国家和地点拾取、搜索、首都定位、法国历史省界高亮。", "政治旗图、标注开关和法国 25 / 50 km 方格由 Rust 绘制。"),
                ("本地显示与截图", "窗口、全屏、地图名称显隐和 PNG 截图由 Rust 执行。", "全屏偏好由 Rust 写入候选配置。地图名称每次开局默认关闭。"),
                ("统一开局与时钟", "默认入口由 Rust 创建同一个 1900 年世界。六国选择决定玩家身份和所在地。", "跨日、市场、人物和工资共用 Rust 正式时钟。"),
                ("Rust 存档", "Rust 执行手动保存、保存并退出和重启读档。", "恢复人物、时钟、人口、账本、合同、库存、市场及在途货物。"),
            ],
            Self::Partial => &[
                ("地图与资料覆盖", "Rust 包含 282 张 R68 区域地表分片、181 条地点、87 个法国历史省。", "仍缺完整行政与地点资料、铁路、航运、原版细级切换和水系精度。"),
                ("人物、工作与关系", "Rust 执行人物衰老、学习、巴黎招聘和工资，使用原开局账户。", "完整组织操作、地区就业和科技项目仍缺。"),
                ("市场、交易与运输", "Rust 执行 50 个统计市场日结、个人现货交易和统计货运交付。", "地区商户、个人配送、企业生产和融资仍留在 R68。"),
                ("政治与行政", "Rust 读取 1900 年历史边界、旗图、人口和部分行政资料。", "动态权属、行政和组织联动仍留在 R68。"),
                ("军事入口", "Rust 有法国方格和训练开关。训练运行时、会话和 3D 窗口仍是 R68。", "方格用于显示。正式空间单元、编组、部署、补给和裁决未移植。"),
                ("设置", "Rust 控制全屏和标注。", "翻译覆盖有限，主音量和主题选择尚未迁移。"),
                ("旧存档兼容", "原有 R68 槽位保留在 R68 对照入口。", "Rust 大厅尚不能直接读取旧世界。"),
            ],
            Self::Missing => &[
                ("人物事件", "伤病来源、医疗、休息、正式死亡结算、继承和教育玩法尚未接通。", "原版迁居和客运仍留在 R68。"),
                ("战略军事与隔离训练", "编组、部署、补给、战果状态及训练物理、车辆、车组和步兵仍在 R68。", "战略动作按原领域代码核对，玩家菜单覆盖与实机操作待核。"),
                ("城市和地标 3D", "巴黎近景在 Rust 使用楼廓和道路栅格。原版楼体、地标和局部场景留在 R68。", "未迁入铁塔、巴黎北站、耶拿桥、威斯敏斯特钟楼与桥、柏林车站、吉萨金字塔。"),
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
        let tabs = [(Status::Complete, "已完成"), (Status::Partial, "部分迁移"), (Status::Missing, "未迁移")];
        let tab_width = (content_width - 16.) / 3.;
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
