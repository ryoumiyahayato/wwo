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
            ],
            Self::Partial => &[
                ("开局、界面与时钟", "Rust 绘制菜单、加载和钟盘。后台 R68 创建世界、推进、暂停和调速。", "Rust 有独立时钟和调度模块。游戏未接入。国家档案和消息跳转仍缺。"),
                ("地图与资料覆盖", "Rust 包含 282 张 R68 区域地表分片、181 条地点、87 个法国历史省。", "仍缺完整行政与地点资料、铁路、航运、原版细级切换和水系精度。"),
                ("人物、关系与科技", "Rust 计算人物健康、衰老、市场与工作经验；头像打开人物资料。", "R68 管理身份、人口、账目、物品、合同和组织。项目提交与完整组织操作仍缺。"),
                ("市场、交易与经济数据", "Rust 有市场、行情、报价、订单和购买。报价、扣款、交付由 R68 执行。", "Rust 独立命令行只写入法国开局首笔鲁昂粮食采购。产业结构图含静态史料。"),
                ("政治与行政", "Rust 读取 1900 年历史边界、旗图和部分行政资料，可选中与定位。", "实时权属、辖区、机构与人口状态由 R68 持有。完整档案及联动未接入。"),
                ("军事入口", "Rust 有法国方格和训练开关。训练运行时、会话和 3D 窗口仍是 R68。", "方格用于显示。正式空间单元、编组、部署、补给和裁决未移植。"),
                ("设置", "Rust 控制全屏、标注、语言界面。主音量交给 Godot 音频应用。", "翻译覆盖有限。主题管理只显示当前主题。背景音乐选项在两边均未显示。"),
                ("存档", "R68 执行正式槽位、自动保存和世界恢复。Rust 人物状态保存在同一正式槽位。", "旧正式槽可读；带 Rust 人物状态的新槽需要本候选。"),
            ],
            Self::Missing => &[
                ("人物事件与企业经营", "伤病来源、正式死亡结算、继承和教育玩法尚未接通。", "迁居、旅行、工资、消费、仓储、企业生产和融资仍在 R68。"),
                ("正式世界与领域数据", "Rust 尚无可独立续玩的正式世界。人物、人口、组织、领土、市场由 R68 装载。", "历史证据与完整运行数据仍依赖原项目。Rust 只有选取数据和法国开局样本。"),
                ("战略军事与隔离训练", "编组、部署、补给、战果状态及训练物理、车辆、车组和步兵仍在 R68。", "战略动作按原领域代码核对，玩家菜单覆盖与实机操作待核。"),
                ("城市和地标 3D", "巴黎近景在 Rust 使用楼廓和道路栅格。原版楼体、地标和局部场景留在 R68。", "未迁入铁塔、巴黎北站、耶拿桥、威斯敏斯特钟楼与桥、柏林车站、吉萨金字塔。"),
            ],
        }
    }
}

impl Display<'_> {
    pub(crate) fn migration_status(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>, status: Status, page: usize) {
        let [width, height] = self.size.map(|n| n as f32);
        let card_width = (width - 32.).min(990.);
        let x = (width - card_width) * 0.5;
        let y = (height - 450.) * 0.5;
        let left = x + 23.;
        let content_width = card_width - 46.;
        formal_ui::panel(panels, [x, y, card_width, 450.], [6, 14, 23, 250]);
        self.skin.text(text, "R68 迁移状态", 2, [left, y + 15.], content_width, IVORY);
        self.skin.text(text, "当前候选的界面和地图由 Rust 绘制，正式世界由后台 R68 / Godot 运行。", 0, [left, y + 47.], content_width, MUTED);

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
