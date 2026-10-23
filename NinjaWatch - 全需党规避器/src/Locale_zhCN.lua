-- NinjaWatcher - 全需党规避器
-- Locale_zhCN.lua: Chinese strings. Keep the keys stable; other locale files
-- can provide the same keys.

local ADDON, NW = ...

NW.strings = {
    TITLE = "NinjaWatch - 全需党规避器",
    SUBTITLE = "基于公开成就统计的需求/贪婪掷骰计数，仅供参考。",
    VERSION = "版本 %s",
    VERSION_BETA = "版本 %s · 测试版",

    TAB_PLAYERS = "玩家",
    TAB_OPTIONS = "选项",

    TOOLTIP_LABEL = "需求掷骰行为",
    TOOLTIP_PENDING = "扫描中…",
    TOOLTIP_UNKNOWN = "数据不可读",
    TOOLTIP_INSUFFICIENT = "数据不足",
    TOOLTIP_PASS = "低",
    TOOLTIP_RATE = "需求率 %.1f%% · %s",
    TOOLTIP_PASS_DETAIL = "合计掷骰次数 %d < 门槛 %.1f（进入地下城次数 %d）",
    TOOLTIP_THRESHOLD = "门槛 %.1f（进入地下城次数 %d）",
    TOOLTIP_RED_CAP = "合计掷骰次数<30，最高只显示黄档",
    TOOLTIP_INSUFFICIENT_DETAIL = "至少需要进入地下城次数≥%d",
    TOOLTIP_STATUS_FAR = "距离太远",
    -- BUSY only means another scan is in flight right now; it is not a
    -- property of the hovered player. Same wording and ellipsis as PENDING so
    -- both waiting states read as "still fetching".
    TOOLTIP_STATUS_BUSY = "扫描中…",
    TOOLTIP_STATUS_COMBAT = "战斗中",
    TOOLTIP_STATUS_NOAPI = "客户端不支持成就对比",
    TOOLTIP_STATUS_TIMEOUT = "扫描超时",
    TOOLTIP_STATUS_NODATA = "没有可读统计",
    TOOLTIP_STATUS_RETRY = "再次悬停可重试",
    TOOLTIP_UNKNOWN_FIELD = "字段「%s」不可读",

    BAND_DARKGREEN = "正常",
    BAND_GREEN = "正常",
    BAND_YELLOW = "偏高",
    BAND_RED = "极高",
    BAND_GRAY = "样本少",
    BAND_UNKNOWN = "未知",

    FIELD_NEED = "需求掷骰次数",
    FIELD_GREED = "贪婪掷骰次数",
    FIELD_ENTRIES = "进入地下城次数",
    FIELD_ROLLS = "合计掷骰次数",

    STATUS_READABLE = "可读",
    STATUS_ZERO = "0/未报告",
    STATUS_UNKNOWN = "未知",
    STATUS_RESTRICTED = "受限",
    STATUS_FORMAT = "格式不支持",
    STATUS_SKIPPED = "客户端标记为隐藏",
    STATUS_API = "统计接口不可用",
    STATUS_ERROR = "统计接口报错",
    STATUS_UNREPORTED = "没有报告值",

    ALERT_YELLOW = "队伍中「%s」的需求率偏高：%.1f%%（需求掷骰次数 %d，贪婪掷骰次数 %d，进入地下城次数 %d，合计掷骰次数 %d）。仅本地提示。",
    ALERT_RED = "玩家%s疑似全需党，ta在%d次战利品掷骰中选择需求了%d次。请留意。（数据来自公开成就统计，仅供参考，不构成决策建议）",
    ALERT_RED_LOCAL = "「%s」需求率极高：%.1f%%（需求掷骰次数 %d，贪婪掷骰次数 %d，进入地下城次数 %d，合计掷骰次数 %d）。仅本地提示。",
    ALERT_RED_BLOCKED = "红档提示未发送：当前不是 5 人小队。",

    SETTINGS_PLAYERS_TITLE = "已扫描的玩家",
    SETTINGS_PLAYERS_HINT = "记录只保存在本机 WTF，不会上传。把鼠标移到队友身上即可扫描；也可以点击下面的按钮。",
    SETTINGS_EMPTY = "还没有扫描记录。把鼠标移到队友身上，或点击“扫描队伍”。",
    SETTINGS_SCAN_PARTY = "扫描队伍",
    SETTINGS_CLEAR_ALL = "清除全部记录",
    SETTINGS_CLEAR_CONFIRM = "再次点击确认清除",
    SETTINGS_CLEAR_DONE = "已清除 %d 条本地记录。",
    SETTINGS_SORT_RECENT = "排序：最近",
    SETTINGS_SORT_RATE = "排序：需求率",
    SETTINGS_COUNT = "共 %d 名玩家（本地记录）",
    SETTINGS_SCAN_STARTED = "开始扫描队伍，共 %d 人。",
    SETTINGS_SCAN_NONE = "当前没有可扫描的小队成员。",

    COL_NAME = "玩家",
    COL_LEVEL = "等级",
    COL_NEED = "需求",
    COL_GREED = "贪婪",
    COL_ENTRIES = "进入地下城",
    COL_ROLLS = "合计",
    COL_RATE = "需求率",
    COL_BAND = "档位",
    COL_TIME = "最后扫描",
    TABLE_LEGEND = "列含义：需求=需求掷骰次数，贪婪=贪婪掷骰次数，进入地下城=进入地下城次数，合计=需求+贪婪。",
    TABLE_PASS = "低",
    TABLE_INSUFFICIENT = "数据不足",
    TABLE_UNKNOWN = "未知",
    TABLE_ROW_DETAIL = "需求掷骰次数 %d　贪婪掷骰次数 %d\n进入地下城次数 %d　合计掷骰次数 %d\n需求率：%s\n判定：%s\n最后扫描：%s",
    RATE_HINT = "需求率 = 需求掷骰次数/合计掷骰次数，用以提供需求行为的参考。",

    -- The entry appended to the unit popup (right-click a portrait).
    MENU_DETAIL = "详细掷骰行为",
    -- BETA(0.2.0): the tester marks a player as a need-everything ninja.
    MENU_REPORT = "报告全需玩家",
    MENU_UNREPORT = "取消报告",
    CHAT_REPORT_ON = "已报告「%s」为全需玩家，样本已记录。",
    CHAT_REPORT_QUEUED = "已标记该玩家，扫描完成后自动补记计数。",
    CHAT_REPORT_OFF = "已取消该玩家的报告标记。",
    CHAT_REPORT_NO_GUID = "拿不到这名玩家的标识，无法标记。",

    OPTIONS_TITLE = "显示与提示",
    OPTIONS_TOOLTIP = "鼠标提示中显示需求率",
    OPTIONS_SELF = "鼠标指向自己时也显示",
    OPTIONS_LOCAL = "黄档在本地聊天框提示（不发队伍）",
    OPTIONS_PARTY = "红档自动发送队伍频道",
    OPTIONS_PARTY_WARN = "开启后，红档玩家会被队友看到。默认关闭。",
    OPTIONS_RULE_TITLE = "判定规则",
    OPTIONS_RULE_TEXT =
        "需求掷骰次数（成就 1044）、贪婪掷骰次数（1043）与进入地下城次数（932）都取自公开成就统计；合计掷骰次数 = 需求 + 贪婪。\n" ..
        "「低」档（放弃型）：合计掷骰次数 < 5.4×进入地下城次数 − max(3, 0.81×进入地下城次数)，此时不计算需求率。\n" ..
        "其余玩家看需求率：<50% 正常，50–70% 偏高（仅本地），≥70% 极高（且合计掷骰次数 ≥30）。\n" ..
        "合计掷骰次数 <20 时需求率显示为样本少；进入地下城次数 <4 时整个判定显示数据不足。",
    OPTIONS_PRIVACY_TITLE = "隐私",
    OPTIONS_PRIVACY_TEXT =
        "所有记录只写入本机 SavedVariables（NinjaWatcherDB），不上传、不写邮件、不发起交易。\n" ..
        "红档队伍提示默认关闭；开启后只在 5 人小队发送一次，并对同一玩家做冷却去重。",
    OPTIONS_RESET = "恢复默认设置",
    OPTIONS_RESET_DONE = "已恢复默认设置。",

    CHAT_PREFIX = "|cff66ccffNinjaWatcher|r",
    CHAT_HELP_TITLE = "命令：",
    CHAT_HELP_OPEN = "/nw — 打开设置",
    CHAT_HELP_SCAN = "/nw scan — 扫描当前小队",
    CHAT_HELP_STATUS = "/nw status — 查看自己的计数与判定",
    CHAT_HELP_TEST = "/nw test — 运行内置判定测试",
    CHAT_HELP_CLEAR = "/nw clear — 清除本地记录（需二次确认）",
    CHAT_CLEAR_ASK = "这会删除全部本地玩家记录与已报告的全需样本。再次输入 /nw clear confirm 确认。",
    CHAT_CLEAR_DONE = "已清除 %d 条本地记录。",
    CHAT_CLEAR_CANCEL = "已取消清除。",
    CHAT_STATUS = "自己：需求掷骰次数=%d，贪婪掷骰次数=%d，进入地下城次数=%d，合计掷骰次数=%d；%s。",
    CHAT_STATUS_RATE = "%s（需求率 %.1f%%）",
    CHAT_STATUS_UNKNOWN = "自己的统计数据不可读（%s）。",
    CHAT_TEST_TITLE = "内置判定测试：",
    CHAT_TEST_OK = "通过 %d / %d",
    CHAT_TEST_FAIL = "失败 %d 项",
    CHAT_DEBUG = "扫描状态：%s；队列：%d；本地记录：%d；对比接口：%s。",
    CHAT_NO_SETTINGS = "此客户端没有 Settings 面板接口，无法打开设置页。",
    CHAT_NO_MENU_API = "此客户端没有 Menu 接口，右键菜单项不可用。",
    CHAT_NO_MENU_OPEN = "当前没有打开的菜单（右键头像后再查）。",
    CHAT_MENU_TAGS = "当前打开的菜单标签：%s",
    CHAT_ADDON_LOADED = "已加载。输入 /nw 打开设置。",
}
