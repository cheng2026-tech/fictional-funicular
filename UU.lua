local Loader = {}
Loader.__cache = {}
Loader.__raw = {}
Loader.__base = nil

function Loader.setBase(url)
    if url:sub(-1) ~= "/" then url = url .. "/" end
    Loader.__base = url
end

function Loader.fetch(relPath)
    if Loader.__raw[relPath] then return Loader.__raw[relPath] end
    if not Loader.__base then error("Loader not initialized") end
    local url = Loader.__base .. relPath
    local src = game:HttpGet(url)
    if not src or src == "" then error("Fetch failed: " .. url) end
    Loader.__raw[relPath] = src
    return src
end

function Loader.req(relPath)
    if Loader.__cache[relPath] then return Loader.__cache[relPath] end
    local src = Loader.fetch(relPath)
    local fn = loadstring(src)
    if not fn then error("Compile failed: " .. relPath) end
    local ok, mod = pcall(fn)
    if not ok then error("Runtime failed: " .. relPath) end
    Loader.__cache[relPath] = mod
    return mod
end

return Loaderlocal BASE = "https://raw.githubusercontent.com/cheng2026-tech/fictional-funicular/main/"

if not _G.wait  then _G.wait  = task.wait  end
if not _G.spawn then _G.spawn = task.spawn end
if not _G.delay then _G.delay = task.delay end

local Loader = loadstring(game:HttpGet(BASE .. "Loader.lua"))()
Loader.setBase(BASE)
_G.PatriotLoader = Loader

local Services     = Loader.req("Core/Services")
local Util         = Loader.req("Core/Util")
local State        = Loader.req("Core/State")
local Storage      = Loader.req("Core/Storage")
local Logger       = Loader.req("Core/Logger")
local Mirror       = Loader.req("Core/Mirror")
local NotifyHub    = Loader.req("Core/NotifyHub")
local ScriptLoader = Loader.req("Core/ScriptLoader")

Mirror.init(game.HttpGet)
State.Logger = Logger
State.Mirror = Mirror
State.ScriptLoader = ScriptLoader

local ok, WindUI = pcall(function()
    return loadstring(game:HttpGet("https://github.com/cheng2026-tech/fictional-funicular/blob/43060d508beb412825f9f523b6fd92a92b23195f/%E5%A4%A7%E8%82%A5%E9%B1%BC%E6%A8%A1%E5%9D%97.lua"))()
end)
if not ok or not WindUI then return end

NotifyHub.setWindUI(WindUI)
_G.__PatriotWindUI = WindUI
ScriptLoader.hooks.notify = NotifyHub.notify

local ok2, Whale = pcall(function() return Loader.req("EasterEgg/Whale") end)
if ok2 and Whale then
    ScriptLoader.hooks.say = Whale.say
    State.Whale = Whale
end

local Themes = Loader.req("UI/Themes")
local Window = Loader.req("UI/Window")
local Widget = Loader.req("UI/Widget")

Themes.register(WindUI)
Widget.init(WindUI)

local MainWindow = Window.build(WindUI)
if not MainWindow then return end
State.Window = MainWindow

local Tabs = {
    "UI/Tabs/Notice", "UI/Tabs/About", "UI/Tabs/Main",
    "UI/Tabs/Scripts", "UI/Tabs/Favorites", "UI/Tabs/Info",
    "UI/Tabs/UISettings", "UI/Tabs/ScriptTool", "UI/Tabs/PlayerTool",
    "UI/Tabs/GameTool", "UI/Tabs/Settings"
}

for _, path in ipairs(Tabs) do
    local ok3, mod = pcall(function() return Loader.req(path) end)
    if ok3 and type(mod) == "function" then pcall(mod, MainWindow) end
end

pcall(function()
    local PN = Loader.req("Features/PlayerNotice")
    if PN and PN.init then PN.init() end
end)

if Whale and Whale.startLoops then Whale.startLoops() end

NotifyHub.notify("爱国者 Hub 已加载", "版本 1.0", 5, "bell-ring")local Services = {}
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
return Serviceslocal Util = {}

function Util.try(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

function Util.tryCall(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then return nil end
    return Util.try(function() return obj[method](obj, ...) end)
end

function Util.safeUI(parent, method, opts)
    if not parent or type(parent[method]) ~= "function" then return nil end
    return Util.try(function() return parent[method](parent, opts) end)
end

function Util.compatSetDesc(obj, text)
    if not obj then return end
    if type(obj.SetDesc) == "function" then
        Util.try(function() obj:SetDesc(text) end)
    elseif type(obj.Set) == "function" then
        Util.try(function() obj:Set({ Desc = text }) end)
    end
end

function Util.getUIParent()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    local ok2, core = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and core then return core end
    return game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
end

function Util.inputGet(input)
    if not input then return nil end
    return Util.tryCall(input, "Get") or Util.tryCall(input, "GetValue")
end

return Utilreturn {
    AntiAFK = false, AntiAFKThread = nil,
    BlockKick = false, OriginalKick = nil,
    AntiAFKProtect = false, AntiAFKProtThread = nil,
    FPS = 0, FpsThread = nil,
    Loading = false, LastScript = { name = nil, url = nil },
    SelectedPlayer = nil, NoticeDuration = 4,
    SoundEnabled = true, CustomTitle = "爱国者 Hub", UIScale = 1,
    PlayerNoticeEnabled = true, PlayerNoticeDuration = 3, PlayerNoticeMaxCount = 5,
    Window = nil, Logger = nil, Mirror = nil, ScriptLoader = nil, Whale = nil,
}local HS = game:GetService("HttpService")
local Storage = {}
Storage.ConfigPath    = "PatriotHub_Config.json"
Storage.FavoritesPath = "PatriotHub_Favorites.json"
Storage.HistoryPath   = "PatriotHub_History.json"
Storage.NotesPath     = "PatriotHub_Notes.json"

function Storage.read(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    if not isfile(path) then return nil end
    local ok, content = pcall(readfile, path)
    if not ok or not content then return nil end
    local ok2, data = pcall(function() return HS:JSONDecode(content) end)
    if ok2 and type(data) == "table" then return data end
    return nil
end

function Storage.write(path, data)
    if type(writefile) ~= "function" then return false end
    return pcall(function() writefile(path, HS:JSONEncode(data)) end)
end

Storage.Favorites = Storage.read(Storage.FavoritesPath) or {}
Storage.History   = Storage.read(Storage.HistoryPath) or {}
Storage.Notes     = Storage.read(Storage.NotesPath) or {}

function Storage.addHistory(name)
    table.insert(Storage.History, { name = name, time = os.time() })
    while #Storage.History > 50 do table.remove(Storage.History, 1) end
    Storage.write(Storage.HistoryPath, Storage.History)
end

function Storage.addFavorite(name)
    Storage.Favorites[name] = true
    Storage.write(Storage.FavoritesPath, Storage.Favorites)
end

function Storage.removeFavorite(name)
    Storage.Favorites[name] = nil
    Storage.write(Storage.FavoritesPath, Storage.Favorites)
end

return Storagelocal Logger = {}
Logger._history = {}

function Logger.log(level, tag, msg)
    table.insert(Logger._history, { time = os.time(), level = level, tag = tag, msg = tostring(msg) })
    if #Logger._history > 200 then table.remove(Logger._history, 1) end
end

function Logger.info(t, m) Logger.log("info", t, m) end
function Logger.warn(t, m) Logger.log("warn", t, m) end
function Logger.error(t, m) Logger.log("error", t, m) end

function Logger.try(tag, fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

function Logger.export()
    local lines = {}
    for _, e in ipairs(Logger._history) do
        table.insert(lines, string.format("[%s][%s] %s", e.level:upper(), e.tag, e.msg))
    end
    return table.concat(lines, "\n")
end

function Logger.clear() Logger._history = {} end
return Loggerlocal Mirror = {}
Mirror._HttpGet = game.HttpGet
Mirror._success = {}

function Mirror.init(httpGet) if httpGet then Mirror._HttpGet = httpGet end end

Mirror.RULES = {
    { match = "^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/(.+)$", build = "https://cdn.jsdelivr.net/gh/%1/%2@%3" },
    { match = "^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/(.+)$", build = "https://cdn.statically.io/gh/%1/%2/%3" },
    { match = "^https?://raw%.githubusercontent%.com/(.+)$", build = "https://ghproxy.com/https://raw.githubusercontent.com/%1" },
}

function Mirror.generate(url)
    local list = { url }
    for _, rule in ipairs(Mirror.RULES) do
        local caps = { url:match(rule.match) }
        if #caps > 0 then
            local built = rule.build
            for i, cap in ipairs(caps) do built = built:gsub("%" .. i, cap) end
            if built ~= url then table.insert(list, built) end
        end
    end
    return list
end

function Mirror.fetch(url)
    local mirrors = Mirror.generate(url)
    local pref = Mirror._success[url]
    if pref then
        for i, m in ipairs(mirrors) do
            if m == pref then table.remove(mirrors, i) table.insert(mirrors, 1, m) break end
        end
    end

    for _, m in ipairs(mirrors) do
        local ok, res = pcall(function() return Mirror._HttpGet(m) end)
        if ok and res and res ~= "" then
            Mirror._success[url] = m
            return res
        end
    end
    return nil
end

return Mirrorlocal NotifyHub = { WindUI = nil }
local State = _G.PatriotLoader.req("Core/State")

function NotifyHub.setWindUI(w) NotifyHub.WindUI = w end

function NotifyHub.notify(title, content, dur, icon)
    if NotifyHub.WindUI then
        pcall(function()
            NotifyHub.WindUI:Notify({ Title = title, Content = content, Duration = dur or State.NoticeDuration or 4, Icon = icon })
        end)
    end
end

return NotifyHublocal ScriptLoader = {}
ScriptLoader.hooks = { notify = function() end, say = function() end }
local State = _G.PatriotLoader.req("Core/State")
local Storage = _G.PatriotLoader.req("Core/Storage")

function ScriptLoader.load(name, urls)
    if State.Loading then return end
    if not urls or (type(urls) == "table" and #urls == 0) then return end

    State.Loading = true
    local list = type(urls) == "table" and urls or { urls }
    State.LastScript = { name = name, url = urls }
    Storage.addHistory(name)

    task.spawn(function()
        for _, url in ipairs(list) do
            pcall(function()
                local src = game:HttpGet(url)
                if src and src ~= "" then
                    local fn = loadstring(src)
                    if fn then fn() end
                end
            end)
        end
        State.Loading = false
    end)
end

return ScriptLoaderlocal Themes = {}
Themes.map = {
    ["Crimson"] = {Accent="#7f1d1d",Background="#200c0c",Outline="#f87171",Text="#fef2f2",Placeholder="#fca5a5",Button="#991b1b",Icon="#ef4444"},
    ["Dark"]    = {Accent="#18181b",Background="#101010",Outline="#ffffff",Text="#ffffff",Placeholder="#7a7a7a",Button="#52525b",Icon="#a1a1aa"},
    ["Snow"]    = {Accent="#f1f5f9",Background="#f8fafc",Outline="#cbd5e1",Text="#0f172a",Placeholder="#64748b",Button="#e2e8f0",Icon="#334155"},
    ["Midnight"] = {Accent="#1e3a8a",Background="#0f172a",Outline="#93c5fd",Text="#eff6ff",Placeholder="#94a3b8",Button="#1e40af",Icon="#3b82f6"},
}

function Themes.register(WindUI)
    for name, p in pairs(Themes.map) do
        pcall(function()
            WindUI:AddTheme({
                Name=name, Accent=Color3.fromHex(p.Accent), Background=Color3.fromHex(p.Background),
                Outline=Color3.fromHex(p.Outline), Text=Color3.fromHex(p.Text),
                Placeholder=Color3.fromHex(p.Placeholder), Button=Color3.fromHex(p.Button), Icon=Color3.fromHex(p.Icon),
            })
        end)
    end
end

function Themes.names()
    local list = {}
    for name in pairs(Themes.map) do table.insert(list, name) end
    table.sort(list)
    return list
end

return Themeslocal Util = _G.PatriotLoader.req("Core/Util")
local Widget = { WindUI = nil }

function Widget.init(w) Widget.WindUI = w end
function Widget.Tab(p, o)       return Util.safeUI(p, "Tab", o) end
function Widget.Section(p, o)   return Util.safeUI(p, "Section", o) end
function Widget.Button(p, o)    return Util.safeUI(p, "Button", o) end
function Widget.Toggle(p, o)    return Util.safeUI(p, "Toggle", o) end
function Widget.Input(p, o)     return Util.safeUI(p, "Input", o) end
function Widget.Dropdown(p, o)  return Util.safeUI(p, "Dropdown", o) end
function Widget.Slider(p, o)    return Util.safeUI(p, "Slider", o) end
function Widget.Paragraph(p, o) return Util.safeUI(p, "Paragraph", o) end

return Widgetlocal Util   = _G.PatriotLoader.req("Core/Util")

local Window = {}

function Window.build(WindUI)
    local win = Util.safeUI(WindUI, "CreateWindow", {
        Folder="爱国者Hub", Title="爱国者 Hub",
        Icon="rbxassetid://75478609949910",
        Author="大肥鱼 | QQ: 3106633104",
        Theme="Crimson", Size=UDim2.fromOffset(620,460),
        HasOutline=true,
    })
    if not win then return nil end

    Util.tryCall(win, "EditOpenButton", {
        Title="Patriot", CornerRadius=UDim.new(4,16),
        StrokeThickness=0.75, Draggable=true,
    })
    Util.tryCall(win, "Tag", { Title="1.0", Color=Color3.fromHex("#306aff") })

    if _G.__PatriotLoop then _G.__PatriotLoop = false; task.wait(0.2) end
    _G.__PatriotLoop = true
    task.spawn(function()
        local a, b = Color3.fromRGB(255,0,0), Color3.fromRGB(0,0,0)
        while _G.__PatriotLoop do
            local t = os.clock() * 0.8
            local kp = {}
            for i = 0, 10 do
                local x = i / 10
                local w = (math.sin((x - t) * math.pi * 2) + 1) / 2
                table.insert(kp, ColorSequenceKeypoint.new(x, a:Lerp(b, w)))
            end
            Util.tryCall(win, "EditOpenButton", {
                CornerRadius=UDim.new(4,16), StrokeThickness=3,
                Color=ColorSequence.new(kp),
            })
            task.wait(1/15)
        end
    end)

    return win
end

return Windowlocal L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Widget   = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="公告", Icon="info" })
    if not Tab then return end
    local plr = Services.plr

    Widget.Paragraph(Tab, { Title="欢迎使用 爱国者 Hub", Desc="版本 1.0" })
    Widget.Paragraph(Tab, { Title="关于", Desc="作者：大肥鱼 | QQ: 3106633104" })
    Widget.Paragraph(Tab, {
        Title="玩家信息",
        Desc="用户名: "..plr.Name.."\n显示名: "..plr.DisplayName..
             "\n账号年龄: "..plr.AccountAge.." 天\nID: "..plr.UserId,
    })
    Widget.Paragraph(Tab, {
        Title="当前服务器",
        Desc="JobId: "..(game.JobId ~= "" and game.JobId or "未知").."\nPlaceId: "..game.PlaceId,
    })
endlocal L = _G.PatriotLoader
local Widget = L.req("UI/Widget")
local Util   = L.req("Core/Util")
local NotifyHub = L.req("Core/NotifyHub")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="关于", Icon="info" })
    if not Tab then return end

    Widget.Paragraph(Tab, { Title="爱国者 Hub", Desc="版本 1.0 · 永久免费" })
    Widget.Section(Tab, { Title="为什么选我们", TextXAlignment="Left" })
    Widget.Paragraph(Tab, { Title="永久免费", Desc="无内购 · 无广告" })
    Widget.Paragraph(Tab, { Title="稳定更新", Desc="持续维护" })

    Widget.Section(Tab, { Title="联系作者", TextXAlignment="Left" })
    Widget.Button(Tab, {
        Title="复制 QQ 号", Icon="copy",
        Callback=function()
            Util.try(function() setclipboard("3106633104") end)
            NotifyHub.notify("已复制", "QQ: 3106633104", 2, "check")
        end,
    })
endlocal L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")
local State    = L.req("Core/State")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")
local AntiAFK  = L.req("Features/AntiAFK")
local AntiKick = L.req("Features/AntiKick")
local Fps      = L.req("Features/Fps")
local Teleport = L.req("Features/Teleport")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="主要", Icon="house" })
    if not Tab then return end
    local P = Services.Players
    local plr = Services.plr

    Widget.Section(Tab, { Title="实用功能", TextXAlignment="Left" })
    Widget.Toggle(Tab, {
        Title="挂机防踢", Desc="每分钟自动跳跃一次",
        Default=false, Callback=AntiAFK.setJump,
    })

    local function getPlayerNames()
        local list = {}
        for _, p in ipairs(P:GetPlayers()) do
            if p ~= plr then table.insert(list, p.Name) end
        end
        return list
    end

    local initNames = getPlayerNames()
    local dd = Widget.Dropdown(Tab, {
        Title="选择玩家",
        Values = #initNames > 0 and initNames or {"（暂无玩家）"},
        Value  = initNames[1] or "（暂无玩家）",
        Callback = function(v) State.SelectedPlayer = v end,
    })

    Widget.Button(Tab, {
        Title="刷新玩家列表", Icon="refresh-cw",
        Callback=function()
            local names = getPlayerNames()
            if #names > 0 then
                Util.tryCall(dd, "SetValue", names[1])
                Util.tryCall(dd, "Refresh", names)
                State.SelectedPlayer = names[1]
                NotifyHub.notify("已刷新", #names.." 个玩家", 2, "check")
            end
        end,
    })
    Widget.Button(Tab, {
        Title="传送到玩家", Icon="navigation",
        Callback=function()
            local sp = State.SelectedPlayer
            if sp and sp ~= "" and sp ~= "（暂无玩家）" then
                Teleport.toPlayer(sp)
            end
        end,
    })

    Widget.Section(Tab, { Title="性能", TextXAlignment="Left" })
    Widget.Button(Tab, { Title="解除帧率限制", Icon="gauge", Callback=function() Fps.set(9999) end })
    Widget.Button(Tab, { Title="设置 120Hz", Icon="gauge", Callback=function() Fps.set(120) end })

    Widget.Section(Tab, { Title="防护", TextXAlignment="Left" })
    Widget.Toggle(Tab, { Title="防本地踢", Default=false, Callback=AntiKick.set })
    Widget.Toggle(Tab, { Title="反 AFK 踢", Default=false, Callback=AntiAFK.setShift })
endlocal L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local Storage   = L.req("Core/Storage")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")
local Registry  = L.req("Data/ScriptRegistry")

local CATEGORY_ORDER = { ["官方脚本"]=1, ["主脚本"]=2, ["服务器专区"]=3, ["功能脚本"]=4, ["游戏专用"]=99 }

local WARN_PATH = "PatriotHub_WarningConfirmed.json"
local WC = Storage.read(WARN_PATH) or {}
local function isConfirmed(n) return WC[n] == true end
local function markConfirmed(n) WC[n] = true; Storage.write(WARN_PATH, WC) end

local function showDialog(script, cb)
    local parent = Util.getUIParent()
    if not parent then cb(true); return end
    local old = parent:FindFirstChild("PatriotWarningDialog")
    if old then old:Destroy() end

    local ov = Instance.new("Frame")
    ov.Name = "PatriotWarningDialog"
    ov.Size = UDim2.new(1,0,1,0)
    ov.BackgroundColor3 = Color3.fromRGB(0,0,0)
    ov.BackgroundTransparency = 0.5
    ov.ZIndex = 999999
    ov.Parent = parent

    local d = Instance.new("Frame")
    d.Size = UDim2.new(0,400,0,280)
    d.Position = UDim2.new(0.5,-200,0.5,-140)
    d.BackgroundColor3 = Color3.fromRGB(28,18,18)
    d.ZIndex = 1000000
    d.Parent = ov
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,14); c.Parent = d
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255,90,90); s.Thickness = 2; s.Parent = d

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1,-40,0,36); t.Position = UDim2.new(0,20,0,16)
    t.BackgroundTransparency = 1; t.Text = "⚠️ 风险提示"
    t.TextColor3 = Color3.fromRGB(255,150,150); t.TextSize = 20
    t.Font = Enum.Font.GothamBold; t.TextXAlignment = Enum.TextXAlignment.Left; t.Parent = d

    local ct = Instance.new("TextLabel")
    ct.Size = UDim2.new(1,-40,0,140); ct.Position = UDim2.new(0,20,0,58)
    ct.BackgroundTransparency = 1; ct.Text = script.WarningText or "确认加载？"
    ct.TextColor3 = Color3.fromRGB(235,235,245); ct.TextSize = 14
    ct.TextWrapped = true; ct.TextXAlignment = Enum.TextXAlignment.Left
    ct.TextYAlignment = Enum.TextYAlignment.Top; ct.Parent = d

    local b1 = Instance.new("TextButton")
    b1.Size = UDim2.new(0,160,0,40); b1.Position = UDim2.new(0,20,1,-58)
    b1.BackgroundColor3 = Color3.fromRGB(60,60,70); b1.Text = "取消"
    b1.TextColor3 = Color3.fromRGB(240,240,255); b1.Font = Enum.Font.GothamBold; b1.Parent = d
    local cc1 = Instance.new("UICorner"); cc1.CornerRadius = UDim.new(0,8); cc1.Parent = b1

    local b2 = Instance.new("TextButton")
    b2.Size = UDim2.new(0,180,0,40); b2.Position = UDim2.new(1,-200,1,-58)
    b2.BackgroundColor3 = Color3.fromRGB(180,40,40); b2.Text = "我已了解，确认加载"
    b2.TextColor3 = Color3.fromRGB(255,255,255); b2.Font = Enum.Font.GothamBold; b2.Parent = d
    local cc2 = Instance.new("UICorner"); cc2.CornerRadius = UDim.new(0,8); cc2.Parent = b2

    b1.MouseButton1Click:Connect(function() ov:Destroy(); cb(false) end)
    b2.MouseButton1Click:Connect(function() ov:Destroy(); markConfirmed(script.Name); cb(true) end)
end

local function loadScript(s)
    if not State.ScriptLoader then return end
    if s.Warning and not isConfirmed(s.Name) then
        showDialog(s, function(ok)
            if ok then State.ScriptLoader.load(s.Name, s.Url or s.Urls) end
        end)
        return
    end
    State.ScriptLoader.load(s.Name, s.Url or s.Urls)
end

return function(Window)
    local Tab = Widget.Tab(Window, { Title="脚本列表", Icon="file-code" })
    if not Tab then return end

    local cats, seen = {}, {}
    for _, s in ipairs(Registry) do
        local c = s.Category or "未分类"
        if not seen[c] then seen[c] = true; table.insert(cats, c) end
    end
    table.sort(cats, function(a,b)
        return (CATEGORY_ORDER[a] or 50) < (CATEGORY_ORDER[b] or 50)
    end)

    for _, cat in ipairs(cats) do
        Widget.Section(Tab, { Title=cat, TextXAlignment="Left" })
        for _, s in ipairs(Registry) do
            if (s.Category or "未分类") == cat then
                Widget.Button(Tab, {
                    Title = s.Name,
                    Desc  = s.Desc or ("作者: "..(s.Author or "未知")),
                    Icon  = s.Icon or "file-code",
                    Callback = function() loadScript(s) end,
                })
            end
        end
    end
endlocal L = _G.PatriotLoader
local State    = L.req("Core/State")
local Storage  = L.req("Core/Storage")
local Widget   = L.req("UI/Widget")
local Registry = L.req("Data/ScriptRegistry")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="收藏", Icon="star" })
    if not Tab then return end
    local count = 0
    for _, s in ipairs(Registry) do
        if Storage.Favorites[s.Name] then
            count = count + 1
            Widget.Button(Tab, {
                Title = s.Name,
                Desc  = "作者: "..(s.Author or "未知"),
                Icon  = s.Icon or "star",
                Callback = function()
                    if State.ScriptLoader then State.ScriptLoader.load(s.Name, s.Url or s.Urls) end
                end,
            })
        end
    end
    if count == 0 then
        Widget.Paragraph(Tab, { Title="暂无收藏", Desc="去「设置」页添加" })
    end
endlocal L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="信息", Icon="activity" })
    if not Tab then return end
    local RS = Services.RS
    local Stats = Services.Stats
    local P = Services.Players
    local plr = Services.plr

    Widget.Section(Tab, { Title="实时数据", TextXAlignment="Left" })
    local FpsL = Widget.Paragraph(Tab, { Title="FPS", Desc="计算中..." })
    local PingL = Widget.Paragraph(Tab, { Title="Ping", Desc="计算中..." })

    task.spawn(function()
        local smooth = 60
        while true do
            local dt = Util.try(function() return RS.RenderStepped:Wait() end)
            if dt and dt > 0 then smooth = smooth * 0.9 + (1/dt) * 0.1 end
            Util.compatSetDesc(FpsL, math.floor(smooth + 0.5).." FPS")
            local ping = 0
            Util.try(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
            Util.compatSetDesc(PingL, ping.." ms")
            Util.compatSetDesc(Widget.Paragraph(Tab, {Title="在线", Desc=""}), #P:GetPlayers().." 人")
            task.wait(1)
        end
    end)
endlocal L = _G.PatriotLoader
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")
local NotifyHub = L.req("Core/NotifyHub")
local Widget    = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="UI 设置", Icon="palette" })
    if not Tab then return end
    Widget.Section(Tab, { Title="通知", TextXAlignment="Left" })
    Widget.Slider(Tab, {
        Title="通知时长", Step=1,
        Value={ Min=1, Max=15, Default=4 }, Suffix=" 秒",
        Callback=function(v) State.NoticeDuration = v end,
    })
endlocal L = _G.PatriotLoader
local State    = L.req("Core/State")
local Storage  = L.req("Core/Storage")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="脚本工具", Icon="wrench" })
    if not Tab then return end
    Widget.Section(Tab, { Title="执行历史", TextXAlignment="Left" })
    Widget.Button(Tab, { Title="查看最近执行", Icon="list",
        Callback=function()
            if #Storage.History == 0 then return end
            local lines = { "共 "..#Storage.History.." 条" }
            for i = math.max(1, #Storage.History - 9), #Storage.History do
                table.insert(lines, i..". "..Storage.History[i].name)
            end
            NotifyHub.notify("执行历史", table.concat(lines, "\n"), 8)
        end })
    Widget.Button(Tab, { Title="清空历史", Icon="trash",
        Callback=function()
            Storage.History = {}
            Storage.write(Storage.HistoryPath, Storage.History)
        end })
    Widget.Button(Tab, { Title="重新加载上次脚本", Icon="refresh-cw",
        Callback=function()
            if State.LastScript.name and State.ScriptLoader then
                State.ScriptLoader.load(State.LastScript.name, State.LastScript.url)
            end
        end })
endlocal L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="玩家工具", Icon="users" })
    if not Tab then return end
    local P = Services.Players
    local targetName = ""

    Widget.Input(Tab, { Title="玩家名称", Icon="user", Callback=function(v) targetName = v end })
    Widget.Button(Tab, { Title="复制 UserID", Icon="copy",
        Callback=function()
            local p = P:FindFirstChild(targetName)
            if p then Util.try(function() setclipboard(tostring(p.UserId)) end) end
        end })
    Widget.Button(Tab, { Title="复制显示名", Icon="copy",
        Callback=function()
            local p = P:FindFirstChild(targetName)
            if p then Util.try(function() setclipboard(p.DisplayName) end) end
        end })
endlocal L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="游戏工具", Icon="gamepad-2" })
    if not Tab then return end
    local Lighting = Services.Lighting
    local P = Services.Players
    local plr = Services.plr

    Widget.Section(Tab, { Title="环境", TextXAlignment="Left" })
    Widget.Button(Tab, { Title="关闭阴影", Icon="sun",
        Callback=function() Util.try(function() Lighting.GlobalShadows = false end) end })
    Widget.Button(Tab, { Title="开启阴影", Icon="sun",
        Callback=function() Util.try(function() Lighting.GlobalShadows = true end) end })
    Widget.Button(Tab, { Title="隐藏玩家名字", Icon="user-x",
        Callback=function()
            for _, p in ipairs(P:GetPlayers()) do
                if p ~= plr and p.Character then
                    local h = p.Character:FindFirstChildOfClass("Humanoid")
                    if h then h.NameDisplayDistance = 0 end
                end
            end
        end })
    Widget.Button(Tab, { Title="恢复玩家名字", Icon="user-check",
        Callback=function()
            for _, p in ipairs(P:GetPlayers()) do
                if p ~= plr and p.Character then
                    local h = p.Character:FindFirstChildOfClass("Humanoid")
                    if h then h.NameDisplayDistance = 100 end
                end
            end
        end })
endlocal L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")
local State    = L.req("Core/State")
local Storage  = L.req("Core/Storage")
local NotifyHub= L.req("Core/NotifyHub")
local Widget   = L.req("UI/Widget")
local Themes   = L.req("UI/Themes")

return function(Window)
    local Tab = Widget.Tab(Window, { Title="设置", Icon="settings" })
    if not Tab then return end
    local TS = Services.TS
    local plr = Services.plr

    Widget.Section(Tab, { Title="外观", TextXAlignment="Left" })
    Widget.Dropdown(Tab, {
        Title="切换主题",
        Values=Themes.names(), Value="Crimson",
        Callback=function(sel)
            Util.tryCall(_G.__PatriotWindUI, "SetTheme", sel)
            Util.tryCall(_G.__PatriotWindUI, "UpdateTheme")
        end,
    })

    Widget.Section(Tab, { Title="服务器传送", TextXAlignment="Left" })
    Widget.Button(Tab, { Title="重新加入当前服务器", Icon="refresh-cw",
        Callback=function()
            if game.JobId and game.JobId ~= "" then
                Util.try(function() TS:TeleportToPlaceInstance(game.PlaceId, game.JobId, plr) end)
            end
        end })

    Widget.Section(Tab, { Title="危险操作", TextXAlignment="Left" })
    Widget.Button(Tab, { Title="卸载脚本", Icon="power",
        Callback=function()
            if _G.__PatriotLoop then _G.__PatriotLoop = false end
            State.AntiAFK = false
            State.AntiAFKProtect = false
            if State.AntiAFKThread then Util.try(function() task.cancel(State.AntiAFKThread) end) end
            if State.AntiAFKProtThread then Util.try(function() task.cancel(State.AntiAFKProtThread) end) end
            if State.FpsThread then Util.try(function() task.cancel(State.FpsThread) end) end
            if State.BlockKick and State.OriginalKick then plr.Kick = State.OriginalKick end
            if State.Whale then State.Whale.Enabled = false end
            task.wait(1)
            Util.tryCall(Window, "Destroy")
        end })
endlocal L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")

local AntiAFK = {}

function AntiAFK.setJump(state)
    State.AntiAFK = state
    if State.AntiAFKThread then
        Util.try(function() task.cancel(State.AntiAFKThread) end)
        State.AntiAFKThread = nil
    end
    if state then
        State.AntiAFKThread = task.spawn(function()
            while State.AntiAFK do
                task.wait(60)
                Util.try(function()
                    local h = Services.plr.Character and Services.plr.Character:FindFirstChildOfClass("Humanoid")
                    if h then h.Jump = true end
                end)
            end
        end)
    end
end

function AntiAFK.setShift(state)
    State.AntiAFKProtect = state
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
    end
end

return AntiAFKlocal L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local State     = L.req("Core/State")

local AntiKick = {}

function AntiKick.set(state)
    State.BlockKick = state
    if state then
        if not State.OriginalKick then State.OriginalKick = Services.plr.Kick end
        Services.plr.Kick = function() end
    else
        if State.OriginalKick then
            Services.plr.Kick = State.OriginalKick
            State.OriginalKick = nil
        end
    end
end

return AntiKicklocal L = _G.PatriotLoader
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")

local Fps = {}

function Fps.set(value)
    State.FPS = value
    if State.FpsThread then
        Util.try(function() task.cancel(State.FpsThread) end)
        State.FpsThread = nil
    end
    if type(setfpscap) ~= "function" then return end
    Util.try(function() setfpscap(value) end)
    State.FpsThread = task.spawn(function()
        while State.FPS == value do
            task.wait(2)
            Util.try(function() setfpscap(value) end)
        end
    end)
end

return Fpslocal L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local NotifyHub = L.req("Core/NotifyHub")

local Teleport = {}
local lock = false

function Teleport.toPlayer(name)
    if lock then return end
    local P = Services.Players
    local plr = Services.plr
    local t = P:FindFirstChild(name)
    if not t then return end
    local tc, mc = t.Character, plr.Character
    if not tc or not tc:FindFirstChild("HumanoidRootPart") then return end
    if not mc or not mc:FindFirstChild("HumanoidRootPart") then return end
    lock = true
    mc.HumanoidRootPart.CFrame = tc.HumanoidRootPart.CFrame + Vector3.new(0,3,0)
    task.delay(0.5, function() lock = false end)
end

return Teleportlocal L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local Util      = L.req("Core/Util")
local State     = L.req("Core/State")

local PlayerNotice = {}

local function getGui()
    local parent = Util.getUIParent()
    if not parent then return nil end
    local gui = parent:FindFirstChild("PatriotPlayerNotice")
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "PatriotPlayerNotice"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Parent = parent
        local frame = Instance.new("Frame")
        frame.Name = "Container"
        frame.Size = UDim2.new(0, 280, 1, -60)
        frame.Position = UDim2.new(1, -300, 0, 30)
        frame.BackgroundTransparency = 1
        frame.Parent = gui
        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 8)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        layout.Parent = frame
    end
    return gui
end

local function show(text, color)
    if not State.PlayerNoticeEnabled then return end
    local gui = getGui()
    if not gui then return end
    local container = gui:FindFirstChild("Container")
    if not container then return end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 52)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    frame.BackgroundTransparency = 0.15
    frame.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 1.5
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

    task.delay(State.PlayerNoticeDuration or 3, function()
        if frame and frame.Parent then frame:Destroy() end
    end)
end

function PlayerNotice.init()
    local P = Services.Players
    P.PlayerAdded:Connect(function(p) show("🟢  " .. p.Name .. "  加入了", Color3.fromRGB(80, 220, 120)) end)
    P.PlayerRemoving:Connect(function(p) show("🔴  " .. p.Name .. "  离开了", Color3.fromRGB(240, 100, 100)) end)
end

return PlayerNoticelocal L = _G.PatriotLoader
local Services  = L.req("Core/Services")
local NotifyHub = L.req("Core/NotifyHub")

local Summon = {}

local function findItem(item)
    local ws = workspace
    local names = { item.name }
    for _, a in ipairs(item.aliases or {}) do table.insert(names, a) end
    local containers = {
        ws:FindFirstChild("Items"), ws:FindFirstChild("ltems"),
        ws:FindFirstChild("MapItems"), ws:FindFirstChild("WorldItems"),
    }
    for _, c in ipairs(containers) do
        if c then
            for _, n in ipairs(names) do
                local o = c:FindFirstChild(n)
                if o then return o end
            end
        end
    end
    return nil
end

function Summon.toItem(item)
    local hrp = Services.plr.Character and Services.plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local o = findItem(item)
    if not o then return end
    local t = o:IsA("BasePart") and o or o:FindFirstChildWhichIsA("BasePart")
    if t then hrp.CFrame = t.CFrame + Vector3.new(0, 3, 0) end
end

return Summonreturn {
    {
        Name = "菜鸟竞技场",
        Author = "大肥鱼",
        Category = "官方脚本",
        Icon = "swords",
        Url = "https://raw.githubusercontent.com/cheng2026-tech/-Ioo/refs/heads/main/niaoniao.lua",
        Desc = "⚠️ 全自动 PvP 战斗，有封号风险",
        Warning = true,
        WarningText = "此脚本为全自动化 PvP 战斗工具\n\n可能违反游戏规则，使用可能导致账号被封。\n\n你已了解风险并自行承担后果？",
    },
    {
        Name = "地狱塔",
        Author = "大肥鱼",
        Category = "官方脚本",
        Icon = "tower",
        Url = "https://raw.githubusercontent.com/cheng2026-tech/fluffy-octo-tribble/refs/heads/main/obfuscated_1791017105761.lua.txt",
        Desc = "跑酷辅助：F 飞行 / T 传最高点 / R 重置位置",
    },
}return {
    { id = "wood",   name = "木头",   aliases = {"log", "wood"} },
    { id = "carrot", name = "胡萝卜", aliases = {"carrot"} },
    { id = "berry",  name = "浆果",   aliases = {"berry"} },
    { id = "chest",  name = "宝箱",   aliases = {"chest"} },
    { id = "bear",   name = "熊",     aliases = {"bear"}, kind = "mob" },
    { id = "wolf",   name = "狼",     aliases = {"wolf"}, kind = "mob" },
}local L = _G.PatriotLoader
local Services = L.req("Core/Services")
local Util     = L.req("Core/Util")

local Whale = {
    Enabled = true,
    LastActive = os.time(),
}

local function rawSay(text, dur)
    dur = dur or 3
    Util.try(function()
        local parent = Util.getUIParent()
        if not parent then return end
        local gui = parent:FindFirstChild("WhaleSayGui")
        if not gui then
            gui = Instance.new("ScreenGui")
            gui.Name = "WhaleSayGui"
            gui.ResetOnSpawn = false
            gui.Parent = parent
        end
        local old = gui:FindFirstChild("Bubble")
        if old then old:Destroy() end
        local b = Instance.new("TextLabel")
        b.Size = UDim2.new(0, 320, 0, 60)
        b.Position = UDim2.new(1, -340, 1, -80)
        b.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
        b.BackgroundTransparency = 0.15
        b.Text = text
        b.TextColor3 = Color3.fromRGB(180, 230, 255)
        b.TextSize = 15
        b.Font = Enum.Font.GothamBold
        b.TextWrapped = true
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Parent = gui
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 10)
        c.Parent = b
        task.spawn(function()
            task.wait(dur)
            if b and b.Parent then b:Destroy() end
        end)
    end)
end

function Whale.say(text, dur)
    Whale.LastActive = os.time()
    rawSay(text, dur)
end

function Whale.startLoops()
    task.spawn(function()
        task.wait(1)
        Whale.say("主人回来啦～本鲸是 LOADI", 4)
    end)
    task.spawn(function()
        local lines = { "尾巴甩甩～今天想加载哪个脚本呀？", "懒…不想动…主人自己点吧" }
        while Whale.Enabled do
            task.wait(math.random(180, 300))
            Whale.say(lines[math.random(1, #lines)], 3)
        end
    end)
end

return Whale
