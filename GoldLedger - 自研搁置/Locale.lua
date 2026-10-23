-- 金账簿 - Locale.lua
-- 全部面向用户的文案集中在这里。将来要做多语言，只需换掉这一个文件。

local ADDON_NAME, GL = ...
local L = {}
GL.L = L

L.ADDON      = "金账簿"
L.TAG        = "|cff8ab4f8金账簿|r"

-- 判定词：只描述【数字】，不描述【人】。这是一条硬约束，改文案时别破坏它。
L.VERDICT = {
    PENDING  = "扫描中…",
    FAR      = "太远",
    HIDDEN   = "身份被隐藏",
    THIN     = "数据太少",
    FRESH    = "历史空白，峰值巨大",
    BANK     = "仓库号形态",
    GAP      = "峰值无法解释",
    CLEAN    = "数字自洽",
}

L.VERDICT_DESC = {
    THIN  = "五个必需的计数器没有全部读到，无法判断。",
    FRESH = "低等级角色却有很高的历史峰值。",
    BANK  = "拍卖行重度使用，但几乎没有战斗和任务记录。",
    GAP   = "记录到的收入不足以解释历史峰值。",
    CLEAN = "收入与峰值大致对得上。",
}

-- ⚠️ 免责声明必须与判定同显，不能只放在报告里。
L.DISCLAIMER = "无法解释不等于 RMT"

L.MISSING = {
    unresolved = "未识别",
    noapi      = "无接口",
    restricted = "被限制",
    skipped    = "被隐藏",
    error      = "读取失败",
    unreported = "未上报",
    format     = "格式未知",
    readable   = "已读到",
}

L.CMD = {
    HELP       = "命令：/gl help 查看全部",
    NO_API     = "这个客户端没有成就统计对比接口。",
    NO_IDS     = "统计量还没识别出来。先打开角色面板→统计，然后运行 /gl probe",
    RESOLVED   = "已识别 %d/%d 个统计量。",
    SELF_ONLY  = "只能读自己的钱包。",
    SCAN_LATER = "扫描功能将在 M4 加入。",
}
