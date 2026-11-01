--!nonstrict
local Model = require("./lib/inline_model.luau")
local UI = require("./lib/inline_ui.luau")
local Interaction = require("./lib/interaction.luau")
local latest = noctalia.state.get("lattice.state")
local hovered, hoverKey, targets, pages = nil, nil, {}, {}
local dirty, stopped, busy = true, false, false
local icons, usedIcons = {}, {}
local stableOrders = {}
local function settings()
    return Model.settings({capsule_padding=noctalia.getConfig("capsule_padding"),
        workspace_spacing=noctalia.getConfig("workspace_spacing"),icon_size=noctalia.getConfig("icon_size"),
        max_icons=noctalia.getConfig("max_icons"),group_icons=noctalia.getConfig("group_icons"),density=noctalia.getConfig("density")})
end
local function iconPath(appId,size)
    if appId=="" then return nil end
    local key=tostring(size)..":"..appId
    usedIcons[key]=true
    local revision=type(latest)=="table" and latest.revision or 0
    local item=icons[key]
    if item and item.path and noctalia.fileExists(item.path) then return item.path end
    if item and item.revision==revision then return nil end
    local ok,path=pcall(noctalia.appIconPath,appId,size)
    if not ok or type(path)~="string" or path=="" or not noctalia.fileExists(path) then path=nil end
    icons[key]={path=path,revision=revision}
    return path
end
local function click(reference,windowId)
    return function()
        if stopped or busy or reference.output~=barWidget.outputName() then return end
        busy=true
        if not Interaction.send(latest,reference,windowId,noctalia,function()busy=false end) then busy=false end
    end
end
local function render()
    local model=Model.forOutput(latest,barWidget.outputName(),hovered,settings(),barWidget.isVertical(),pages,stableOrders)
    hovered=model.hover
    usedIcons={}
    local tree
    tree,targets=UI.render(model,{ui=ui,tr=noctalia.tr,iconPath=iconPath,hoverKey=hoverKey,
        workspaceClick=function(ref)return click(ref,nil)end,
        windowClick=function(ref,id)return click(ref,id)end,
        pageClick=function(ref,page,count)return function()
            if stopped or ref.output~=barWidget.outputName() or not Interaction.workspace(latest,ref) then return end
            pages[ref.id]=(page+1)%count
            dirty=true
        end end})
    local retained={}
    for _,ws in ipairs(model.workspaces) do retained[ws.id]=ws.page end
    pages=retained
    for key in pairs(icons) do if not usedIcons[key] then icons[key]=nil end end
    barWidget.render(tree)
    dirty=false
end
function onInlineHover(entered,key)
    if stopped then return end
    if entered==true or entered=="true" then
        local ref=Model.validHover(latest,barWidget.outputName(),targets[key])
        if ref then hovered,hoverKey,dirty=ref,key,true end
    elseif hoverKey==key then
        -- Native leave/enter callbacks for parent -> child arrive as one input
        -- transition. Settle them on the existing host update, never collapse
        -- the parent synchronously while its child is being entered.
        hoverKey=nil
        dirty=true
    end
end
function update()
    if stopped then return end
    if not hoverKey and hovered then hovered=nil;dirty=true end
    if dirty then render() end
end
function onConfigChanged() icons={};pages={};dirty=true end
function onClick()return false end
function onRightClick()return false end
function onMiddleClick()return false end
function onScroll(_axis,_steps,_startsGesture)return false end
function onExit(_signal,_reason)stopped=true;hovered=nil;hoverKey=nil;targets={};icons={};pages={};stableOrders={} end
noctalia.state.watch("lattice.state",function(value)
    if stopped then return end
    if type(value)~="table" or type(latest)~="table" or value.generation~=latest.generation then pages={};stableOrders={} end
    latest=value
    dirty=true
end)
noctalia.setUpdateInterval(100)
