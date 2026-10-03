--[[
==========================================================
 Loader.lua —— PatriotHub 模块加载器
==========================================================
 职责：
   1. 从 BASE 拉取远程 Lua 文件
   2. 缓存已拉取内容（避免重复请求）
   3. 编译并执行模块
   4. 返回模块实例
==========================================================
]]

local Loader = {}

-- 缓存
Loader.__cache = {}   -- [relPath] = module 实例
Loader.__raw   = {}   -- [relPath] = 原始源码
Loader.__base  = nil  -- BASE URL

-- ==========================================================
-- 设置 BASE
-- ==========================================================
function Loader.setBase(url)
    if url:sub(-1) ~= "/" then
        url = url .. "/"
    end
    Loader.__base = url
end

function Loader.getBase()
    return Loader.__base
end

-- ==========================================================
-- 拉取原始源码
-- ==========================================================
function Loader.fetch(relPath)
    -- 命中缓存
    if Loader.__raw[relPath] then
        return Loader.__raw[relPath]
    end

    if not Loader.__base then
        error("[Loader] 未设置 BASE，请先调用 setBase()")
    end

    local url = Loader.__base .. relPath
    local ok, src = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok or not src or src == "" then
        error("[Loader] 拉取失败: " .. url)
    end

    Loader.__raw[relPath] = src
    return src
end

-- ==========================================================
-- 加载模块（返回模块实例）
-- ==========================================================
function Loader.req(relPath)
    -- 命中缓存
    if Loader.__cache[relPath] then
        return Loader.__cache[relPath]
    end

    local src = Loader.fetch(relPath)

    local fn = loadstring(src)
    if not fn then
        error("[Loader] 编译失败: " .. relPath)
    end

    local ok, mod = pcall(fn)
    if not ok then
        error("[Loader] 运行失败: " .. relPath .. " -> " .. tostring(mod))
    end

    Loader.__cache[relPath] = mod
    return mod
end

-- ==========================================================
-- 清空缓存（热重载用）
-- ==========================================================
function Loader.clear(relPath)
    if relPath then
        Loader.__cache[relPath] = nil
        Loader.__raw[relPath] = nil
    else
        Loader.__cache = {}
        Loader.__raw = {}
    end
end

-- ==========================================================
-- 打印加载状态
-- ==========================================================
function Loader.info()
    local count = 0
    for _ in pairs(Loader.__cache) do
        count = count + 1
    end
    print("[Loader] BASE: " .. tostring(Loader.__base))
    print("[Loader] 已加载模块: " .. count)
    for path in pairs(Loader.__cache) do
        print("  - " .. path)
    end
end

return Loader--[[
==========================================================
 Main.lua —— PatriotHub 入口
==========================================================
 用户执行：
   loadstring(game:HttpGet("你的仓库/Main.lua"))()
==========================================================
]]

-- ★★★ 改这里：换成你自己仓库地址 ★★★
local BASE = "https://raw.githubusercontent.com/cheng2026-tech/fictional-funicular/main/"

-- ==========================================================
-- 兼容补丁（防止老脚本崩溃）
-- ==========================================================
if not _G.wait  then _G.wait  = task.wait  end
if not _G.spawn then _G.spawn = task.spawn end
if not _G.delay then _G.delay = task.delay end

-- ==========================================================
-- 加载 Loader
-- ==========================================================
local Loader = loadstring(game:HttpGet(BASE .. "Loader.lua"))()
Loader.setBase(BASE)
_G.PatriotLoader = Loader

print("[PatriotHub] Loader 已就绪")

-- ==========================================================
-- 加载 Core 模块
-- ==========================================================
local Services     = Loader.req("Core/Services")
local Util         = Loader.req("Core/Util")
local State        = Loader.req("Core/State")
local Storage      = Loader.req("Core/Storage")
local Logger       = Loader.req("Core/Logger")
local Mirror       = Loader.req("Core/Mirror")
local NotifyHub    = Loader.req("Core/NotifyHub")
local ScriptLoader = Loader.req("Core/ScriptLoader")

-- ==========================================================
-- 初始化 Logger
-- ==========================================================
Logger.setLevel("info")
Logger.setConsole(true)
Logger.info("Main", "启动 PatriotHub")

-- ==========================================================
-- 初始化 Mirror
-- ==========================================================
Mirror.init(game.HttpGet, Logger, NotifyHub.notify)
Logger.info("Main", "Mirror 初始化完成")

-- ==========================================================
-- 注入到 State（关键）
-- ==========================================================
State.Logger       = Logger
State.Mirror       = Mirror
State.ScriptLoader = ScriptLoader

-- ==========================================================
-- 加载 WindUI
-- ==========================================================
local WindUI = Logger.try("WindUI", function()
    return loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
    ))()
end)

if not WindUI then
    Logger.error("Main", "WindUI 加载失败")
    return
end
Logger.info("Main", "WindUI 加载成功")

NotifyHub.setWindUI(WindUI)
_G.__PatriotWindUI = WindUI

-- ==========================================================
-- 依赖注入
-- ==========================================================
ScriptLoader.hooks.notify = NotifyHub.notify

-- 加载鲸鱼
local ok, Whale = pcall(function() return Loader.req("EasterEgg/Whale") end)
if ok and Whale then
    ScriptLoader.hooks.say = Whale.say
    Whale.hooks.notify     = NotifyHub.notify
    State.Whale            = Whale
end

-- ==========================================================
-- UI 装配
-- ==========================================================
local Themes = Loader.req("UI/Themes")
local Window = Loader.req("UI/Window")
local Widget = Loader.req("UI/Widget")

Themes.register(WindUI)
Widget.init(WindUI)

local MainWindow = Window.build(WindUI)
if not MainWindow then
    Logger.error("Main", "窗口创建失败")
    return
end
State.Window = MainWindow

-- ==========================================================
-- 加载所有 Tab
-- ==========================================================
local TabList = {
    "UI/Tabs/Notice",
    "UI/Tabs/About",
    "UI/Tabs/Main",
    "UI/Tabs/Scripts",
    "UI/Tabs/Favorites",
    "UI/Tabs/Info",
    "UI/Tabs/UISettings",
    "UI/Tabs/ScriptTool",
    "UI/Tabs/PlayerTool",
    "UI/Tabs/GameTool",
    "UI/Tabs/Settings",
}

for _, path in ipairs(TabList) do
    local ok2, mod = pcall(function() return Loader.req(path) end)
    if ok2 and type(mod) == "function" then
        pcall(mod, MainWindow)
        Logger.info("Main", "Tab 加载: " .. path)
    else
        Logger.warn("Main", "Tab 加载失败: " .. path)
    end
end

-- ==========================================================
-- 启动玩家进出通知
-- ==========================================================
pcall(function()
    local PN = Loader.req("Features/PlayerNotice")
    if PN and PN.init then PN.init() end
end)

-- ==========================================================
-- 启动鲸鱼
-- ==========================================================
if Whale and Whale.startLoops then
    Whale.startLoops()
end

-- ==========================================================
-- 启动通知
-- ==========================================================
NotifyHub.notify(
    "爱国者 Hub 已加载",
    "版本 1.0 · 由大肥鱼维护",
    5,
    "bell-ring"
)

Logger.info("Main", "启动完成")

print("═══════════════════════════════════════")
print("  爱国者 Hub 已启动")
print("  作者：大肥鱼")
print("═══════════════════════════════════════")

return true--[[
==========================================================
 Core/Services.lua —— 服务集中引用
==========================================================
 所有模块通过这里拿服务，方便统一管理
==========================================================
]]

local Services = {}

Services.Players   = game:GetService("Players")
Services.TS        = game:GetService("TeleportService")
Services.HS        = game:GetService("HttpService")
Services.RS        = game:GetService("RunService")
Services.Stats     = game:GetService("Stats")
Services.Tween     = game:GetService("TweenService")
Services.VIM       = game:GetService("VirtualInputManager")
Services.Lighting  = game:GetService("Lighting")
Services.MPS       = game:GetService("MarketplaceService")
Services.UIS       = game:GetService("UserInputService")

Services.plr       = Services.Players.LocalPlayer

return Services--[[
==========================================================
 Core/Util.lua —— 通用工具
==========================================================
 提供：
   - try      : pcall 封装（记录日志）
   - tryCall  : 方法调用保护
   - safeUI   : UI 创建保护
   - compatSetDesc : 兼容不同版本的 Desc 更新
   - strContains  : 安全的字符串包含
   - getUIParent  : 获取 UI 父级（gethui 优先）
   - inputGet     : 兼容不同版本的 Input 取值
==========================================================
]]

local Util = {}

-- 缓存 Logger 引用（避免每次 req）
local _logger = nil
local function getLogger()
    if not _logger then
        _logger = _G.PatriotLoader and _G.PatriotLoader.req("Core/Logger")
    end
    return _logger
end

-- ==========================================================
-- 基础 try
-- ==========================================================
function Util.try(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        local L = getLogger()
        if L then L.error("Util.try", tostring(res)) end
        return nil
    end
    return res
end

-- ==========================================================
-- tryCall（方法调用保护）
-- ==========================================================
function Util.tryCall(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    return Util.try(function() return obj[method](obj, ...) end)
end

-- ==========================================================
-- safeUI（UI 创建保护）
-- ==========================================================
function Util.safeUI(parent, method, opts)
    if not parent or type(parent[method]) ~= "function" then
        return nil
    end
    return Util.try(function() return parent[method](parent, opts) end)
end

-- ==========================================================
-- 兼容不同版本的 Desc 设置
-- ==========================================================
function Util.compatSetDesc(obj, text)
    if not obj then return end
    if type(obj.SetDesc) == "function" then
        Util.try(function() obj:SetDesc(text) end)
    elseif type(obj.Set) == "function" then
        Util.try(function() obj:Set({ Desc = text }) end)
    elseif type(obj.SetTitle) == "function" then
        Util.try(function() obj:SetTitle(text) end)
    end
end

-- ==========================================================
-- 字符串包含（plain 匹配，防止模式字符）
-- ==========================================================
function Util.strContains(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" then
        return false
    end
    return string.find(haystack, needle, 1, true) ~= nil
end

-- ==========================================================
-- 获取 UI 父级
-- ==========================================================
function Util.getUIParent()
    -- 优先 gethui（执行器隐藏 UI 用）
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end

    -- 其次 CoreGui
    local ok2, core = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and core then return core end

    -- 兜底 PlayerGui
    return game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
end

-- ==========================================================
-- Input 取值（兼容多版本）
-- ==========================================================
function Util.inputGet(input)
    if not input then return nil end
    return Util.tryCall(input, "Get")
        or Util.tryCall(input, "GetValue")
        or Util.tryCall(input, "GetText")
end

-- ==========================================================
-- 深度拷贝（浅拷贝 table）
-- ==========================================================
function Util.shallowCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

-- ==========================================================
-- 数字 clamp
-- ==========================================================
function Util.clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

return Util--[[
==========================================================
 Core/State.lua —— 全局状态
==========================================================
 所有模块共享的状态表
==========================================================
]]

return {
    -- ========== 防护 ==========
    AntiAFK           = false,
    AntiAFKThread     = nil,
    BlockKick         = false,
    OriginalKick      = nil,
    AntiAFKProtect    = false,
    AntiAFKProtThread = nil,

    -- ========== 性能 ==========
    FPS               = 0,
    FpsThread         = nil,

    -- ========== 脚本加载 ==========
    Loading           = false,
    LastScript        = { name = nil, url = nil },

    -- ========== 玩家 ==========
    SelectedPlayer    = nil,

    -- ========== UI 设置 ==========
    NoticeDuration    = 4,
    SoundEnabled      = true,
    CustomTitle       = "爱国者 Hub",
    UIScale           = 1,

    -- ========== 玩家进出通知 ==========
    PlayerNoticeEnabled  = true,
    PlayerNoticeDuration = 3,
    PlayerNoticeMaxCount = 5,

    -- ========== 依赖注入（Main 里赋值） ==========
    Window            = nil,
    Logger            = nil,
    Mirror            = nil,
    ScriptLoader      = nil,
    Whale             = nil,
}--[[
==========================================================
 Core/Storage.lua —— 本地持久化
==========================================================
 用 JSON 文件存储：
   - 配置
   - 收藏
   - 历史
   - 备注
==========================================================
]]

local HS = game:GetService("HttpService")
local Storage = {}

-- ==========================================================
-- 路径常量
-- ==========================================================
Storage.ConfigPath    = "PatriotHub_Config.json"
Storage.FavoritesPath = "PatriotHub_Favorites.json"
Storage.HistoryPath   = "PatriotHub_History.json"
Storage.NotesPath     = "PatriotHub_Notes.json"

-- ==========================================================
-- 读 JSON
-- ==========================================================
function Storage.read(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return nil
    end
    if not isfile(path) then return nil end

    local ok, content = pcall(readfile, path)
    if not ok or not content then return nil end

    local ok2, data = pcall(function() return HS:JSONDecode(content) end)
    if ok2 and type(data) == "table" then return data end
    return nil
end

-- ==========================================================
-- 写 JSON
-- ==========================================================
function Storage.write(path, data)
    if type(writefile) ~= "function" then return false end
    return pcall(function()
        writefile(path, HS:JSONEncode(data))
    end)
end

-- ==========================================================
-- 加载初始数据
-- ==========================================================
Storage.Favorites = Storage.read(Storage.FavoritesPath) or {}
Storage.History   = Storage.read(Storage.HistoryPath) or {}
Storage.Notes     = Storage.read(Storage.NotesPath) or {}

-- ==========================================================
-- 历史记录
-- ==========================================================
function Storage.addHistory(name)
    table.insert(Storage.History, { name = name, time = os.time() })
    while #Storage.History > 50 do
        table.remove(Storage.History, 1)
    end
    Storage.write(Storage.HistoryPath, Storage.History)
end

function Storage.clearHistory()
    Storage.History = {}
    Storage.write(Storage.HistoryPath, Storage.History)
end

-- ==========================================================
-- 收藏
-- ==========================================================
function Storage.addFavorite(name)
    Storage.Favorites[name] = true
    Storage.write(Storage.FavoritesPath, Storage.Favorites)
end

function Storage.removeFavorite(name)
    Storage.Favorites[name] = nil
    Storage.write(Storage.FavoritesPath, Storage.Favorites)
end

function Storage.isFavorite(name)
    return Storage.Favorites[name] == true
end

-- ==========================================================
-- 备注
-- ==========================================================
function Storage.setNote(name, text)
    Storage.Notes[name] = text
    Storage.write(Storage.NotesPath, Storage.Notes)
end

function Storage.getNote(name)
    return Storage.Notes[name]
end

return Storage--[[
==========================================================
 Core/Logger.lua —— 统一日志
==========================================================
 功能：
   1. 分级日志（debug / info / warn / error）
   2. 内存缓冲（最近 200 条）
   3. 可选持久化（定时 flush）
   4. Logger.try 包装 pcall
==========================================================
]]

local Logger = {}

-- ==========================================================
-- 配置
-- ==========================================================
Logger._config = {
    enabled     = true,
    level       = "info",
    maxHistory  = 200,
    console     = true,
    persist     = false,
    persistPath = "PatriotHub_Log.txt",
}

Logger._LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
Logger._history = {}
Logger._dirty = false

-- ==========================================================
-- 内部
-- ==========================================================
function Logger._should(level)
    if not Logger._config.enabled then return false end
    local min = Logger._LEVELS[Logger._config.level] or 2
    local cur = Logger._LEVELS[level] or 2
    return cur >= min
end

function Logger._fmt(level, tag, msg)
    return string.format("[%s][%s][%s] %s",
        os.date("%H:%M:%S"),
        level:upper(),
        tag or "?",
        tostring(msg))
end

-- ==========================================================
-- 核心 log
-- ==========================================================
function Logger.log(level, tag, msg)
    if not Logger._should(level) then return end

    local entry = {
        time  = os.time(),
        level = level,
        tag   = tag,
        msg   = tostring(msg),
    }

    table.insert(Logger._history, entry)
    while #Logger._history > Logger._config.maxHistory do
        table.remove(Logger._history, 1)
    end

    if Logger._config.console then
        local line = Logger._fmt(level, tag, msg)
        if level == "error" or level == "warn" then
            warn(line)
        else
            print(line)
        end
    end

    if Logger._config.persist then
        Logger._dirty = true
    end
end

-- ==========================================================
-- 快捷方法
-- ==========================================================
function Logger.debug(tag, msg) Logger.log("debug", tag, msg) end
function Logger.info (tag, msg) Logger.log("info",  tag, msg) end
function Logger.warn (tag, msg) Logger.log("warn",  tag, msg) end
function Logger.error(tag, msg) Logger.log("error", tag, msg) end

-- ==========================================================
-- try 包装
-- ==========================================================
function Logger.try(tag, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        Logger.error(tag, tostring(res))
        return nil
    end
    return res
end

-- ==========================================================
-- 导出
-- ==========================================================
function Logger.getRecent(n)
    n = n or 20
    local start = math.max(1, #Logger._history - n + 1)
    local out = {}
    for i = start, #Logger._history do
        table.insert(out, Logger._history[i])
    end
    return out
end

function Logger.export()
    local lines = {}
    for _, e in ipairs(Logger._history) do
        table.insert(lines, Logger._fmt(e.level, e.tag, e.msg))
    end
    return table.concat(lines, "\n")
end

-- ==========================================================
-- 文件持久化
-- ==========================================================
function Logger._flush()
    if type(writefile) ~= "function" then return end
    if not Logger._dirty then return end
    local ok = pcall(function()
        writefile(Logger._config.persistPath, Logger.export())
    end)
    if ok then Logger._dirty = false end
end

-- 定时 flush（每 30 秒）
task.spawn(function()
    while true do
        task.wait(30)
        Logger._flush()
    end
end)

function Logger.clear()
    Logger._history = {}
end

-- ==========================================================
-- 配置
-- ==========================================================
function Logger.setLevel(level)
    if Logger._LEVELS[level] then
        Logger._config.level = level
    end
end

function Logger.setEnabled(enabled)
    Logger._config.enabled = enabled
end

function Logger.setConsole(enabled)
    Logger._config.console = enabled
end

function Logger.setPersist(enabled)
    Logger._config.persist = enabled
end

-- ==========================================================
-- 启动信息
-- ==========================================================
Logger.info("Logger", "日志系统启动，级别：" .. Logger._config.level)

return Logger--[[
==========================================================
 Core/Mirror.lua —— 资源镜像自动切换
==========================================================
 功能：
   1. 给定 URL 自动生成多个镜像
   2. 按顺序尝试，成功即返回
   3. 记住成功源，下次优先
   4. 失败源计数
==========================================================
]]

local Mirror = {}

-- 依赖注入
Mirror._HttpGet = game.HttpGet
Mirror._Logger  = nil
Mirror._Notify  = nil

function Mirror.init(httpGet, logger, notify)
    if httpGet then Mirror._HttpGet = httpGet end
    if logger  then Mirror._Logger  = logger  end
    if notify  then Mirror._Notify  = notify  end
end

-- ==========================================================
-- 镜像规则
-- ==========================================================
Mirror.RULES = {
    -- GitHub raw → jsDelivr
    {
        match = "^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/(.+)$",
        build = "https://cdn.jsdelivr.net/gh/%1/%2@%3",
        name  = "jsDelivr",
    },
    -- GitHub raw → Statically
    {
        match = "^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/(.+)$",
        build = "https://cdn.statically.io/gh/%1/%2/%3",
        name  = "Statically",
    },
    -- GitHub raw → ghproxy
    {
        match = "^https?://raw%.githubusercontent%.com/(.+)$",
        build = "https://ghproxy.com/https://raw.githubusercontent.com/%1",
        name  = "ghproxy",
    },
}

-- ==========================================================
-- 状态
-- ==========================================================
Mirror._success = {}     -- [origUrl] = mirrorUrl
Mirror._fail    = {}     -- [mirrorUrl] = count
Mirror._TIMEOUT = 8      -- 单次请求超时（秒）
Mirror._MAXFAIL = 3      -- 连续失败次数（暂仅记录）

-- ==========================================================
-- 生成镜像列表
-- ==========================================================
function Mirror.generate(url)
    local list = { { url = url, name = "原始" } }

    for _, rule in ipairs(Mirror.RULES) do
        local caps = { url:match(rule.match) }
        if #caps > 0 then
            local built = rule.build
            for i, cap in ipairs(caps) do
                built = built:gsub("%" .. i, cap)
            end
            if built ~= url then
                table.insert(list, { url = built, name = rule.name })
            end
        end
    end

    return list
end

-- ==========================================================
-- 带超时的 HttpGet
-- ==========================================================
local function httpGetWithTimeout(url, timeout)
    local done, result = false, nil
    local start = os.clock()

    task.spawn(function()
        local ok, res = pcall(function()
            return Mirror._HttpGet(url)
        end)
        if ok then result = res end
        done = true
    end)

    while not done do
        if os.clock() - start > timeout then
            return nil, "timeout"
        end
        task.wait(0.05)
    end

    if result == nil or result == "" then
        return nil, "empty"
    end
    return result
end

-- ==========================================================
-- 核心：拉取
-- ==========================================================
function Mirror.fetch(url, opts)
    opts = opts or {}
    local timeout = opts.timeout or Mirror._TIMEOUT
    local silent  = opts.silent

    -- 生成镜像列表
    local mirrors = Mirror.generate(url)

    -- 优先使用上次成功源
    local preferred = Mirror._success[url]
    if preferred then
        for i, m in ipairs(mirrors) do
            if m.url == preferred then
                table.remove(mirrors, i)
                table.insert(mirrors, 1, m)
                break
            end
        end
    end

    -- 依次尝试
    local errors = {}
    for _, m in ipairs(mirrors) do
        local content, err = httpGetWithTimeout(m.url, timeout)
        if content then
            Mirror._success[url] = m.url
            Mirror._fail[m.url] = 0
            if Mirror._Logger then
                Mirror._Logger.info("Mirror", "成功: " .. m.name)
            end
            if not silent and m.name ~= "原始" and Mirror._Notify then
                Mirror._Notify("镜像切换", "使用 " .. m.name, 2)
            end
            return content
        end
        Mirror._fail[m.url] = (Mirror._fail[m.url] or 0) + 1
        table.insert(errors, m.name .. ":" .. (err or "?"))
    end

    if Mirror._Logger then
        Mirror._Logger.error("Mirror", "全失败: " .. url .. " | " .. table.concat(errors, " "))
    end
    if not silent and Mirror._Notify then
        Mirror._Notify("加载失败", "所有镜像均失败", 4, "x")
    end
    return nil, table.concat(errors, " | ")
end

-- ==========================================================
-- 工具
-- ==========================================================
function Mirror.reset()
    Mirror._success = {}
    Mirror._fail    = {}
end

function Mirror.stats()
    local s = { cache = {}, fails = {} }
    for k, v in pairs(Mirror._success) do s.cache[k] = v end
    for k, v in pairs(Mirror._fail) do s.fails[k] = v end
    return s
end

return Mirror--[[
==========================================================
 Core/NotifyHub.lua —— 通知中心
==========================================================
 功能：
   1. 封装 WindUI:Notify
   2. WindUI 不可用时降级到 print
   3. 自动带上 State.NoticeDuration
==========================================================
]]

local NotifyHub = {}

local State = _G.PatriotLoader.req("Core/State")
local Util  = _G.PatriotLoader.req("Core/Util")

NotifyHub.WindUI = nil

-- ==========================================================
-- 设置 WindUI 实例
-- ==========================================================
function NotifyHub.setWindUI(w)
    NotifyHub.WindUI = w
end

-- ==========================================================
-- 发送通知
-- ==========================================================
function NotifyHub.notify(title, content, dur, icon)
    -- 优先走 WindUI
    if NotifyHub.WindUI then
        local ok = Util.try(function()
            NotifyHub.WindUI:Notify({
                Title    = title,
                Content  = content,
                Duration = dur or State.NoticeDuration or 4,
                Icon     = icon,
            })
        end)
        if ok ~= nil then return end
    end

    -- 降级：print 到控制台
    print(string.format("[通知] %s | %s", tostring(title), tostring(content)))
end

-- ==========================================================
-- 快捷方法
-- ==========================================================
function NotifyHub.success(title, content, dur)
    NotifyHub.notify(title, content, dur or 3, "check")
end

function NotifyHub.error(title, content, dur)
    NotifyHub.notify(title, content, dur or 4, "x")
end

function NotifyHub.info(title, content, dur)
    NotifyHub.notify(title, content, dur or 3, "info")
end

function NotifyHub.warn(title, content, dur)
    NotifyHub.notify(title, content, dur or 4, "alert-triangle")
end

return NotifyHub--[[
==========================================================
 Core/ScriptLoader.lua —— 外部脚本加载器
==========================================================
 功能：
   1. 从 URL 拉取脚本
   2. 编译并执行
   3. 支持多段 URL（依次执行）
   4. 记录历史
   5. 依赖注入（notify / say）
==========================================================
]]

local ScriptLoader = {}

-- 依赖注入占位
ScriptLoader.hooks = {
    notify = function() end,
    say    = function() end,
}

local State   = _G.PatriotLoader.req("Core/State")
local Storage = _G.PatriotLoader.req("Core/Storage")

-- ==========================================================
-- 编译源码
-- ==========================================================
function ScriptLoader.compile(source)
    local loaders = {}
    if type(loadstring) == "function" then
        table.insert(loaders, loadstring)
    end
    if type(load) == "function" and load ~= loadstring then
        table.insert(loaders, load)
    end
    if luau and type(luau.load) == "function" then
        table.insert(loaders, luau.load)
    end

    for _, loader in ipairs(loaders) do
        local ok, fn = pcall(loader, source)
        if ok and type(fn) == "function" then
            return fn
        end
    end
    return nil
end

-- ==========================================================
-- 加载脚本
-- ==========================================================
function ScriptLoader.load(name, urls)
    local Notify = ScriptLoader.hooks.notify
    local Say    = ScriptLoader.hooks.say

    -- 检查是否已有加载
    if State.Loading then
        Notify("请稍候", "已有脚本正在加载中", 2)
        return
    end

    -- 检查 URL
    if not urls or (type(urls) == "table" and #urls == 0) then
        Notify("失败", (name or "脚本") .. " 没有可用链接", 3, "x")
        return
    end

    -- 设置状态
    State.Loading = true
    local list = type(urls) == "table" and urls or { urls }
    State.LastScript = { name = name, url = urls }

    -- 记录历史
    Storage.addHistory(name)

    -- 提示
    Say("正在拉取 " .. name .. " …", 2)
    Notify("加载中", name .. "（" .. #list .. " 段）", 2)

    -- 异步加载
    task.spawn(function()
        local okCnt, failCnt, lastErr = 0, 0, ""

        for i, url in ipairs(list) do
            local ok, err = pcall(function()
                local src = game:HttpGet(url)
                if not src or src == "" then
                    error("第 " .. i .. " 段内容为空")
                end
                local fn = ScriptLoader.compile(src)
                if not fn then
                    error("第 " .. i .. " 段编译失败")
                end
                fn()
            end)

            if ok then
                okCnt = okCnt + 1
            else
                failCnt = failCnt + 1
                lastErr = tostring(err)
            end
        end

        if failCnt == 0 then
            Notify("成功", name .. " 已执行", 3, "check")
        elseif okCnt == 0 then
            Notify("失败", name .. " 全部失败: " .. lastErr, 5, "x")
        else
            Notify("部分成功", okCnt .. " 成功 / " .. failCnt .. " 失败", 5)
        end

        State.Loading = false
    end)
end

-- ==========================================================
-- 重新加载上次
-- ==========================================================
function ScriptLoader.reloadLast()
    local Notify = ScriptLoader.hooks.notify

    if not State.LastScript.name or not State.LastScript.url then
        Notify("失败", "没有上次记录", 3, "x")
        return
    end

    Notify("重载中", State.LastScript.name, 2)
    ScriptLoader.load(State.LastScript.name, State.LastScript.url)
end

return ScriptLoader--[[
==========================================================
 UI/Themes.lua —— 主题注册
==========================================================
 功能：
   1. 定义 13 套配色方案
   2. 启动时注册到 WindUI
   3. 提供 names() 供 Dropdown 使用
==========================================================
]]

local Util = _G.PatriotLoader.req("Core/Util")
local Themes = {}

-- ==========================================================
-- 主题表
-- ==========================================================
Themes.map = {
    ["Crimson"]    = {Accent="#7f1d1d",Background="#200c0c",Outline="#f87171",Text="#fef2f2",Placeholder="#fca5a5",Button="#991b1b",Icon="#ef4444"},
    ["Dark"]       = {Accent="#18181b",Background="#101010",Outline="#ffffff",Text="#ffffff",Placeholder="#7a7a7a",Button="#52525b",Icon="#a1a1aa"},
    ["Light"]      = {Accent="#e5e7eb",Background="#ffffff",Outline="#9ca3af",Text="#111827",Placeholder="#6b7280",Button="#f3f4f6",Icon="#374151"},
    ["Midnight"]   = {Accent="#1e3a8a",Background="#0f172a",Outline="#93c5fd",Text="#eff6ff",Placeholder="#94a3b8",Button="#1e40af",Icon="#3b82f6"},
    ["Rose"]       = {Accent="#881337",Background="#230e16",Outline="#fda4af",Text="#fff1f2",Placeholder="#fda4af",Button="#9f1239",Icon="#f43f5e"},
    ["Violet"]     = {Accent="#4c1d95",Background="#17102b",Outline="#a78bfa",Text="#f5f3ff",Placeholder="#c4b5fd",Button="#5b21b6",Icon="#8b5cf6"},
    ["Emerald"]    = {Accent="#047857",Background="#0c1c16",Outline="#6ee7b7",Text="#f0fdfa",Placeholder="#6ee7b7",Button="#065f46",Icon="#10b981"},
    ["Sky"]        = {Accent="#0e7490",Background="#0c1d24",Outline="#5eead4",Text="#ecfeff",Placeholder="#5eead4",Button="#155e75",Icon="#14b8a6"},
    ["Amber"]      = {Accent="#92400e",Background="#1c140f",Outline="#fcd34d",Text="#fffbeb",Placeholder="#a8a29e",Button="#78350f",Icon="#fbbf24"},
    ["Plant"]      = {Accent="#166534",Background="#0f1f17",Outline="#4ade80",Text="#f0fdf4",Placeholder="#86efac",Button="#14532d",Icon="#22c55e"},
    ["Red"]        = {Accent="#b91c1c",Background="#1f0d0d",Outline="#fca5a5",Text="#fef2f2",Placeholder="#fca5a5",Button="#991b1b",Icon="#ef4444"},
    ["Indigo"]     = {Accent="#312e81",Background="#12142d",Outline="#a5b4fc",Text="#eef2ff",Placeholder="#a5b4fc",Button="#3730a3",Icon="#6366f1"},
    ["Snow"]       = {Accent="#f1f5f9",Background="#f8fafc",Outline="#cbd5e1",Text="#0f172a",Placeholder="#64748b",Button="#e2e8f0",Icon="#334155"},
}

-- ==========================================================
-- 注册所有主题
-- ==========================================================
function Themes.register(WindUI)
    for name, p in pairs(Themes.map) do
        Util.try(function()
            WindUI:AddTheme({
                Name        = name,
                Accent      = Color3.fromHex(p.Accent),
                Background  = Color3.fromHex(p.Background),
                Outline     = Color3.fromHex(p.Outline),
                Text        = Color3.fromHex(p.Text),
                Placeholder = Color3.fromHex(p.Placeholder),
                Button      = Color3.fromHex(p.Button),
                Icon        = Color3.fromHex(p.Icon),
            })
        end)
    end
end

-- ==========================================================
-- 主题名列表（Dropdown 用）
-- ==========================================================
function Themes.names()
    local list = {}
    for name in pairs(Themes.map) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

return Themes--[[
==========================================================
 UI/Widget.lua —— WindUI 适配层
==========================================================
 功能：
   1. 封装 WindUI 所有 UI 创建方法
   2. 未来换 UI 库只改这一层
   3. 提供 Dropdown 刷新 / Input 取值的兼容
==========================================================
]]

local Util = _G.PatriotLoader.req("Core/Util")
local Widget = {}

Widget.WindUI = nil

-- ==========================================================
-- 初始化
-- ==========================================================
function Widget.init(WindUI)
    Widget.WindUI = WindUI
end

-- ==========================================================
-- UI 元素创建（全部走 safeUI）
-- ==========================================================
function Widget.Tab(parent, opts)
    return Util.safeUI(parent, "Tab", opts)
end

function Widget.Section(parent, opts)
    return Util.safeUI(parent, "Section", opts)
end

function Widget.Button(parent, opts)
    return Util.safeUI(parent, "Button", opts)
end

function Widget.Toggle(parent, opts)
    return Util.safeUI(parent, "Toggle", opts)
end

function Widget.Input(parent, opts)
    return Util.safeUI(parent, "Input", opts)
end

function Widget.Dropdown(parent, opts)
    return Util.safeUI(parent, "Dropdown", opts)
end

function Widget.Slider(parent, opts)
    return Util.safeUI(parent, "Slider", opts)
end

function Widget.Paragraph(parent, opts)
    return Util.safeUI(parent, "Paragraph", opts)
end

function Widget.Label(parent, opts)
    return Util.safeUI(parent, "Label", opts)
end

function Widget.Space(parent, opts)
    return Util.safeUI(parent, "Space", opts or {})
end

-- ==========================================================
-- Dropdown 刷新兼容
-- ==========================================================
function Widget.dropdownRefresh(dd, values)
    if not dd then return false end
    if Util.tryCall(dd, "Refresh", values) then return true end
    if Util.tryCall(dd, "SetValues", values) then return true end
    return false
end

-- ==========================================================
-- Input 取值兼容
-- ==========================================================
function Widget.inputGet(input)
    if not input then return nil end
    return Util.tryCall(input, "Get")
        or Util.tryCall(input, "GetValue")
        or Util.tryCall(input, "GetText")
end

-- ==========================================================
-- Toggle 取值兼容
-- ==========================================================
function Widget.toggleGet(toggle)
    if not toggle then return nil end
    return Util.tryCall(toggle, "Get")
        or Util.tryCall(toggle, "GetValue")
end

-- ==========================================================
-- 通知（转给 NotifyHub）
-- ==========================================================
function Widget.notify(title, content, dur, icon)
    local NotifyHub = _G.PatriotLoader.req("Core/NotifyHub")
    NotifyHub.notify(title, content, dur, icon)
end

return Widget--[[
==========================================================
 UI/Window.lua —— 主窗口
==========================================================
 功能：
   1. 创建 WindUI 主窗口
   2. 设置标题、作者、Tag
   3. 跑马灯动画（窗口按钮红黑渐变旋转）
==========================================================
]]

local Util   = _G.PatriotLoader.req("Core/Util")
local Widget = _G.PatriotLoader.req("UI/Widget")
local Logger = _G.PatriotLoader.req("Core/Logger")

local Window = {}

-- ==========================================================
-- 构建窗口
-- ==========================================================
function Window.build(WindUI)
    -- 创建窗口
    local win = Util.safeUI(WindUI, "CreateWindow", {
        Folder     = "PatriotHub",
        Title      = "爱国者 Hub",
        Icon       = "rbxassetid://75478609949910",
        Author     = "大肥鱼 | QQ: 3106633104",
        Theme      = "Crimson",
        Size       = UDim2.fromOffset(620, 460),
        HasOutline = true,
    })

    if not win then
        Logger.error("Window", "CreateWindow 返回 nil")
        return nil
    end

    -- 编辑打开按钮
    Util.tryCall(win, "EditOpenButton", {
        Title           = "Patriot",
        CornerRadius    = UDim.new(4, 16),
        StrokeThickness = 0.75,
        Draggable       = true,
    })

    -- 打 Tag
    Util.tryCall(win, "Tag", {
        Title = "1.0",
        Color = Color3.fromHex("#306aff"),
    })

    -- 启动跑马灯
    Window.startMarquee(win)

    Logger.info("Window", "窗口创建成功")
    return win
end

-- ==========================================================
-- 跑马灯（彩虹渐变旋转）
-- ==========================================================
function Window.startMarquee(win)
    -- 停掉旧的
    if _G.__PatriotLoop then
        _G.__PatriotLoop = false
        task.wait(0.2)
    end

    _G.__PatriotLoop = true

    task.spawn(function()
        local colorA = Color3.fromRGB(255, 0, 0)
        local colorB = Color3.fromRGB(0, 0, 0)

        while _G.__PatriotLoop do
            local t = os.clock() * 0.8
            local keypoints = {}

            for i = 0, 10 do
                local x = i / 10
                local w = (math.sin((x - t) * math.pi * 2) + 1) / 2
                table.insert(keypoints, ColorSequenceKeypoint.new(
                    x, colorA:Lerp(colorB, w)
                ))
            end

            Util.tryCall(win, "EditOpenButton", {
                CornerRadius    = UDim.new(4, 16),
                StrokeThickness = 3,
                Color           = ColorSequence.new(keypoints),
            })

            task.wait(1 / 15)
        end
    end)
end

-- ==========================================================
-- 停止跑马灯
-- ==========================================================
function Window.stopMarquee()
    _G.__PatriotLoop = false
end

-- ==========================================================
-- 销毁窗口
-- ==========================================================
function Window.destroy(win)
    Window.stopMarquee()
    Util.tryCall(win, "Destroy")
end

return Window--[[
==========================================================
 UI/Tabs/Notice.lua —— 公告页
==========================================================
 显示：
   - 欢迎信息
   - 作者信息
   - 玩家信息
   - 服务器信息
==========================================================
]]

local L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Widget   = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "公告", Icon = "info" })
    if not Tab then return end

    local plr = Services.plr

    -- 欢迎
    Widget.Paragraph(Tab, {
        Title = "欢迎使用 爱国者 Hub",
        Desc  = "版本 1.0 · 由大肥鱼维护",
    })

    -- 关于
    Widget.Paragraph(Tab, {
        Title = "关于",
        Desc  = "作者：大肥鱼 | QQ: 3106633104\n主题：Crimson\n许可：永久免费",
    })

    -- 玩家信息
    Widget.Paragraph(Tab, {
        Title = "玩家信息",
        Desc  = "用户名: " .. plr.Name ..
                "\n显示名: " .. plr.DisplayName ..
                "\n账号年龄: " .. plr.AccountAge .. " 天" ..
                "\nID: " .. plr.UserId,
    })

    -- 服务器信息
    local jobId = game.JobId
    if jobId == "" then jobId = "未知" end

    Widget.Paragraph(Tab, {
        Title = "当前服务器",
        Desc  = "JobId: " .. jobId ..
                "\nPlaceId: " .. game.PlaceId,
    })

    -- 提示
    Widget.Section(Tab, { Title = "使用提示", TextXAlignment = "Left" })

    Widget.Paragraph(Tab, {
        Title = "📌 说明",
        Desc  = "· 所有脚本均为免费使用\n" ..
                "· 部分自动化脚本有封号风险\n" ..
                "· 使用前请阅读风险提示\n" ..
                "· 有问题联系作者 QQ",
    })
end--[[
==========================================================
 UI/Tabs/About.lua —— 关于页
==========================================================
 显示：
   - 产品定位
   - 为什么选我们
   - 承诺
   - 联系方式
   - 反馈入口
==========================================================
]]

local L = _G.PatriotLoader
local Widget    = L.req("UI/Widget")
local Util      = L.req("Core/Util")
local Logger    = L.req("Core/Logger")
local NotifyHub = L.req("Core/NotifyHub")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "关于", Icon = "info" })
    if not Tab then return end

    -- 头部
    Widget.Paragraph(Tab, {
        Title = "爱国者 Hub",
        Desc  = "版本 1.0 · 由大肥鱼维护 · 永久免费",
    })

    -- 为什么选我们
    Widget.Section(Tab, { Title = "为什么选我们", TextXAlignment = "Left" })
    Widget.Paragraph(Tab, { Title = "✅ 永久免费", Desc = "无内购 · 无广告 · 无隐藏收费" })
    Widget.Paragraph(Tab, { Title = "✅ 稳定更新", Desc = "持续维护，功能不断优化" })
    Widget.Paragraph(Tab, { Title = "✅ 简单易用", Desc = "一行命令即可启动" })
    Widget.Paragraph(Tab, { Title = "✅ 多源镜像", Desc = "网络不佳自动切换源" })

    -- 承诺
    Widget.Section(Tab, { Title = "我们的承诺", TextXAlignment = "Left" })
    Widget.Paragraph(Tab, {
        Title = "闭源声明",
        Desc  = "为保护用户安全，我们选择不开源。\n" ..
                "承诺：无后门 · 无数据收集 · 无追踪。",
    })

    -- 联系方式
    Widget.Section(Tab, { Title = "联系作者", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "复制 QQ 号", Icon = "copy",
        Callback = function()
            Util.try(function() setclipboard("3106633104") end)
            NotifyHub.success("已复制", "QQ: 3106633104")
        end,
    })

    -- 反馈
    Widget.Section(Tab, { Title = "反馈与建议", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "报告 Bug", Icon = "bug",
        Desc  = "复制运行日志，发送给作者",
        Callback = function()
            local log = Logger.export()
            if not log or log == "" then
                NotifyHub.warn("无日志", "日志为空，请先复现问题")
                return
            end
            Util.try(function() setclipboard(log) end)
            NotifyHub.success("日志已复制", "请粘贴给作者")
        end,
    })

    Widget.Button(Tab, {
        Title = "清空日志", Icon = "trash",
        Callback = function()
            Logger.clear()
            NotifyHub.success("已清空", "日志缓存已清空")
        end,
    })

    -- 底部
    Widget.Section(Tab, { Title = " ", TextXAlignment = "Left" })
    Widget.Paragraph(Tab, {
        Title = "",
        Desc  = "Made with ❤️ by 大肥鱼",
    })
end--[[
==========================================================
 UI/Tabs/Main.lua —— 主页
==========================================================
 包含：
   - 挂机防踢
   - 玩家列表 + 传送
   - 帧率控制
   - 防护开关
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")
local AntiAFK   = L.req("Features/AntiAFK")
local AntiKick  = L.req("Features/AntiKick")
local Fps       = L.req("Features/Fps")
local Teleport  = L.req("Features/Teleport")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "主要", Icon = "house" })
    if not Tab then return end

    local P = Services.Players
    local plr = Services.plr

    -- ==========================================================
    -- 实用功能
    -- ==========================================================
    Widget.Section(Tab, { Title = "实用功能", TextXAlignment = "Left" })

    Widget.Toggle(Tab, {
        Title   = "挂机防踢",
        Desc    = "每分钟自动跳跃一次",
        Default = false,
        Callback = AntiAFK.setJump,
    })

    -- 玩家列表
    local function getPlayerNames()
        local list = {}
        for _, p in ipairs(P:GetPlayers()) do
            if p ~= plr then
                table.insert(list, p.Name)
            end
        end
        return list
    end

    local initNames = getPlayerNames()
    local playerDropdown = Widget.Dropdown(Tab, {
        Title = "选择玩家",
        Values = #initNames > 0 and initNames or { "（暂无玩家）" },
        Value  = initNames[1] or "（暂无玩家）",
        Callback = function(v) State.SelectedPlayer = v end,
    })

    Widget.Button(Tab, {
        Title = "刷新玩家列表", Icon = "refresh-cw",
        Callback = function()
            local names = getPlayerNames()
            if #names > 0 then
                Util.tryCall(playerDropdown, "SetValue", names[1])
                Widget.dropdownRefresh(playerDropdown, names)
                State.SelectedPlayer = names[1]
                NotifyHub.success("已刷新", "共 " .. #names .. " 个玩家")
            else
                NotifyHub.warn("无玩家", "服务器里只有你")
            end
        end,
    })

    Widget.Button(Tab, {
        Title = "传送到玩家", Icon = "navigation",
        Callback = function()
            local sp = State.SelectedPlayer
            if not sp or sp == "" or sp == "（暂无玩家）" then
                NotifyHub.error("失败", "请先选择玩家")
                return
            end
            Teleport.toPlayer(sp)
        end,
    })

    -- ==========================================================
    -- 性能设置
    -- ==========================================================
    Widget.Section(Tab, { Title = "性能设置", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "解除帧率限制（不限帧）",
        Desc  = "性能允许时不限帧",
        Icon  = "gauge",
        Callback = function() Fps.set(9999) end,
    })

    Widget.Button(Tab, {
        Title = "设置帧率 120Hz",
        Icon  = "gauge",
        Callback = function() Fps.set(120) end,
    })

    Widget.Button(Tab, {
        Title = "设置帧率 60Hz",
        Icon  = "gauge",
        Callback = function() Fps.set(60) end,
    })

    -- ==========================================================
    -- 工具
    -- ==========================================================
    Widget.Section(Tab, { Title = "工具", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "复制当前服务器 ID", Icon = "copy",
        Callback = function()
            local jobId = game.JobId
            if jobId and jobId ~= "" then
                Util.try(function() setclipboard(jobId) end)
                NotifyHub.success("已复制", "服务器 ID: " .. jobId)
            else
                NotifyHub.error("失败", "无法获取 JobId")
            end
        end,
    })

    -- ==========================================================
    -- 防护
    -- ==========================================================
    Widget.Section(Tab, { Title = "防护", TextXAlignment = "Left" })

    Widget.Toggle(Tab, {
        Title   = "防本地踢",
        Desc    = "拦截客户端 Kick 调用",
        Default = false,
        Callback = AntiKick.set,
    })

    Widget.Toggle(Tab, {
        Title   = "反 AFK 踢",
        Desc    = "每 45 秒模拟一次按键",
        Default = false,
        Callback = AntiAFK.setShift,
    })
end--[[
==========================================================
 UI/Tabs/Scripts.lua —— 脚本列表页
==========================================================
 功能：
   1. 分类排序（官方脚本优先）
   2. 数据驱动渲染（从 ScriptRegistry 读）
   3. 三层风险警告：
      - Desc 标注
      - 点击弹窗确认（记住已确认）
      - 加载后 Notify 提醒
   4. 自定义脚本加载
   5. 重置风险确认记录
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local Storage   = L.req("Core/Storage")
local Logger    = L.req("Core/Logger")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")
local Registry  = L.req("Data/ScriptRegistry")

-- ==========================================================
-- 分类优先级
-- ==========================================================
local CATEGORY_ORDER = {
    ["官方脚本"]   = 1,
    ["主脚本"]     = 2,
    ["服务器专区"] = 3,
    ["功能脚本"]   = 4,
    ["黑洞专区"]   = 5,
    ["小游戏"]     = 6,
    ["画质光影"]   = 7,
    ["动作 / 表情"] = 8,
    ["工具"]       = 9,
    ["服务器脚本"] = 10,
    ["游戏专用"]   = 99,
}

-- ==========================================================
-- 风险确认记忆
-- ==========================================================
local WARN_PATH = "PatriotHub_WarningConfirmed.json"
local WarningConfirmed = Storage.read(WARN_PATH) or {}

local function isConfirmed(name)
    return WarningConfirmed[name] == true
end

local function markConfirmed(name)
    WarningConfirmed[name] = true
    Storage.write(WARN_PATH, WarningConfirmed)
end

local function resetConfirmed()
    for k in pairs(WarningConfirmed) do
        WarningConfirmed[k] = nil
    end
    Storage.write(WARN_PATH, WarningConfirmed)
end

-- ==========================================================
-- 风险弹窗
-- ==========================================================
local function showWarningDialog(script, onResult)
    local parent = Util.getUIParent()
    if not parent then
        onResult(true)
        return
    end

    -- 清旧
    local old = parent:FindFirstChild("PatriotWarningDialog")
    if old then old:Destroy() end

    -- 遮罩
    local overlay = Instance.new("Frame")
    overlay.Name = "PatriotWarningDialog"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.5
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 999999
    overlay.Parent = parent

    -- 对话框
    local dialog = Instance.new("Frame")
    dialog.Size = UDim2.new(0, 0, 0, 0)
    dialog.Position = UDim2.new(0.5, -200, 0.5, -140)
    dialog.BackgroundColor3 = Color3.fromRGB(28, 18, 18)
    dialog.BorderSizePixel = 0
    dialog.ZIndex = 1000000
    dialog.Parent = overlay

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = dialog

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 90, 90)
    stroke.Thickness = 2
    stroke.Transparency = 0.2
    stroke.Parent = dialog

    -- 标题
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 0, 36)
    title.Position = UDim2.new(0, 20, 0, 16)
    title.BackgroundTransparency = 1
    title.Text = "⚠️ 风险提示"
    title.TextColor3 = Color3.fromRGB(255, 150, 150)
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 1000001
    title.Parent = dialog

    -- 内容
    local content = Instance.new("TextLabel")
    content.Size = UDim2.new(1, -40, 0, 140)
    content.Position = UDim2.new(0, 20, 0, 58)
    content.BackgroundTransparency = 1
    content.Text = script.WarningText or "此脚本有风险，确认加载？"
    content.TextColor3 = Color3.fromRGB(235, 235, 245)
    content.TextSize = 14
    content.Font = Enum.Font.GothamMedium
    content.TextWrapped = true
    content.TextXAlignment = Enum.TextXAlignment.Left
    content.TextYAlignment = Enum.TextYAlignment.Top
    content.ZIndex = 1000001
    content.Parent = dialog

    -- 取消按钮
    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Size = UDim2.new(0, 160, 0, 40)
    cancelBtn.Position = UDim2.new(0, 20, 1, -58)
    cancelBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    cancelBtn.BorderSizePixel = 0
    cancelBtn.Text = "取消"
    cancelBtn.TextColor3 = Color3.fromRGB(240, 240, 255)
    cancelBtn.TextSize = 16
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.ZIndex = 1000001
    cancelBtn.Parent = dialog

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 8)
    cancelCorner.Parent = cancelBtn

    -- 确认按钮
    local confirmBtn = Instance.new("TextButton")
    confirmBtn.Size = UDim2.new(0, 180, 0, 40)
    confirmBtn.Position = UDim2.new(1, -200, 1, -58)
    confirmBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    confirmBtn.BorderSizePixel = 0
    confirmBtn.Text = "我已了解，确认加载"
    confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    confirmBtn.TextSize = 14
    confirmBtn.Font = Enum.Font.GothamBold
    confirmBtn.ZIndex = 1000001
    confirmBtn.Parent = dialog

    local confirmCorner = Instance.new("UICorner")
    confirmCorner.CornerRadius = UDim.new(0, 8)
    confirmCorner.Parent = confirmBtn

    -- 事件
    cancelBtn.MouseButton1Click:Connect(function()
        overlay:Destroy()
        Logger.info("Scripts", "取消加载: " .. script.Name)
        onResult(false)
    end)

    confirmBtn.MouseButton1Click:Connect(function()
        overlay:Destroy()
        markConfirmed(script.Name)
        Logger.info("Scripts", "确认加载: " .. script.Name)
        onResult(true)
    end)

    -- 入场动画
    Services.Tween:Create(dialog, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
        Size = UDim2.new(0, 400, 0, 280),
    }):Play()
end

-- ==========================================================
-- 加载脚本（含风险检查）
-- ==========================================================
local function loadScript(script)
    if not State.ScriptLoader then
        NotifyHub.error("错误", "ScriptLoader 未注入")
        return
    end

    -- 首次点击风险脚本
    if script.Warning and not isConfirmed(script.Name) then
        showWarningDialog(script, function(confirmed)
            if confirmed then
                State.ScriptLoader.load(script.Name, script.Url or script.Urls)
                task.wait(1.5)
                NotifyHub.warn("⚠️ 自动化提醒", "此脚本为自动化工具，请注意游戏规则", 6)
            end
        end)
        return
    end

    -- 正常加载
    State.ScriptLoader.load(script.Name, script.Url or script.Urls)

    -- 风险脚本已确认过，二次点击也提醒
    if script.Warning then
        task.wait(1.5)
        NotifyHub.warn("⚠️ 自动化提醒", "此脚本为自动化工具，请注意游戏规则", 6)
    end
end

-- ==========================================================
-- 主渲染
-- ==========================================================
return function(Window)
    local Tab = Widget.Tab(Window, { Title = "脚本列表", Icon = "file-code" })
    if not Tab then return end

    -- 1. 收集分类
    local categories, seen = {}, {}
    for _, s in ipairs(Registry) do
        local c = s.Category or "未分类"
        if not seen[c] then
            seen[c] = true
            table.insert(categories, c)
        end
    end

    -- 2. 排序
    table.sort(categories, function(a, b)
        local oa = CATEGORY_ORDER[a] or 50
        local ob = CATEGORY_ORDER[b] or 50
        if oa == ob then return a < b end
        return oa < ob
    end)

    -- 3. 渲染
    for _, cat in ipairs(categories) do
        Widget.Section(Tab, { Title = cat, TextXAlignment = "Left" })

        if cat == "官方脚本" then
            Widget.Paragraph(Tab, {
                Title = "📌 官方内容",
                Desc  = "以下脚本由大肥鱼维护 · 免费使用",
            })
        end

        if cat == "游戏专用" then
            Widget.Paragraph(Tab, {
                Title = "⚠️ 提示",
                Desc  = "以下脚本为特定游戏设计，使用风险自负",
            })
        end

        for _, s in ipairs(Registry) do
            if (s.Category or "未分类") == cat then
                local descText = s.Desc or ("作者: " .. (s.Author or "未知"))
                Widget.Button(Tab, {
                    Title = s.Name,
                    Desc  = descText,
                    Icon  = s.Icon or "file-code",
                    Callback = function()
                        loadScript(s)
                    end,
                })
            end
        end
    end

    -- ==========================================================
    -- 自定义脚本
    -- ==========================================================
    Widget.Section(Tab, { Title = "自定义脚本", TextXAlignment = "Left" })

    local CustomName, CustomUrl = "", ""
    local nameInput = Widget.Input(Tab, {
        Title = "脚本名称", Icon = "tag",
        Placeholder = "给脚本起个名字",
        Callback = function(v) CustomName = v end,
    })
    local urlInput = Widget.Input(Tab, {
        Title = "脚本链接", Icon = "link",
        Placeholder = "https://...",
        Callback = function(v) CustomUrl = v end,
    })

    Widget.Button(Tab, {
        Title = "加载自定义脚本", Icon = "play",
        Callback = function()
            local url = CustomUrl
            if (not url or url == "") and urlInput then
                url = Util.inputGet(urlInput) or url
            end
            if not url or url == "" then
                NotifyHub.error("失败", "请先填脚本链接")
                return
            end
            local nm = CustomName
            if (not nm or nm == "") and nameInput then
                nm = Util.inputGet(nameInput)
            end
            loadScript({
                Name = (nm and nm ~= "") and nm or "自定义脚本",
                Url = url,
                Warning = false,
            })
        end,
    })

    -- ==========================================================
    -- 重置风险确认
    -- ==========================================================
    Widget.Button(Tab, {
        Title = "重置风险确认记录",
        Desc  = "清除所有脚本的已确认状态",
        Icon  = "rotate-ccw",
        Callback = function()
            resetConfirmed()
            NotifyHub.success("已重置", "下次加载风险脚本会重新提示")
        end,
    })
end--[[
==========================================================
 UI/Tabs/Favorites.lua —— 收藏页
==========================================================
 功能：
   1. 从 Storage.Favorites 读取收藏列表
   2. 从 ScriptRegistry 匹配脚本
   3. 提供一键加载
   4. 支持热刷新（添加收藏后立即显示）
==========================================================
]]

local L = _G.PatriotLoader
local State    = L.req("Core/State")
local Storage  = L.req("Core/Storage")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")
local Registry = L.req("Data/ScriptRegistry")

-- 全局刷新钩子（Settings 里添加/移除收藏后调用）
_G.__RefreshFavorites = nil

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "收藏", Icon = "star" })
    if not Tab then return end

    -- 说明
    Widget.Paragraph(Tab, {
        Title = "⭐ 收藏夹",
        Desc  = "去「设置」页添加/移除收藏",
    })

    Widget.Section(Tab, { Title = "已收藏的脚本", TextXAlignment = "Left" })

    -- 渲染函数
    local function render()
        local count = 0

        for _, s in ipairs(Registry) do
            if Storage.Favorites[s.Name] then
                count = count + 1
                Widget.Button(Tab, {
                    Title = s.Name,
                    Desc  = "作者: " .. (s.Author or "未知"),
                    Icon  = s.Icon or "star",
                    Callback = function()
                        if State.ScriptLoader then
                            State.ScriptLoader.load(s.Name, s.Url or s.Urls)
                        else
                            NotifyHub.error("错误", "ScriptLoader 未注入")
                        end
                    end,
                })
            end
        end

        if count == 0 then
            Widget.Paragraph(Tab, {
                Title = "暂无收藏",
                Desc  = "在「设置」页的「收藏管理」添加脚本名",
            })
        end

        return count
    end

    -- 首次渲染
    render()

    -- 注册刷新钩子
    _G.__RefreshFavorites = function()
        -- WindUI 大多不支持清空 Tab
        -- 简单方案：只提示用户重开窗口
        NotifyHub.info("提示", "收藏已更新，重开窗口可见")
    end
end--[[
==========================================================
 UI/Tabs/Info.lua —— 信息页
==========================================================
 显示：
   - 实时 FPS
   - Ping
   - 内存占用
   - 坐标
   - 服务器运行时间
   - 在线玩家数
   - 服务器信息（PlaceId / JobId）
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "信息", Icon = "activity" })
    if not Tab then return end

    local RS    = Services.RS
    local Stats = Services.Stats
    local P     = Services.Players
    local plr   = Services.plr

    -- ==========================================================
    -- 实时数据
    -- ==========================================================
    Widget.Section(Tab, { Title = "实时数据", TextXAlignment = "Left" })

    local FpsLabel    = Widget.Paragraph(Tab, { Title = "FPS",     Desc = "计算中..." })
    local PingLabel   = Widget.Paragraph(Tab, { Title = "Ping",    Desc = "计算中..." })
    local MemLabel    = Widget.Paragraph(Tab, { Title = "内存",    Desc = "计算中..." })
    local CoordLabel  = Widget.Paragraph(Tab, { Title = "坐标",    Desc = "计算中..." })
    local ServerLabel = Widget.Paragraph(Tab, { Title = "运行时长", Desc = "计算中..." })
    local CountLabel  = Widget.Paragraph(Tab, { Title = "在线玩家", Desc = "计算中..." })

    task.spawn(function()
        local smoothFps = 60

        while true do
            -- FPS
            local dt = Util.try(function() return RS.RenderStepped:Wait() end)
            if dt and dt > 0 then
                smoothFps = smoothFps * 0.9 + (1 / dt) * 0.1
            end
            Util.compatSetDesc(FpsLabel, math.floor(smoothFps + 0.5) .. " FPS")

            task.wait(0.2)

            -- Ping
            local ping = 0
            Util.try(function()
                ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            Util.compatSetDesc(PingLabel, ping .. " ms")

            -- 内存
            local mem = 0
            Util.try(function() mem = math.floor(Stats:GetTotalMemoryUsageMb()) end)
            Util.compatSetDesc(MemLabel, mem .. " MB")

            -- 坐标
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local p = hrp.Position
                Util.compatSetDesc(CoordLabel, string.format(
                    "X: %.1f  Y: %.1f  Z: %.1f", p.X, p.Y, p.Z
                ))
            else
                Util.compatSetDesc(CoordLabel, "角色未加载")
            end

            -- 运行时长
            local uptime = 0
            Util.try(function() uptime = math.floor(workspace.DistributedGameTime) end)
            local h = math.floor(uptime / 3600)
            local m = math.floor((uptime % 3600) / 60)
            Util.compatSetDesc(ServerLabel, h .. " 小时 " .. m .. " 分")

            -- 在线玩家
            Util.compatSetDesc(CountLabel, #P:GetPlayers() .. " 人")

            task.wait(1)
        end
    end)

    -- ==========================================================
    -- 服务器信息
    -- ==========================================================
    Widget.Section(Tab, { Title = "服务器信息", TextXAlignment = "Left" })

    Widget.Paragraph(Tab, { Title = "PlaceId", Desc = tostring(game.PlaceId) })
    Widget.Paragraph(Tab, {
        Title = "JobId",
        Desc  = game.JobId ~= "" and game.JobId or "未知",
    })

    -- 游戏名
    Widget.Paragraph(Tab, {
        Title = "游戏名",
        Desc  = (function()
            local ok, name = pcall(function()
                return Services.MPS:GetProductInfo(game.PlaceId).Name
            end)
            return ok and name or "获取失败"
        end)(),
    })

    -- 复制按钮
    Widget.Button(Tab, {
        Title = "复制服务器信息", Icon = "copy",
        Callback = function()
            local txt = "PlaceId: " .. game.PlaceId ..
                        "\nJobId: " .. game.JobId ..
                        "\n在线: " .. #P:GetPlayers() .. " 人"
            Util.try(function() setclipboard(txt) end)
            NotifyHub.success("已复制", "服务器信息已复制")
        end,
    })

    -- ==========================================================
    -- 玩家列表
    -- ==========================================================
    Widget.Section(Tab, { Title = "玩家列表", TextXAlignment = "Left" })

    local function buildNamesDesc()
        local names = {}
        for _, p in ipairs(P:GetPlayers()) do
            table.insert(names, "· " .. p.Name)
        end
        return table.concat(names, "\n")
    end

    local listLabel = Widget.Paragraph(Tab, {
        Title = "当前服务器玩家",
        Desc  = buildNamesDesc(),
    })

    Widget.Button(Tab, {
        Title = "刷新玩家列表", Icon = "refresh-cw",
        Callback = function()
            Util.compatSetDesc(listLabel, buildNamesDesc())
            NotifyHub.success("已刷新", "玩家列表已更新")
        end,
    })

    Widget.Button(Tab, {
        Title = "复制所有玩家名字", Icon = "copy",
        Callback = function()
            local names = {}
            for _, p in ipairs(P:GetPlayers()) do
                table.insert(names, p.Name)
            end
            Util.try(function() setclipboard(table.concat(names, "\n")) end)
            NotifyHub.success("已复制", #names .. " 个玩家名")
        end,
    })
end--[[
==========================================================
 UI/Tabs/UISettings.lua —— UI 设置页
==========================================================
 包含：
   - UI 缩放
   - 通知时长
   - 通知位置
   - 主题切换
   - 音效开关
==========================================================
]]

local L = _G.PatriotLoader
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")
local Themes    = L.req("UI/Themes")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "UI 设置", Icon = "palette" })
    if not Tab then return end

    -- ==========================================================
    -- 窗口外观
    -- ==========================================================
    Widget.Section(Tab, { Title = "窗口外观", TextXAlignment = "Left" })

    -- 找 WindUI 的 ScreenGui
    local function getWindScreenGui()
        local parent = Util.getUIParent()
        if not parent then return nil end
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("ScreenGui") and
               (obj.Name:find("Wind") or obj.Name:find("爱国者")) then
                return obj
            end
        end
        return nil
    end

    -- UI 缩放
    Widget.Slider(Tab, {
        Title = "UI 缩放",
        Step  = 0.05,
        Value = { Min = 0.5, Max = 1.5, Default = 1 },
        Callback = function(v)
            State.UIScale = v
            Util.try(function()
                local gui = getWindScreenGui()
                if not gui then return end
                local scale = gui:FindFirstChildOfClass("UIScale")
                if not scale then
                    scale = Instance.new("UIScale")
                    scale.Parent = gui
                end
                scale.Scale = v
            end)
        end,
    })

    -- 通知时长
    Widget.Slider(Tab, {
        Title  = "通知时长",
        Step   = 1,
        Value  = { Min = 1, Max = 15, Default = 4 },
        Suffix = " 秒",
        Callback = function(v)
            State.NoticeDuration = v
        end,
    })

    -- 通知位置
    Widget.Dropdown(Tab, {
        Title  = "通知位置",
        Values = { "右上", "左上", "右下", "左下" },
        Value  = "右上",
        Callback = function(v)
            local side = (v == "右上" or v == "右下") and "Right" or "Left"
            Util.tryCall(_G.__PatriotWindUI, "SetNotifySide", side)
            NotifyHub.success("已切换", "通知位置: " .. v, 2)
        end,
    })

    -- ==========================================================
    -- 主题
    -- ==========================================================
    Widget.Section(Tab, { Title = "主题", TextXAlignment = "Left" })

    Widget.Dropdown(Tab, {
        Title  = "切换主题",
        Values = Themes.names(),
        Value  = "Crimson",
        Callback = function(selected)
            Util.tryCall(_G.__PatriotWindUI, "SetTheme", selected)
            Util.tryCall(_G.__PatriotWindUI, "UpdateTheme")
            NotifyHub.success("已切换", "主题: " .. selected, 2)
        end,
    })

    -- ==========================================================
    -- 音效
    -- ==========================================================
    Widget.Section(Tab, { Title = "音效", TextXAlignment = "Left" })

    Widget.Toggle(Tab, {
        Title   = "点击音效",
        Default = true,
        Callback = function(s)
            State.SoundEnabled = s
        end,
    })

    -- ==========================================================
    -- 玩家进出通知
    -- ==========================================================
    Widget.Section(Tab, { Title = "玩家进出通知", TextXAlignment = "Left" })

    Widget.Toggle(Tab, {
        Title   = "启用玩家进出提示",
        Desc    = "右上角玻璃风通知",
        Default = true,
        Callback = function(s)
            State.PlayerNoticeEnabled = s
            local PN = L.req("Features/PlayerNotice")
            if PN and PN.setEnabled then PN.setEnabled(s) end
        end,
    })

    Widget.Slider(Tab, {
        Title  = "提示停留时间",
        Step   = 0.5,
        Value  = { Min = 1, Max = 8, Default = 3 },
        Suffix = " 秒",
        Callback = function(v)
            State.PlayerNoticeDuration = v
        end,
    })

    Widget.Slider(Tab, {
        Title  = "最大同时显示条数",
        Step   = 1,
        Value  = { Min = 1, Max = 10, Default = 5 },
        Callback = function(v)
            State.PlayerNoticeMaxCount = v
        end,
    })

    Widget.Button(Tab, {
        Title = "测试通知", Icon = "play",
        Callback = function()
            local PN = L.req("Features/PlayerNotice")
            if PN and PN.test then PN.test() end
        end,
    })
end--[[
==========================================================
 UI/Tabs/ScriptTool.lua —— 脚本工具页
==========================================================
 包含：
   - 脚本备注（保存/查看）
   - 脚本队列（添加到队列 → 批量执行）
   - 重新加载上次脚本
==========================================================
]]

local L = _G.PatriotLoader
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local Storage   = L.req("Core/Storage")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "脚本工具", Icon = "wrench" })
    if not Tab then return end

    -- ==========================================================
    -- 脚本备注
    -- ==========================================================
    Widget.Section(Tab, { Title = "脚本备注", TextXAlignment = "Left" })

    local noteName, noteText = "", ""

    Widget.Input(Tab, {
        Title = "脚本名称", Icon = "tag",
        Placeholder = "输入脚本名",
        Callback = function(v) noteName = v end,
    })

    Widget.Input(Tab, {
        Title = "备注内容", Icon = "file-text",
        Placeholder = "输入备注",
        Callback = function(v) noteText = v end,
    })

    Widget.Button(Tab, {
        Title = "保存备注", Icon = "save",
        Callback = function()
            if not noteName or noteName == "" then
                NotifyHub.error("失败", "请输入脚本名")
                return
            end
            Storage.setNote(noteName, noteText)
            NotifyHub.success("已保存", noteName .. " 的备注")
        end,
    })

    Widget.Button(Tab, {
        Title = "查看备注", Icon = "eye",
        Callback = function()
            if not noteName or noteName == "" then
                NotifyHub.error("失败", "请输入脚本名")
                return
            end
            local n = Storage.getNote(noteName)
            if n then
                NotifyHub.info("备注", noteName .. "：\n" .. n, 6)
            else
                NotifyHub.warn("无备注", noteName .. " 没有备注")
            end
        end,
    })

    -- ==========================================================
    -- 脚本队列
    -- ==========================================================
    Widget.Section(Tab, { Title = "脚本队列", TextXAlignment = "Left" })

    local Queue = {}
    local QueueRunning = false
    local queueName, queueUrl = "", ""

    Widget.Input(Tab, {
        Title = "队列脚本名", Icon = "tag",
        Placeholder = "可留空",
        Callback = function(v) queueName = v end,
    })

    Widget.Input(Tab, {
        Title = "队列脚本链接", Icon = "link",
        Placeholder = "https://...",
        Callback = function(v) queueUrl = v end,
    })

    Widget.Button(Tab, {
        Title = "添加到队列", Icon = "plus",
        Callback = function()
            if not queueUrl or queueUrl == "" then
                NotifyHub.error("失败", "请填链接")
                return
            end
            table.insert(Queue, {
                name = (queueName ~= "" and queueName) or ("脚本" .. (#Queue + 1)),
                url  = queueUrl,
            })
            NotifyHub.success("已添加", "当前队列 " .. #Queue .. " 个")
        end,
    })

    Widget.Button(Tab, {
        Title = "开始执行队列", Icon = "play",
        Callback = function()
            if QueueRunning then
                NotifyHub.warn("提示", "队列正在执行中")
                return
            end
            if #Queue == 0 then
                NotifyHub.error("失败", "队列为空")
                return
            end

            QueueRunning = true
            task.spawn(function()
                for i, item in ipairs(Queue) do
                    NotifyHub.info("队列执行", i .. "/" .. #Queue .. " " .. item.name, 2)
                    pcall(function()
                        local src = game:HttpGet(item.url)
                        if src and src ~= "" then
                            local fn = loadstring(src)
                            if fn then fn() end
                        end
                    end)
                    task.wait(2)
                end
                Queue = {}
                QueueRunning = false
                NotifyHub.success("队列完成", "全部执行完毕")
            end)
        end,
    })

    Widget.Button(Tab, {
        Title = "清空队列", Icon = "trash",
        Callback = function()
            Queue = {}
            NotifyHub.success("已清空", "队列已清空")
        end,
    })

    -- ==========================================================
    -- 重新加载
    -- ==========================================================
    Widget.Section(Tab, { Title = "重新加载", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "重新加载上次脚本", Icon = "refresh-cw",
        Callback = function()
            if not State.LastScript.name or not State.LastScript.url then
                NotifyHub.error("失败", "没有上次记录")
                return
            end
            if State.ScriptLoader then
                State.ScriptLoader.load(State.LastScript.name, State.LastScript.url)
            end
        end,
    })

    -- ==========================================================
    -- 执行历史
    -- ==========================================================
    Widget.Section(Tab, { Title = "执行历史", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "查看最近执行", Icon = "list",
        Callback = function()
            if #Storage.History == 0 then
                NotifyHub.info("历史", "暂无记录")
                return
            end
            local lines = { "共 " .. #Storage.History .. " 条" }
            local start = math.max(1, #Storage.History - 9)
            for i = start, #Storage.History do
                table.insert(lines, i .. ". " .. Storage.History[i].name)
            end
            NotifyHub.info("执行历史", table.concat(lines, "\n"), 8)
        end,
    })

    Widget.Button(Tab, {
        Title = "清空执行历史", Icon = "trash",
        Callback = function()
            Storage.clearHistory()
            NotifyHub.success("已清空", "历史已清空")
        end,
    })
end--[[
==========================================================
 UI/Tabs/PlayerTool.lua —— 玩家工具页
==========================================================
 包含：
   - 玩家名称输入
   - 复制 UserID / 显示名 / 账号年龄
   - 查看玩家信息
   - 玩家列表 + 复制所有名字
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "玩家工具", Icon = "users" })
    if not Tab then return end

    local P = Services.Players

    -- ==========================================================
    -- 玩家操作
    -- ==========================================================
    Widget.Section(Tab, { Title = "玩家操作", TextXAlignment = "Left" })

    local targetPlayerName = ""

    Widget.Input(Tab, {
        Title = "玩家名称", Icon = "user",
        Placeholder = "输入完整用户名",
        Callback = function(v) targetPlayerName = v end,
    })

    -- 复制 UserID
    Widget.Button(Tab, {
        Title = "复制玩家 UserID", Icon = "copy",
        Callback = function()
            local p = P:FindFirstChild(targetPlayerName)
            if not p then
                NotifyHub.error("失败", "找不到玩家")
                return
            end
            Util.try(function() setclipboard(tostring(p.UserId)) end)
            NotifyHub.success("已复制", p.Name .. " ID: " .. p.UserId)
        end,
    })

    -- 复制显示名
    Widget.Button(Tab, {
        Title = "复制玩家显示名", Icon = "copy",
        Callback = function()
            local p = P:FindFirstChild(targetPlayerName)
            if not p then
                NotifyHub.error("失败", "找不到玩家")
                return
            end
            Util.try(function() setclipboard(p.DisplayName) end)
            NotifyHub.success("已复制", p.DisplayName)
        end,
    })

    -- 复制账号年龄
    Widget.Button(Tab, {
        Title = "复制玩家账号年龄", Icon = "copy",
        Callback = function()
            local p = P:FindFirstChild(targetPlayerName)
            if not p then
                NotifyHub.error("失败", "找不到玩家")
                return
            end
            Util.try(function() setclipboard(tostring(p.AccountAge)) end)
            NotifyHub.success("已复制", p.AccountAge .. " 天")
        end,
    })

    -- 查看玩家信息
    Widget.Button(Tab, {
        Title = "查看玩家信息", Icon = "info",
        Callback = function()
            local p = P:FindFirstChild(targetPlayerName)
            if not p then
                NotifyHub.error("失败", "找不到玩家")
                return
            end
            local info = "用户名: " .. p.Name ..
                         "\n显示名: " .. p.DisplayName ..
                         "\nID: " .. p.UserId ..
                         "\n账号年龄: " .. p.AccountAge .. " 天"
            NotifyHub.info("玩家信息", info, 8)
        end,
    })

    -- ==========================================================
    -- 玩家列表
    -- ==========================================================
    Widget.Section(Tab, { Title = "玩家列表", TextXAlignment = "Left" })

    local function buildNamesDesc()
        local names = {}
        for _, p in ipairs(P:GetPlayers()) do
            table.insert(names, "· " .. p.Name .. "  (ID: " .. p.UserId .. ")")
        end
        return table.concat(names, "\n")
    end

    local listLabel = Widget.Paragraph(Tab, {
        Title = "当前服务器玩家",
        Desc  = buildNamesDesc(),
    })

    Widget.Button(Tab, {
        Title = "刷新玩家列表", Icon = "refresh-cw",
        Callback = function()
            Util.compatSetDesc(listLabel, buildNamesDesc())
            NotifyHub.success("已刷新", "玩家列表已更新")
        end,
    })

    Widget.Button(Tab, {
        Title = "复制所有玩家名字", Icon = "copy",
        Callback = function()
            local names = {}
            for _, p in ipairs(P:GetPlayers()) do
                table.insert(names, p.Name)
            end
            Util.try(function() setclipboard(table.concat(names, "\n")) end)
            NotifyHub.success("已复制", #names .. " 个玩家名")
        end,
    })
end--[[
==========================================================
 UI/Tabs/GameTool.lua —— 游戏工具页
==========================================================
 包含：
   - 天空盒切换
   - 时间调整
   - 阴影开关
   - 雾效开关
   - 玩家名字隐藏/恢复
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "游戏工具", Icon = "gamepad-2" })
    if not Tab then return end

    local Lighting = Services.Lighting
    local P        = Services.Players
    local plr      = Services.plr

    -- ==========================================================
    -- 天空盒
    -- ==========================================================
    Widget.Section(Tab, { Title = "天空盒", TextXAlignment = "Left" })

    local skyPresets = {
        ["默认"]     = nil,
        ["日落"]     = "rbxassetid://4895664308",
        ["星空"]     = "rbxassetid://159454299",
        ["雪山"]     = "rbxassetid://2985358373",
        ["赛博朋克"] = "rbxassetid://6766367600",
        ["深海"]     = "rbxassetid://6036208305",
    }

    local skyNames = {}
    for k in pairs(skyPresets) do
        table.insert(skyNames, k)
    end
    table.sort(skyNames)

    Widget.Dropdown(Tab, {
        Title  = "切换天空盒",
        Values = skyNames,
        Value  = "默认",
        Callback = function(v)
            local id = skyPresets[v]
            Util.try(function()
                local old = Lighting:FindFirstChildOfClass("Sky")
                if old then old:Destroy() end

                if id then
                    local sky = Instance.new("Sky")
                    sky.SkyboxBk = id
                    sky.SkyboxDn = id
                    sky.SkyboxFt = id
                    sky.SkyboxLf = id
                    sky.SkyboxRt = id
                    sky.SkyboxUp = id
                    sky.Parent = Lighting
                end
            end)
            NotifyHub.success("已切换", "天空盒: " .. v)
        end,
    })

    -- ==========================================================
    -- 环境
    -- ==========================================================
    Widget.Section(Tab, { Title = "环境", TextXAlignment = "Left" })

    Widget.Slider(Tab, {
        Title = "时间（小时）",
        Step  = 1,
        Value = { Min = 0, Max = 24, Default = 14 },
        Callback = function(v)
            Util.try(function() Lighting.ClockTime = v end)
        end,
    })

    -- ==========================================================
    -- 视觉设置
    -- ==========================================================
    Widget.Section(Tab, { Title = "视觉设置", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "关闭阴影", Icon = "sun",
        Callback = function()
            Util.try(function() Lighting.GlobalShadows = false end)
            NotifyHub.success("已关闭", "阴影已关闭")
        end,
    })

    Widget.Button(Tab, {
        Title = "开启阴影", Icon = "sun",
        Callback = function()
            Util.try(function() Lighting.GlobalShadows = true end)
            NotifyHub.success("已开启", "阴影已开启")
        end,
    })

    Widget.Button(Tab, {
        Title = "关闭雾效", Icon = "cloud-off",
        Callback = function()
            Util.try(function() Lighting.FogEnd = 100000 end)
            NotifyHub.success("已关闭", "雾效已关闭")
        end,
    })

    -- ==========================================================
    -- 玩家名字
    -- ==========================================================
    Widget.Section(Tab, { Title = "玩家名字", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "隐藏玩家名字",
        Desc  = "本地隐藏其他玩家头顶名字",
        Icon  = "user-x",
        Callback = function()
            local count = 0
            for _, p in ipairs(P:GetPlayers()) do
                if p ~= plr and p.Character then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.NameDisplayDistance = 0
                        hum.HealthDisplayDistance = 0
                        count = count + 1
                    end
                end
            end
            NotifyHub.success("已隐藏", count .. " 个玩家名字")
        end,
    })

    Widget.Button(Tab, {
        Title = "恢复玩家名字", Icon = "user-check",
        Callback = function()
            for _, p in ipairs(P:GetPlayers()) do
                if p ~= plr and p.Character then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.NameDisplayDistance = 100
                        hum.HealthDisplayDistance = 100
                    end
                end
            end
            NotifyHub.success("已恢复", "所有玩家名字已恢复")
        end,
    })

    -- ==========================================================
    -- 光照预设
    -- ==========================================================
    Widget.Section(Tab, { Title = "光照预设", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "白天模式", Icon = "sun",
        Callback = function()
            Util.try(function()
                Lighting.ClockTime = 14
                Lighting.Brightness = 2
                Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                Lighting.GlobalShadows = true
            end)
            NotifyHub.success("已切换", "白天模式")
        end,
    })

    Widget.Button(Tab, {
        Title = "夜晚模式", Icon = "moon",
        Callback = function()
            Util.try(function()
                Lighting.ClockTime = 0
                Lighting.Brightness = 1
                Lighting.OutdoorAmbient = Color3.fromRGB(40, 40, 60)
            end)
            NotifyHub.success("已切换", "夜晚模式")
        end,
    })
end--[[
==========================================================
 UI/Tabs/Settings.lua —— 设置页
==========================================================
 包含：
   - 收藏管理（添加/移除）
   - 配置保存 / 加载
   - 服务器传送（重加 / 跳跃 / 人少）
   - 危险操作（卸载）
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local Storage   = L.req("Core/Storage")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")
local Themes    = L.req("UI/Themes")

return function(Window)
    local Tab = Widget.Tab(Window, { Title = "设置", Icon = "settings" })
    if not Tab then return end

    local HS  = Services.HS
    local TS  = Services.TS
    local plr = Services.plr

    -- ==========================================================
    -- 外观
    -- ==========================================================
    Widget.Section(Tab, { Title = "外观", TextXAlignment = "Left" })

    Widget.Dropdown(Tab, {
        Title  = "切换主题",
        Values = Themes.names(),
        Value  = "Crimson",
        Callback = function(selected)
            Util.tryCall(_G.__PatriotWindUI, "SetTheme", selected)
            Util.tryCall(_G.__PatriotWindUI, "UpdateTheme")
        end,
    })

    -- ==========================================================
    -- 收藏管理
    -- ==========================================================
    Widget.Section(Tab, { Title = "收藏管理", TextXAlignment = "Left" })

    local FavInput = ""
    Widget.Input(Tab, {
        Title = "脚本名称", Icon = "star",
        Placeholder = "输入要收藏的脚本名",
        Callback = function(v) FavInput = v end,
    })

    Widget.Button(Tab, {
        Title = "添加收藏", Icon = "plus",
        Callback = function()
            if not FavInput or FavInput == "" then
                NotifyHub.error("失败", "请输入脚本名称")
                return
            end
            Storage.addFavorite(FavInput)
            NotifyHub.success("已收藏", FavInput)
        end,
    })

    Widget.Button(Tab, {
        Title = "移除收藏", Icon = "minus",
        Callback = function()
            if not FavInput or FavInput == "" then
                NotifyHub.error("失败", "请输入脚本名称")
                return
            end
            Storage.removeFavorite(FavInput)
            NotifyHub.success("已移除", FavInput)
        end,
    })

    -- ==========================================================
    -- 配置保存
    -- ==========================================================
    Widget.Section(Tab, { Title = "配置保存", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "保存当前配置",
        Desc  = "保存所有设置到文件",
        Icon  = "save",
        Callback = function()
            local cfg = {
                BlockKick            = State.BlockKick,
                AntiAFKProtect       = State.AntiAFKProtect,
                AntiAFK              = State.AntiAFK,
                FPS                  = State.FPS,
                NoticeDuration       = State.NoticeDuration,
                SoundEnabled         = State.SoundEnabled,
                UIScale              = State.UIScale,
                PlayerNoticeEnabled  = State.PlayerNoticeEnabled,
                PlayerNoticeDuration = State.PlayerNoticeDuration,
                PlayerNoticeMaxCount = State.PlayerNoticeMaxCount,
            }
            if Storage.write(Storage.ConfigPath, cfg) then
                NotifyHub.success("已保存", "配置已写入文件")
            else
                NotifyHub.error("失败", "执行器不支持 writefile")
            end
        end,
    })

    Widget.Button(Tab, {
        Title = "加载配置",
        Desc  = "从文件恢复设置",
        Icon  = "folder-open",
        Callback = function()
            local cfg = Storage.read(Storage.ConfigPath)
            if not cfg then
                NotifyHub.error("失败", "配置文件不存在")
                return
            end

            local AntiAFK  = L.req("Features/AntiAFK")
            local AntiKick = L.req("Features/AntiKick")
            local Fps      = L.req("Features/Fps")

            if cfg.BlockKick and not State.BlockKick then
                AntiKick.set(true)
            end
            if cfg.AntiAFKProtect and not State.AntiAFKProtect then
                AntiAFK.setShift(true)
            end
            if cfg.AntiAFK and not State.AntiAFK then
                AntiAFK.setJump(true)
            end
            if cfg.FPS and cfg.FPS > 0 then
                Fps.set(cfg.FPS)
            end
            if cfg.NoticeDuration then
                State.NoticeDuration = cfg.NoticeDuration
            end
            if cfg.SoundEnabled ~= nil then
                State.SoundEnabled = cfg.SoundEnabled
            end
            if cfg.UIScale then
                State.UIScale = cfg.UIScale
            end
            if cfg.PlayerNoticeEnabled ~= nil then
                State.PlayerNoticeEnabled = cfg.PlayerNoticeEnabled
            end
            if cfg.PlayerNoticeDuration then
                State.PlayerNoticeDuration = cfg.PlayerNoticeDuration
            end
            if cfg.PlayerNoticeMaxCount then
                State.PlayerNoticeMaxCount = cfg.PlayerNoticeMaxCount
            end

            NotifyHub.success("已加载", "配置已恢复")
        end,
    })

    -- ==========================================================
    -- 服务器传送
    -- ==========================================================
    Widget.Section(Tab, { Title = "服务器传送", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "重新加入当前服务器", Icon = "refresh-cw",
        Callback = function()
            local jobId = game.JobId
            if jobId and jobId ~= "" then
                Util.try(function()
                    TS:TeleportToPlaceInstance(game.PlaceId, jobId, plr)
                end)
            end
        end,
    })

    Widget.Button(Tab, {
        Title = "服务器跳跃", Icon = "globe",
        Callback = function()
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId ..
                        "/servers/Public?sortOrder=Asc&limit=100"
            local ok, res = pcall(function()
                return HS:JSONDecode(game:HttpGet(url))
            end)
            if ok and res and res.data and #res.data > 0 then
                local chosen = res.data[math.random(1, #res.data)]
                Util.try(function()
                    TS:TeleportToPlaceInstance(game.PlaceId, chosen.id, plr)
                end)
            else
                NotifyHub.error("失败", "没有可用服务器")
            end
        end,
    })

    Widget.Button(Tab, {
        Title = "加入人少的服务器", Icon = "users",
        Callback = function()
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId ..
                        "/servers/Public?sortOrder=Asc&limit=100"
            local ok, res = pcall(function()
                return HS:JSONDecode(game:HttpGet(url))
            end)
            if ok and res and res.data and #res.data > 0 then
                table.sort(res.data, function(a, b)
                    return a.playing < b.playing
                end)
                local chosen = res.data[1]
                for _, s in ipairs(res.data) do
                    if s.playing < s.maxPlayers then
                        chosen = s
                        break
                    end
                end
                Util.try(function()
                    TS:TeleportToPlaceInstance(game.PlaceId, chosen.id, plr)
                end)
            else
                NotifyHub.error("失败", "没有可用服务器")
            end
        end,
    })

    -- ==========================================================
    -- 危险操作
    -- ==========================================================
    Widget.Section(Tab, { Title = "危险操作", TextXAlignment = "Left" })

    Widget.Button(Tab, {
        Title = "卸载脚本",
        Desc  = "关闭 UI 并停止所有功能",
        Icon  = "power",
        Callback = function()
            -- 停跑马灯
            if _G.__PatriotLoop then _G.__PatriotLoop = false end

            -- 停状态
            State.AntiAFK        = false
            State.AntiAFKProtect = false

            -- 停线程
            if State.AntiAFKThread then
                Util.try(function() task.cancel(State.AntiAFKThread) end)
            end
            if State.AntiAFKProtThread then
                Util.try(function() task.cancel(State.AntiAFKProtThread) end)
            end
            if State.FpsThread then
                Util.try(function() task.cancel(State.FpsThread) end)
            end

            -- 恢复 Kick
            if State.BlockKick and State.OriginalKick then
                plr.Kick = State.OriginalKick
            end

            -- 停鲸鱼
            if State.Whale then
                State.Whale.Enabled = false
            end

            NotifyHub.info("已卸载", "爱国者 Hub 已关闭", 3)
            task.wait(1)

            Util.tryCall(Window, "Destroy")
        end,
    })
end--[[
==========================================================
 Features/AntiAFK.lua —— 挂机防踢 / 反 AFK
==========================================================
 功能：
   1. 挂机防踢：每分钟自动跳跃
   2. 反 AFK 踢：每 45 秒模拟 LeftShift 按键
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local NotifyHub = L.req("Core/NotifyHub")

local AntiAFK = {}

-- ==========================================================
-- 挂机防踢（定时跳跃）
-- ==========================================================
function AntiAFK.setJump(state)
    State.AntiAFK = state

    -- 停旧线程
    if State.AntiAFKThread then
        Util.try(function() task.cancel(State.AntiAFKThread) end)
        State.AntiAFKThread = nil
    end

    if state then
        State.AntiAFKThread = task.spawn(function()
            while State.AntiAFK do
                task.wait(60)
                Util.try(function()
                    local char = Services.plr.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hum then hum.Jump = true end
                end)
            end
        end)
        NotifyHub.success("已开启", "挂机防踢已启动")
    else
        NotifyHub.info("已关闭", "挂机防踢已停止", 3)
    end
end

-- ==========================================================
-- 反 AFK 踢（定时模拟按键）
-- ==========================================================
function AntiAFK.setShift(state)
    State.AntiAFKProtect = state

    -- 停旧线程
    if State.AntiAFKProtThread then
        Util.try(function() task.cancel(State.AntiAFKProtThread) end)
        State.AntiAFKProtThread = nil
    end

    if state then
        State.AntiAFKProtThread = task.spawn(function()
            while State.AntiAFKProtect do
                task.wait(45)
                Util.try(function()
                    Services.VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                    task.wait(0.05)
                    Services.VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
                end)
            end
        end)
        NotifyHub.success("已开启", "反 AFK 踢已启用")
    else
        NotifyHub.info("已关闭", "反 AFK 踢已停用", 3)
    end
end

-- ==========================================================
-- 状态查询
-- ==========================================================
function AntiAFK.isJumpOn()
    return State.AntiAFK == true
end

function AntiAFK.isShiftOn()
    return State.AntiAFKProtect == true
end

-- ==========================================================
-- 全部停止
-- ==========================================================
function AntiAFK.stopAll()
    AntiAFK.setJump(false)
    AntiAFK.setShift(false)
end

return AntiAFK--[[
==========================================================
 Features/AntiKick.lua —— 防本地踢
==========================================================
 功能：
   1. 替换 plr.Kick 方法
   2. 拦截任何本地 Kick 调用
   3. 关闭时恢复原方法
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local NotifyHub = L.req("Core/NotifyHub")

local AntiKick = {}

-- ==========================================================
-- 开关
-- ==========================================================
function AntiKick.set(state)
    State.BlockKick = state

    if state then
        -- 保存原方法
        if not State.OriginalKick then
            State.OriginalKick = Services.plr.Kick
        end

        -- 替换
        Services.plr.Kick = function()
            print("[防护] 拦截了一次 Kick 调用")
            NotifyHub.notify("已拦截", "有人尝试踢你", 3, "shield")
        end

        NotifyHub.success("已开启", "防本地踢已启用")
    else
        -- 恢复
        if State.OriginalKick then
            Services.plr.Kick = State.OriginalKick
            State.OriginalKick = nil
        end
        NotifyHub.info("已关闭", "防本地踢已停用", 3)
    end
end

-- ==========================================================
-- 状态查询
-- ==========================================================
function AntiKick.isOn()
    return State.BlockKick == true
end

return AntiKick--[[
==========================================================
 Features/Fps.lua —— 帧率控制
==========================================================
 功能：
   1. 调用 setfpscap 设置帧率
   2. 定时重复设置（防止被游戏重置）
   3. 支持不限帧（9999）
   4. 切换时自动停旧线程
==========================================================
]]

local L = _G.PatriotLoader
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local NotifyHub = L.req("Core/NotifyHub")

local Fps = {}

-- ==========================================================
-- 设置帧率
-- ==========================================================
function Fps.set(value)
    State.FPS = value

    -- 停旧线程
    if State.FpsThread then
        Util.try(function() task.cancel(State.FpsThread) end)
        State.FpsThread = nil
    end

    -- 检查执行器支持
    if type(setfpscap) ~= "function" then
        NotifyHub.error("失败", "执行器不支持 setfpscap")
        return
    end

    -- 立即设置一次
    Util.try(function() setfpscap(value) end)

    -- 定时重复设置
    State.FpsThread = task.spawn(function()
        while State.FPS == value do
            task.wait(2)
            Util.try(function() setfpscap(value) end)
        end
    end)

    -- 提示
    local label
    if value >= 9999 then
        label = "不限帧"
    else
        label = value .. " Hz"
    end
    NotifyHub.success("成功", "帧率已设为 " .. label)
end

-- ==========================================================
-- 快捷方法
-- ==========================================================
function Fps.unlimited()
    Fps.set(9999)
end

function Fps.hz60()
    Fps.set(60)
end

function Fps.hz120()
    Fps.set(120)
end

function Fps.hz144()
    Fps.set(144)
end

function Fps.hz240()
    Fps.set(240)
end

-- ==========================================================
-- 停止控制
-- ==========================================================
function Fps.stop()
    if State.FpsThread then
        Util.try(function() task.cancel(State.FpsThread) end)
        State.FpsThread = nil
    end
    State.FPS = 0
    NotifyHub.info("已停止", "帧率控制已关闭", 3)
end

-- ==========================================================
-- 状态查询
-- ==========================================================
function Fps.get()
    return State.FPS
end

return Fps--[[
==========================================================
 Features/Teleport.lua —— 传送
==========================================================
 功能：
   1. 传送到指定玩家（在角色上方 3 格）
   2. 防抖（防止连续传送）
   3. 失败提示
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local Logger    = L.req("Core/Logger")
local NotifyHub = L.req("Core/NotifyHub")

local Teleport = {}

-- 防抖锁
local lock = false

-- ==========================================================
-- 传送到玩家
-- ==========================================================
function Teleport.toPlayer(name)
    if lock then return end

    local P   = Services.Players
    local plr = Services.plr

    -- 找目标
    local target = P:FindFirstChild(name)
    if not target then
        NotifyHub.error("失败", "找不到玩家: " .. tostring(name))
        return
    end

    -- 检查目标角色
    local tc = target.Character
    if not tc then
        NotifyHub.error("失败", "目标角色未加载")
        return
    end

    local tHRP = tc:FindFirstChild("HumanoidRootPart")
    if not tHRP then
        NotifyHub.error("失败", "目标 HumanoidRootPart 未加载")
        return
    end

    -- 检查自己角色
    local mc = plr.Character
    if not mc then
        NotifyHub.error("失败", "你未加载")
        return
    end

    local mHRP = mc:FindFirstChild("HumanoidRootPart")
    if not mHRP then
        NotifyHub.error("失败", "你的 HumanoidRootPart 未加载")
        return
    end

    -- 传送
    lock = true
    mHRP.CFrame = tHRP.CFrame + Vector3.new(0, 3, 0)

    NotifyHub.success("成功", "已传送到 " .. name)
    Logger.info("Teleport", "传送到: " .. name)

    -- 解锁
    task.delay(0.5, function()
        lock = false
    end)
end

-- ==========================================================
-- 传送到指定坐标
-- ==========================================================
function Teleport.toPosition(x, y, z)
    if lock then return end

    local plr = Services.plr
    local mc = plr.Character
    if not mc then
        NotifyHub.error("失败", "你未加载")
        return
    end

    local mHRP = mc:FindFirstChild("HumanoidRootPart")
    if not mHRP then
        NotifyHub.error("失败", "你的 HumanoidRootPart 未加载")
        return
    end

    lock = true
    mHRP.CFrame = CFrame.new(x, y, z)

    NotifyHub.success("成功", "已传送到坐标")
    Logger.info("Teleport", string.format("传送到: %.1f, %.1f, %.1f", x, y, z))

    task.delay(0.5, function()
        lock = false
    end)
end

-- ==========================================================
-- 传送到指定 CFrame
-- ==========================================================
function Teleport.toCFrame(cf)
    if lock then return end

    local plr = Services.plr
    local mc = plr.Character
    if not mc then
        NotifyHub.error("失败", "你未加载")
        return
    end

    local mHRP = mc:FindFirstChild("HumanoidRootPart")
    if not mHRP then
        NotifyHub.error("失败", "你的 HumanoidRootPart 未加载")
        return
    end

    lock = true
    mHRP.CFrame = cf

    NotifyHub.success("成功", "已传送")
    Logger.info("Teleport", "传送到 CFrame")

    task.delay(0.5, function()
        lock = false
    end)
end

-- ==========================================================
-- 状态查询
-- ==========================================================
function Teleport.isLocked()
    return lock
end

return Teleport--[[
==========================================================
 Features/PlayerNotice.lua —— 玩家进出通知
==========================================================
 功能：
   1. 监听 PlayerAdded / PlayerRemoving
   2. 右上角玻璃风通知（半透明 + 圆角 + 描边）
   3. 限制最大同时显示条数
   4. 可开关 / 可调时长
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local Logger    = L.req("Core/Logger")

local PlayerNotice = {}

-- ==========================================================
-- 获取 / 创建通知 GUI
-- ==========================================================
local function getGui()
    local parent = Util.getUIParent()
    if not parent then return nil end

    local gui = parent:FindFirstChild("PatriotPlayerNotice")
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "PatriotPlayerNotice"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 999
        gui.Parent = parent

        local frame = Instance.new("Frame")
        frame.Name = "Container"
        frame.Size = UDim2.new(0, 280, 1, -60)
        frame.Position = UDim2.new(1, -300, 0, 30)
        frame.BackgroundTransparency = 1
        frame.ClipsDescendants = true
        frame.Parent = gui

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 8)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        layout.VerticalAlignment = Enum.VerticalAlignment.Top
        layout.Parent = frame
    end
    return gui
end

-- ==========================================================
-- 显示一条通知
-- ==========================================================
local function showNotice(text, accentColor)
    if not State.PlayerNoticeEnabled then return end

    local gui = getGui()
    if not gui then return end

    local container = gui:FindFirstChild("Container")
    if not container then return end

    -- 限制数量
    local count = 0
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Frame") then count = count + 1 end
    end
    if count >= (State.PlayerNoticeMaxCount or 5) then
        local first
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Frame") then first = child; break end
        end
        if first then first:Destroy() end
    end

    -- 创建通知卡片
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 52)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = accentColor
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(240, 240, 255)
    label.TextSize = 14
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    -- 入场动画
    frame.Position = UDim2.new(1, 20, 0, 0)
    Services.Tween:Create(frame,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.new(0, 0, 0, 0) }):Play()

    -- 定时销毁
    task.delay(State.PlayerNoticeDuration or 3, function()
        if not frame or not frame.Parent then return end
        Services.Tween:Create(frame, TweenInfo.new(0.3), {
            BackgroundTransparency = 1,
        }):Play()
        task.wait(0.4)
        if frame and frame.Parent then frame:Destroy() end
    end)
end

-- ==========================================================
-- 初始化
-- ==========================================================
function PlayerNotice.init()
    local P = Services.Players

    P.PlayerAdded:Connect(function(p)
        task.wait(0.2)
        showNotice("🟢  " .. p.Name .. "  加入了", Color3.fromRGB(80, 220, 120))
        Logger.info("PlayerNotice", p.Name .. " 加入")
    end)

    P.PlayerRemoving:Connect(function(p)
        showNotice("🔴  " .. p.Name .. "  离开了", Color3.fromRGB(240, 100, 100))
        Logger.info("PlayerNotice", p.Name .. " 离开")
    end)

    Logger.info("PlayerNotice", "玩家进出通知已启动")
end

-- ==========================================================
-- API
-- ==========================================================
function PlayerNotice.setEnabled(v)
    State.PlayerNoticeEnabled = v

    -- 同步 UI 显隐
    local parent = Util.getUIParent()
    if parent then
        local gui = parent:FindFirstChild("PatriotPlayerNotice")
        if gui then gui.Enabled = v end
    end
end

function PlayerNotice.setDuration(v)
    State.PlayerNoticeDuration = v
end

function PlayerNotice.setMaxCount(v)
    State.PlayerNoticeMaxCount = v
end

function PlayerNotice.test()
    showNotice("🧪  测试通知", Color3.fromRGB(100, 180, 255))
end

return PlayerNotice--[[
==========================================================
 Features/Summon.lua —— 通用召唤 / 传送
==========================================================
 功能：
   1. 从场景中查找物品对象
   2. 传送到物品
   3. 召唤物品到面前
   4. 自动刷物品（循环传送）
==========================================================
]]

local L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local Logger    = L.req("Core/Logger")
local NotifyHub = L.req("Core/NotifyHub")

local Summon = {}

-- ==========================================================
-- 内部：查找物品
-- ==========================================================
local function findItem(item)
    local ws = workspace

    -- 组装名字表（主名 + 别名）
    local names = { item.name }
    for _, a in ipairs(item.aliases or {}) do
        table.insert(names, a)
    end

    -- 常见容器
    local containers = {
        ws:FindFirstChild("Items"),
        ws:FindFirstChild("ltems"),      -- 有人拼错，兼容
        ws:FindFirstChild("MapItems"),
        ws:FindFirstChild("WorldItems"),
        ws:FindFirstChild("__OBJECTS"),
    }

    for _, c in ipairs(containers) do
        if c then
            for _, n in ipairs(names) do
                local o = c:FindFirstChild(n)
                if o then return o end

                -- 模糊匹配
                for _, child in ipairs(c:GetChildren()) do
                    if child.Name:lower():find(n:lower(), 1, true) then
                        return child
                    end
                end
            end
        end
    end

    return nil
end

-- ==========================================================
-- 内部：获取自己的 HRP
-- ==========================================================
local function getMyHRP()
    local c = Services.plr.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ==========================================================
-- 内部：获取物品的 BasePart
-- ==========================================================
local function getPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart")
end

-- ==========================================================
-- 传送到物品
-- ==========================================================
function Summon.toItem(item)
    local hrp = getMyHRP()
    if not hrp then
        NotifyHub.error("失败", "角色未加载")
        return false
    end

    local obj = findItem(item)
    if not obj then
        NotifyHub.error("未找到", item.name)
        Logger.warn("Summon", "未找到: " .. item.id)
        return false
    end

    local part = getPart(obj)
    if not part then
        NotifyHub.error("失败", item.name .. " 不是部件")
        return false
    end

    hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    NotifyHub.success("已传送", item.name)
    Logger.info("Summon", "传送到: " .. item.id)
    return true
end

-- ==========================================================
-- 召唤物品到面前
-- ==========================================================
function Summon.item(item)
    local hrp = getMyHRP()
    if not hrp then
        NotifyHub.error("失败", "角色未加载")
        return false
    end

    local obj = findItem(item)
    if not obj then
        NotifyHub.error("未找到", item.name)
        return false
    end

    local part = getPart(obj)
    if not part then
        NotifyHub.error("失败", item.name .. " 不是部件")
        return false
    end

    -- 移到玩家前方 5 格
    local pos = hrp.CFrame.Position + hrp.CFrame.LookVector * 5
    part.CFrame = CFrame.new(pos)

    NotifyHub.success("已召唤", item.name)
    Logger.info("Summon", "召唤: " .. item.id)
    return true
end

-- ==========================================================
-- 自动刷物品（循环传送）
-- ==========================================================
Summon._autoThreads = {}

function Summon.startAuto(item, interval)
    if Summon._autoThreads[item.id] then return end
    interval = interval or 2

    Summon._autoThreads[item.id] = true

    task.spawn(function()
        while Summon._autoThreads[item.id] do
            Summon.toItem(item)
            task.wait(interval)
        end
    end)

    NotifyHub.success("已开启", "自动刷 " .. item.name)
end

function Summon.stopAuto(item)
    Summon._autoThreads[item.id] = nil
    NotifyHub.info("已关闭", "自动刷 " .. item.name, 3)
end

function Summon.stopAllAuto()
    Summon._autoThreads = {}
    NotifyHub.info("已关闭", "所有自动刷已停止", 3)
end

-- ==========================================================
-- 批量操作
-- ==========================================================
function Summon.toAllItems(items)
    local count = 0
    for _, item in ipairs(items) do
        if Summon.toItem(item) then
            count = count + 1
            task.wait(0.1)
        end
    end
    NotifyHub.success("完成", "已传送 " .. count .. " 个物品")
end

return Summon--[[
==========================================================
 Data/ScriptRegistry.lua —— 脚本注册表
==========================================================
 字段说明：
   Name        脚本显示名
   Author      作者
   Category    分类（用于分组）
   Icon        图标名（lucide 图标）
   Url         单个脚本链接
   Urls        多个脚本链接（依次执行）
   Desc        描述文字
   Warning     是否风险脚本（弹窗警告）
   WarningText 弹窗警告内容
==========================================================
]]

return {
    -- ========== 官方脚本 ==========
    {
        Name = "菜鸟竞技场",
        Author = "大肥鱼",
        Category = "官方脚本",
        Icon = "swords",
        Url = "https://raw.githubusercontent.com/cheng2026-tech/-Ioo/refs/heads/main/niaoniao.lua",
        Desc = "⚠️ 全自动 PvP 战斗，有封号风险",
        Warning = true,
        WarningText = "此脚本为全自动化 PvP 战斗工具\n" ..
                      "（自动锁头 / 自动追击 / 自动闪避 / 自动反击）。\n\n" ..
                      "可能违反游戏规则，使用可能导致账号被封。\n\n" ..
                      "你已了解风险并自行承担后果？",
    },
    {
        Name = "地狱塔",
        Author = "大肥鱼",
        Category = "官方脚本",
        Icon = "tower",
        Url = "https://raw.githubusercontent.com/cheng2026-tech/fluffy-octo-tribble/refs/heads/main/obfuscated_1791017105761.lua.txt",
        Desc = "跑酷辅助：F 飞行 / T 传最高点 / R 重置位置",
    },

    -- ========== 主脚本 ==========
    -- 加新脚本示例：
    -- {
    --     Name = "脚本名",
    --     Author = "作者",
    --     Category = "主脚本",
    --     Icon = "file-code",
    --     Url = "https://...",
    --     Desc = "简短描述",
    -- },

    -- ========== 服务器专区 ==========

    -- ========== 功能脚本 ==========

    -- ========== 黑洞专区 ==========

    -- ========== 小游戏 ==========

    -- ========== 画质光影 ==========

    -- ========== 动作 / 表情 ==========

    -- ========== 工具 ==========

    -- ========== 服务器脚本 ==========

    -- ========== 游戏专用 ==========
}--[[
==========================================================
 Data/Items.lua —— 物品数据
==========================================================
 字段说明：
   id      唯一 ID
   name    显示名
   aliases 别名（用于模糊匹配）
   kind    类型（可选，默认为物品）
==========================================================
]]

return {
    -- ========== 基础资源 ==========
    { id = "wood",       name = "木头",       aliases = {"log", "wood", "tree"} },
    { id = "carrot",     name = "胡萝卜",     aliases = {"carrot"} },
    { id = "berry",      name = "浆果",       aliases = {"berry"} },
    { id = "bolt",       name = "螺栓",       aliases = {"bolt"} },
    { id = "fan",        name = "风扇",       aliases = {"fan"} },
    { id = "coal",       name = "煤炭",       aliases = {"coal"} },
    { id = "coin",       name = "钱堆",       aliases = {"coin", "money"} },
    { id = "fuel",       name = "燃料罐",     aliases = {"fuel"} },
    { id = "chest",      name = "宝箱",       aliases = {"chest"} },
    { id = "flashlight", name = "手电筒",     aliases = {"flashlight"} },
    { id = "radio",      name = "收音机",     aliases = {"radio"} },

    -- ========== 武器 ==========
    { id = "ammo_rifle",     name = "步枪子弹",   aliases = {"rifleammo"} },
    { id = "ammo_revolver",  name = "左轮子弹",   aliases = {"revolverammo"} },
    { id = "metal",          name = "金属板",     aliases = {"metal", "sheet"} },
    { id = "revolver",       name = "左轮",       aliases = {"revolver"} },
    { id = "rifle",          name = "步枪",       aliases = {"rifle"} },
    { id = "bandage",        name = "绷带",       aliases = {"bandage"} },

    -- ========== 环境 ==========
    { id = "chair",      name = "椅子",       aliases = {"chair"} },
    { id = "tyre",       name = "轮胎",       aliases = {"tyre", "tire"} },

    -- ========== 特殊宝箱 ==========
    { id = "alien_chest", name = "外星宝箱",   aliases = {"alienchest"} },

    -- ========== 生物 ==========
    { id = "bear",        name = "熊",         aliases = {"bear"},        kind = "mob" },
    { id = "wolf",        name = "狼",         aliases = {"wolf"},        kind = "mob" },
    { id = "alpha_wolf",  name = "阿尔法狼",   aliases = {"alphawolf"},   kind = "mob" },
    { id = "enemy",       name = "敌人",       aliases = {"enemy"},       kind = "mob" },

    -- ========== NPC ==========
    { id = "child",      name = "走失的孩子",  aliases = {"lostchild"},   kind = "npc" },
    { id = "child1",     name = "走失的孩子1", aliases = {"lostchild1"},  kind = "npc" },
    { id = "child2",     name = "走失的孩子2", aliases = {"lostchild2"},  kind = "npc" },
    { id = "child3",     name = "走失的孩子3", aliases = {"lostchild3"},  kind = "npc" },
    { id = "dino_kid",   name = "恐龙孩子",    aliases = {"dinokid"},     kind = "npc" },
    { id = "kraken_kid", name = "海怪孩子",    aliases = {"krakenkid"},   kind = "npc" },
    { id = "squid_kid",  name = "鱿鱼孩子",    aliases = {"squidkid"},    kind = "npc" },
    { id = "koala_kid",  name = "考拉孩子",    aliases = {"koalakid"},    kind = "npc" },
    { id = "koala",      name = "考拉",        aliases = {"koala"},       kind = "mob" },
}--[[
==========================================================
 EasterEgg/Whale.lua —— 鲸鱼 LOADI 彩蛋
==========================================================
 功能：
   1. 启动问候
   2. 随机台词（每 3-5 分钟）
   3. 超时休眠提示
   4. 拦截胖 / NSFW 请求
   5. 独立 ScreenGui 气泡
==========================================================
]]

local L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")

local Whale = {
    Name          = "LOADI",
    Enabled       = true,
    TimeoutSignal = "🐋💤",
    LastActive    = os.time(),
    hooks         = { notify = function() end },
}

-- 敏感词
local NSFW_WORDS = { "涩", "色情", "h图", "开车", "18禁", "R18", "涩图" }
local FAT_WORDS  = { "胖", "肥", "重" }

-- ==========================================================
-- 底层：显示气泡
-- ==========================================================
local function rawSay(text, duration)
    duration = duration or 3

    Util.try(function()
        local parent = Util.getUIParent()
        if not parent then return end

        -- 创建/复用 GUI
        local gui = parent:FindFirstChild("WhaleSayGui")
        if not gui then
            gui = Instance.new("ScreenGui")
            gui.Name = "WhaleSayGui"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = parent
        end

        -- 清旧气泡
        local old = gui:FindFirstChild("Bubble")
        if old then old:Destroy() end

        -- 气泡
        local bubble = Instance.new("TextLabel")
        bubble.Name = "Bubble"
        bubble.Size = UDim2.new(0, 320, 0, 60)
        bubble.Position = UDim2.new(1, -340, 1, -40)
        bubble.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
        bubble.BackgroundTransparency = 0.15
        bubble.BorderSizePixel = 0
        bubble.Text = text
        bubble.TextColor3 = Color3.fromRGB(180, 230, 255)
        bubble.TextSize = 15
        bubble.Font = Enum.Font.GothamBold
        bubble.TextWrapped = true
        bubble.TextXAlignment = Enum.TextXAlignment.Left
        bubble.ZIndex = 999
        bubble.Parent = gui

        -- 圆角
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = bubble

        -- 描边
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(100, 180, 255)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.3
        stroke.Parent = bubble

        -- 入场 + 出场动画
        task.spawn(function()
            Services.Tween:Create(bubble, TweenInfo.new(0.3), {
                Position = UDim2.new(1, -340, 1, -80),
                TextTransparency = 0,
            }):Play()

            task.wait(duration)

            Services.Tween:Create(bubble, TweenInfo.new(0.4), {
                Position = UDim2.new(1, -340, 1, -40),
                TextTransparency = 1,
            }):Play()

            task.wait(0.5)
            if bubble and bubble.Parent then
                bubble:Destroy()
            end
        end)
    end)
end

-- ==========================================================
-- 拦截版 say
-- ==========================================================
function Whale.say(text, duration)
    -- 胖/肥拦截
    if type(text) == "string" then
        for _, w in ipairs(FAT_WORDS) do
            if Util.strContains(text, w) then
                rawSay("你说什么？！本鲸才不胖！这是…这是鲸鱼的正常体型！(╯°□°）╯", 3)
                return
            end
        end

        for _, w in ipairs(NSFW_WORDS) do
            if Util.strContains(text, w) then
                rawSay("哼！本鲸才不做那种事！(￣^￣)", 3)
                return
            end
        end
    end

    Whale.LastActive = os.time()
    return rawSay(text, duration)
end

-- ==========================================================
-- 启动循环
-- ==========================================================
function Whale.startLoops()
    -- 启动问候
    task.spawn(function()
        task.wait(1)
        Whale.say("主人回来啦～本鲸是 LOADI，今天也要好好干活哦", 4)
    end)

    -- 随机台词
    task.spawn(function()
        local lines = {
            "主人，要不要试试脚本列表里的东西？哼，不是本鲸夸自己",
            "尾巴甩甩～今天想加载哪个脚本呀？",
            "唔…有点想吃米饭了，主人。才不是撒娇！",
            "主人别一直盯着屏幕啦，眼睛会累。…本鲸只是随口一说",
            "本鲸才没有在等你回来呢…只是刚好路过",
            "懒…不想动…主人自己点吧",
        }

        while Whale.Enabled do
            task.wait(math.random(180, 300))
            Whale.say(lines[math.random(1, #lines)], 3)
        end
    end)

    -- 超时休眠
    task.spawn(function()
        while Whale.Enabled do
            task.wait(60)
            if os.time() - Whale.LastActive >= 600 then
                Whale.say(Whale.TimeoutSignal .. " 本鲸先睡了…有事叫本鲸", 3)
                Whale.LastActive = os.time()
            end
        end
    end)
end

-- ==========================================================
-- 停止
-- ==========================================================
function Whale.stop()
    Whale.Enabled = false

    local parent = Util.getUIParent()
    if parent then
        local gui = parent:FindFirstChild("WhaleSayGui")
        if gui then gui:Destroy() end
    end
end

return Whale