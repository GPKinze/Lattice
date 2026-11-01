local root=arg[1] or "."
local S=dofile(root.."/lib/state.luau")
local F=dofile(root.."/tests/fixtures/synthetic.luau")
local P=dofile(root.."/lib/presentation.luau")
local B=assert(loadfile(root.."/lib/bar_model.luau","t",setmetatable({require=function()return P end},{__index=_G})))()
local M=assert(loadfile(root.."/lib/inline_model.luau","t",setmetatable({require=function()return B end},{__index=_G})))()
local U=dofile(root.."/lib/inline_ui.luau")
local I=dofile(root.."/lib/interaction.luau")
local total=0
local function test(name,fn)local ok,e=pcall(fn);assert(ok,name..": "..tostring(e));total=total+1;print("ok "..total.." - "..name)end
local function ready(n)
 local s=S.new();S.transport(s,"connected",1);local a,b=F.workspace("a",1,"一"),F.workspace("b",2,"二")
 a.occupied=true;a.window_count=n or 2;a.focused_window="w1";b.occupied=true;b.window_count=1
 local windows={};for k=1,n or 2 do windows[k]=F.window("w"..k,"a");windows[k].title="Synthetic "..k end
 windows[1].active=true;windows[#windows+1]=F.window("other","b")
 for _,e in ipairs({{event="workspaces",data={a,b}},{event="windows",data=windows},{event="outputs",data={F.output("OUT-A","a",true)}}})do assert(S.apply(s,e,1))end
 return S.view(s)
end

local function multiOutput()
    local s = S.new()
    S.transport(s, "connected", 1)

    local a = F.workspace("a", 1, "一", "OUT-A")
    local b = F.workspace("b", 1, "一", "OUT-B")
    a.occupied = true
    a.window_count = 9
    b.occupied = true
    b.window_count = 9

    local windows = {}
    for i = 1, 9 do
        local wa = F.window("a" .. i, "a", "OUT-A")
        wa.app_id = "app-a-" .. i
        wa.title = "Output A " .. i
        windows[#windows + 1] = wa

        local wb = F.window("b" .. i, "b", "OUT-B")
        wb.app_id = "app-b-" .. i
        wb.title = "Output B " .. i
        windows[#windows + 1] = wb
    end

    windows[1].active = true

    local events = {
        { event = "workspaces", data = { a, b } },
        { event = "windows", data = windows },
        { event = "outputs", data = {
            F.output("OUT-A", "a", true),
            F.output("OUT-B", "b", false)
        }}
    }

    for _, event in ipairs(events) do
        assert(S.apply(s, event, 1))
    end

    return S.view(s)
end

local ref={id="a",output="OUT-A",generation=1}
local function model(v,hover,settings,pages,vertical,output)return M.forOutput(v or ready(),output or "OUT-A",hover,settings,vertical,pages)end
local ui={};for _,kind in ipairs({"row","column","label","image","glyph"})do ui[kind]=function(p,c)return{type=kind,props=p or {},children=c or {}}end end
local function find(t,p)if p(t)then return t end;for _,c in ipairs(t.children)do local n=find(c,p);if n then return n end end end
local function all(t,p,result)result=result or {};if p(t)then result[#result+1]=t end;for _,c in ipairs(t.children)do all(c,p,result)end;return result end
local function host(v,output)
 local h={view=v or ready(),output=output or "OUT-A",config={},renders=0,requests={},watch=nil,lookups=0}
 local env=setmetatable({ui=ui},{__index=_G})
 env.require=function(p)if p=="./lib/inline_model.luau"then return M elseif p=="./lib/inline_ui.luau"then return U else assert(p=="./lib/interaction.luau");return I end end
 local function forbidden()error("inline bar must not open a panel, publish shared UI state or start a stream")end
 env.noctalia={state={get=function(k)assert(k=="lattice.state");return h.view end,watch=function(k,f)assert(k=="lattice.state");h.watch=f end,set=forbidden},
 togglePanel=forbidden,runStream=forbidden,pluginDir=function()return "/synthetic"end,
 tr=function(k)return k end,getConfig=function(k)assert(not h.inWatch);return h.config[k]end,
 setUpdateInterval=function(ms)assert(ms==100);h.interval=ms end,
 appIconPath=function(id,size)h.lookups=h.lookups+1;return "/icon/"..id..size end,fileExists=function()return true end,
 json={encode=function(token)h.token=token;return "synthetic"end},
 runAsync=function(argv,cb,timeout)assert(timeout==4000);assert(argv[3]=="/synthetic/action_request.py");h.requests[#h.requests+1]=h.token;h.callback=cb;return true end}
 env.barWidget={outputName=function()assert(not h.inWatch);return h.output end,isVertical=function()return h.vertical==true end,render=function(t)assert(not h.inWatch);h.tree=t;h.renders=h.renders+1 end}
 assert(loadfile(root.."/bar.luau","t",env))();h.env=env
 function h.tick()env.update()end
 function h.send(value)h.view=value;h.inWatch=true;h.watch(value);h.inWatch=false;h.tick()end
 function h.enter(node)env.onInlineHover("true",node.props.key);h.tick()end
 function h.leave(node)env.onInlineHover("false",node.props.key);h.tick()end
 h.tick();return h
end
local function icon(h,id)return find(h.tree,function(n)return n.props.key and n.props.key:find(":window:"..id,1,true)end)end
local function label(h,id)return find(h.tree,function(n)return n.props.key=="workspace:"..tostring(h.view.generation)..":"..id..":label"end)end

local function assertOrder(h, workspaceId, expected)
    local marker = "workspace:" .. tostring(h.view.generation) .. ":" .. workspaceId .. ":window:"
    local actual = {}

    for _, node in ipairs(all(h.tree, function(n)
        return type(n.props.key) == "string"
            and n.props.key:find(marker, 1, true) ~= nil
    end)) do
        local id = node.props.key:match(":window:(.+)$")
        assert(id, "window icon key has no ID")
        table.insert(actual, id)
    end

    assert(#actual == #expected,
        "unexpected icon count in workspace " .. workspaceId)

    for i, id in ipairs(expected) do
        assert(actual[i] == id,
            "icon order mismatch at " .. i
            .. ": expected " .. id
            .. ", got " .. tostring(actual[i]))
    end
end

test("two inline bar instances isolate output workspaces and pagination", function()
    local v = multiOutput()
    local a = host(v, "OUT-A")
    local b = host(v, "OUT-B")

    assert(label(a, "a") and not label(a, "b"))
    assert(label(b, "b") and not label(b, "a"))
    assertOrder(a, "a", {"a1", "a2", "a3", "a4"})
    assertOrder(b, "b", {"b1", "b2", "b3", "b4"})

    local more = find(a.tree, function(n)
        return n.props.key == "workspace:1:a:more"
    end)
    assert(more, "OUT-A is missing its pagination control")
    more.props.onClick()
    a.tick()

    assertOrder(a, "a", {"a5", "a6", "a7", "a8"})
    assertOrder(b, "b", {"b1", "b2", "b3", "b4"})

    v.workspaces.a.windowIds = {
        "a9", "a8", "a7", "a6", "a5", "a4", "a3", "a2", "a1"
    }
    v.workspaces.b.windowIds = {
        "b9", "b8", "b7", "b6", "b5", "b4", "b3", "b2", "b1"
    }

    a.send(v)
    b.send(v)

    assertOrder(a, "a", {"a5", "a6", "a7", "a8"})
    assertOrder(b, "b", {"b1", "b2", "b3", "b4"})
end)

test("old output click callbacks are rejected after widget retarget", function()
    local v = multiOutput()
    local h = host(v, "OUT-A")
    local oldClick = icon(h, "a1").props.onClick

    h.output = "OUT-B"
    h.send(v)

    assert(label(h, "b") and not label(h, "a"))
    oldClick()

    assert(#h.requests == 0, "old OUT-A click dispatched after retargeting")
end)

test("old output pagination callbacks cannot change the previous page", function()
    local v = multiOutput()
    local h = host(v, "OUT-A")
    local oldMore = find(h.tree, function(n)
        return n.props.key == "workspace:1:a:more"
    end)
    assert(oldMore, "OUT-A is missing its pagination control")

    h.output = "OUT-B"
    h.send(v)
    oldMore.props.onClick()

    h.output = "OUT-A"
    h.send(v)

    assertOrder(h, "a", {"a1", "a2", "a3", "a4"})
end)

test("same-app windows remain individually identifiable",function()local m=model(ready());local w=m.workspaces[1].windowIcons;assert(#w==2 and w[1].id=="w1" and w[2].id=="w2")end)

test("focus changes preserve icon order and move active highlight",function()
    local v = ready(3)

    v.windows.w1.app_id = "kitty"
    v.windows.w2.app_id = "chatgpt"
    v.windows.w3.app_id = "zen-browser"

    local h = host(v)
    local expected = {"w1", "w2", "w3"}

    assertOrder(h, "a", expected)

    local cases = {
        {focus="w2", ids={"w2","w1","w3"}},
        {focus="w3", ids={"w3","w2","w1"}},
        {focus="w1", ids={"w1","w3","w2"}},
    }

    for _, case in ipairs(cases) do
        v.workspaces.a.windowIds = case.ids

        for id, w in pairs(v.windows) do
            w.active = id == case.focus
        end

        v.focus.activeWindowId = case.focus
        h.send(v)

        assertOrder(h, "a", expected)
        assert(icon(h, case.focus).props.border == "primary")
    end
end)

test("same-app member order remains stable across focus changes",function()
    local v = ready(3)

    v.windows.w1.app_id = "A"
    v.windows.w2.app_id = "A"
    v.windows.w3.app_id = "B"

    local h = host(v)

    assertOrder(h, "a", {"w1","w2","w3"})

    v.workspaces.a.windowIds = {"w2","w1","w3"}
    v.windows.w1.active = false
    v.windows.w2.active = true
    v.focus.activeWindowId = "w2"

    h.send(v)

    assertOrder(h, "a", {"w1","w2","w3"})
    assert(icon(h, "w2").props.border == "primary")
end)

test("new windows append and closed windows are pruned",function()
    local v = ready(3)

    v.windows.w1.app_id = "kitty"
    v.windows.w2.app_id = "chatgpt"
    v.windows.w3.app_id = "zen-browser"

    local h = host(v)

    local w4 = F.window("w4", "a")
    w4.output = v.workspaces.a.output
    w4.app_id = "new-app"
    w4.title = "Synthetic 4"

    v.windows.w4 = w4
    v.workspaces.a.windowIds = {"w4","w2","w3","w1"}

    h.send(v)

    assertOrder(h, "a", {"w1","w2","w3","w4"})

    v.windows.w2 = nil
    v.workspaces.a.windowIds = {"w4","w3","w1"}

    h.send(v)

    assertOrder(h, "a", {"w1","w3","w4"})
end)

test("moved windows leave source and append at destination",function()
    local v = ready(3)

    v.windows.w1.app_id = "kitty"
    v.windows.w2.app_id = "chatgpt"
    v.windows.w3.app_id = "zen-browser"

    local h = host(v)

    v.windows.w3.workspace = "b"
    v.windows.w3.output = v.workspaces.b.output

    v.workspaces.a.windowIds = {"w1","w2"}
    v.workspaces.b.windowIds = {"w3","other"}

    h.send(v)

    assertOrder(h, "a", {"w1","w2"})

    h.enter(label(h, "b"))

    assertOrder(h, "b", {"other","w3"})
end)

test("new generation seeds a fresh window order",function()
    local v = ready(3)

    v.windows.w1.app_id = "kitty"
    v.windows.w2.app_id = "chatgpt"
    v.windows.w3.app_id = "zen-browser"

    local h = host(v)

    local nextView = ready(3)
    nextView.generation = v.generation + 1

    nextView.windows.w1.app_id = "kitty"
    nextView.windows.w2.app_id = "chatgpt"
    nextView.windows.w3.app_id = "zen-browser"

    nextView.workspaces.a.windowIds = {"w3","w2","w1"}

    h.send(nextView)

    assertOrder(h, "a", {"w3","w2","w1"})
end)
test("inactive windows expand only on hover",function()local h=host();assert(not icon(h,"other"));h.enter(label(h,"b"));assert(icon(h,"other") and icon(h,"w1"));h.leave(label(h,"b"));assert(not icon(h,"other"))end)
test("exact labels stay unchanged",function()local v=ready();v.workspaces.a.name=" 2 一 長い ";v.workspaces.a.named=true;local h=host(v);assert(label(h,"a").children[1].props.text==v.workspaces.a.name)end)
test("label click requests a workspace and never a window",function()local h=host();label(h,"b").props.onClick();assert(#h.requests==1 and h.requests[1].kind=="workspace" and h.requests[1].window==nil)end)
test("icon click immediately requests its exact window without hover",function()local h=host();icon(h,"w2").props.onClick();assert(#h.requests==1 and h.requests[1].window=="w2")end)
test("same-app icon callbacks select different stable IDs",function()local h=host();icon(h,"w1").props.onClick();h.callback({exitCode=0});icon(h,"w2").props.onClick();assert(h.requests[1].window~=h.requests[2].window)end)
test("inactive workspace icon focuses without a separate switch request",function()local h=host();h.enter(label(h,"b"));icon(h,"other").props.onClick();assert(#h.requests==1 and h.requests[1].window=="other" and h.requests[1].id=="b")end)
test("nested parent leave and child enter do not collapse",function()local h=host();h.enter(label(h,"b"));local node=icon(h,"other");h.env.onInlineHover("false",label(h,"b").props.key);h.env.onInlineHover("true",node.props.key);h.tick();assert(icon(h,"other"));h.leave(icon(h,"other"));assert(not icon(h,"other"))end)
test("late parent leave does not cancel child hover",function()local h=host();h.enter(label(h,"b"));h.env.onInlineHover("true",icon(h,"other").props.key);h.env.onInlineHover("false",label(h,"b").props.key);h.tick();assert(icon(h,"other"))end)
test("rapid capsule and child transitions converge",function()local h=host();for _=1,50 do h.enter(label(h,"b"));local n=icon(h,"other");h.enter(n);h.env.onInlineHover("false",n.props.key);h.env.onInlineHover("true",label(h,"a").props.key);h.tick()end;assert(icon(h,"w1") and not icon(h,"other"))end)
test("icons carry native app and title tooltips",function()local h=host();assert(icon(h,"w2").props.tooltip=="org.example.Editor\nSynthetic 2")end)
test("image children do not introduce additional hover targets",function()local h=host();for _,c in ipairs(icon(h,"w1").children)do assert(not c.props.onHover and not c.props.onClick)end end)
test("hover never starts navigation or a panel",function()local h=host();h.enter(label(h,"b"));h.enter(icon(h,"other"));assert(#h.requests==0)end)
test("capsule padding has no implicit window click",function()local h=host();assert(h.tree.children[1].props.onClick==nil and h.env.onClick()==false)end)
test("removed windows reject old click closures",function()local h=host();local click=icon(h,"w2").props.onClick;local v=ready();v.windows.w2=nil;v.workspaces.a.windowIds={"w1"};h.send(v);click();assert(#h.requests==0)end)
test("moved windows reject old workspace ownership",function()local h=host();local click=icon(h,"w2").props.onClick;local v=ready();v.windows.w2.workspace="b";h.send(v);click();assert(#h.requests==0)end)
test("disconnect disables stale icon actions",function()local h=host();local click=icon(h,"w1").props.onClick;local v=ready();v.ready=false;h.send(v);click();assert(#h.requests==0 and h.tree.props.key=="status")end)
test("reconnect rejects the old generation",function()local h=host();local click=icon(h,"w1").props.onClick;local v=ready();v.generation=2;h.send(v);click();assert(#h.requests==0)end)
test("overflow limits individual windows and pages through all of them",function()local h=host(ready(11));local seen={};for _=1,3 do for _,n in ipairs(all(h.tree,function(n)return n.props.key and n.props.key:find(":window:",1,true)end))do seen[n.props.key]=true end;local more=find(h.tree,function(n)return n.props.key=="workspace:1:a:more"end);assert(more);h.enter(more);more.props.onClick();h.tick()end;local count=0;for _ in pairs(seen)do count=count+1 end;assert(count==11 and #h.requests==0)end)
test("overflow paging does not change capsule height",function()local h=host(ready(10));local before=h.tree.children[1].props.height;local more=find(h.tree,function(n)return n.props.key=="workspace:1:a:more"end);more.props.onClick();h.tick();assert(h.tree.children[1].props.height==before)end)
test("stale paging targets are rejected",function()local h=host(ready(9));local more=find(h.tree,function(n)return n.props.key=="workspace:1:a:more"end);local v=ready(9);v.ready=false;h.send(v);more.props.onClick();h.tick();assert(h.tree.props.key=="status")end)
test("grouping preserves adjacent same-app windows",function()local v=ready(4);v.windows.w1.app_id="A";v.windows.w2.app_id="B";v.windows.w3.app_id="A";v.windows.w4.app_id="B";local w=model(v).workspaces[1].windowIcons;assert(w[1].id=="w1" and w[2].id=="w3" and w[3].id=="w2")end)
test("ungrouped mode preserves reported window order",function()local v=ready(4);v.windows.w1.app_id="A";v.windows.w2.app_id="B";v.windows.w3.app_id="A";local w=model(v,nil,{group_icons=false}).workspaces[1].windowIcons;assert(w[1].id=="w1" and w[2].id=="w2" and w[3].id=="w3")end)
test("empty and pinned occupancy comes from Umbriel",function()local v=ready();v.workspaces.a.occupied=false;v.windows.w1.pinned=true;local m=model(v,ref);assert(#m.workspaces[1].windowIcons==0)end)
test("per-output duplicate names remain separate",function()local v=ready();v.outputs['OUT-B']=F.output('OUT-B');v.byOutput['OUT-B']={workspaceIds={'b'},windowIds={'other'}};v.byOutput['OUT-A'].workspaceIds={'a'};v.workspaces.b.output='OUT-B';v.workspaces.b.name='一';v.windows.other.output='OUT-B';local m=model(v,nil,nil,nil,false,'OUT-B');assert(#m.workspaces==1 and m.workspaces[1].id=='b')end)
test("vertical fallback stays label-only",function()local h=host();h.vertical=true;h.env.onConfigChanged();h.tick();assert(not icon(h,"w1") and label(h,"a"))end)
test("minimized icons remain individually dimmed",function()local v=ready();v.windows.w2.minimized=true;local h=host(v);assert(icon(h,"w2").props.opacity==0.6)end)
test("global and remembered focus use distinct outlines",function()local h=host();assert(icon(h,"w1").props.border=="primary");local v=ready();v.windows.w1.active=false;v.focus.activeWindowId=nil;h.send(v);assert(icon(h,"w1").props.border=="secondary")end)
test("scoped ticks coalesce state bursts without polling IPC",function()local h=host();local before=h.renders;h.inWatch=true;for _=1,50 do h.watch(ready())end;h.inWatch=false;assert(h.renders==before);h.tick();assert(h.renders==before+1 and h.interval==100)end)
test("idle ticks do not redraw",function()local h=host();local before=h.renders;for _=1,100 do h.tick()end;assert(h.renders==before)end)
test("appearance settings change icon size without changing names",function()local h=host();h.config.icon_size=24;h.config.density='roomy';h.env.onConfigChanged();h.tick();assert(icon(h,"w1").children[1].props.width==24 and label(h,"a").children[1].props.text=='一')end)
test("teardown blocks queued hover and click actions",function()local h=host();local node=icon(h,"w1");local before=h.renders;h.env.onExit(15,'disable');h.enter(node);node.props.onClick();assert(h.renders==before and #h.requests==0)end)
test("short last page reserves stable inline slots",function()
 local h=host(ready(9));local before=#h.tree.children[1].children
 for _=1,2 do local more=find(h.tree,function(n)return n.props.key=="workspace:1:a:more"end);more.props.onClick();h.tick()end
 assert(#h.tree.children[1].children==before)
 local slots=all(h.tree,function(n)return n.props.key and n.props.key:find(":slot:",1,true)end)
 assert(#slots==3)
 for _,slot in ipairs(slots)do assert(slot.props.width==18 and slot.props.onClick==nil)end
end)
test("capsule hover outline is distinct with active and urgency priority and stable geometry",function()
 local h=host();local idle=h.tree.children[2].props;assert(idle.border=="on_surface_variant/0.18")
 h.enter(label(h,"b"));local hover=h.tree.children[2].props;assert(hover.border=="on_surface_variant/0.32" and hover.fill=="on_surface/0.08")
 for _,key in ipairs({"height","gap","paddingH","paddingV","align","radius","borderWidth"})do assert(hover[key]==idle[key])end
 assert(h.tree.children[1].props.border=="primary")
 h.enter(label(h,"a"));assert(h.tree.children[1].props.border=="primary" and h.tree.children[1].props.fill=="primary/0.16")
 h.enter(label(h,"b"));local v=ready();v.workspaces.b.urgent=true;h.send(v);assert(h.tree.children[2].props.border=="error")
 h.send(ready());h.leave(label(h,"b"));assert(h.tree.children[2].props.border==idle.border and #h.requests==0)
end)

test("pagination preserves remembered order across focus changes", function()
    local v = ready(11)

    for i = 1, 11 do
        v.windows["w" .. i].app_id = "app-" .. i
    end

    local h = host(v)

    local function nextPage()
        local more = find(h.tree, function(n)
            return n.props.key == "workspace:1:a:more"
        end)
        assert(more, "missing next-page control")
        more.props.onClick()
        h.tick()
    end

    nextPage()
    assertOrder(h, "a", {"w5", "w6", "w7", "w8"})

    v.workspaces.a.windowIds = {
        "w11", "w3", "w8", "w1", "w10", "w2",
        "w7", "w4", "w9", "w5", "w6"
    }

    for id, w in pairs(v.windows) do
        w.active = id == "w7"
    end
    v.focus.activeWindowId = "w7"

    h.send(v)

    assertOrder(h, "a", {"w5", "w6", "w7", "w8"})
    assert(icon(h, "w7").props.border == "primary")

    nextPage()
    assertOrder(h, "a", {"w9", "w10", "w11"})

    v.workspaces.a.windowIds = {
        "w4", "w9", "w2", "w11", "w1", "w10",
        "w3", "w8", "w5", "w7", "w6"
    }

    for id, w in pairs(v.windows) do
        w.active = id == "w10"
    end
    v.focus.activeWindowId = "w10"

    h.send(v)

    assertOrder(h, "a", {"w9", "w10", "w11"})
    assert(icon(h, "w10").props.border == "primary")
    assert(#h.requests == 0)
end)

test("shrinking window count keeps the nearest available page", function()
    local v = ready(11)
    local h = host(v)

    local function nextPage()
        local more = find(h.tree, function(n)
            return n.props.key == "workspace:1:a:more"
        end)
        assert(more, "missing next-page control")
        more.props.onClick()
        h.tick()
    end

    nextPage()
    nextPage()
    assertOrder(h, "a", {"w9", "w10", "w11"})

    for i = 8, 11 do
        v.windows["w" .. i] = nil
    end

    v.workspaces.a.windowIds = {
        "w7", "w2", "w6", "w1", "w5", "w3", "w4"
    }

    h.send(v)

    assertOrder(h, "a", {"w5", "w6", "w7"})

    -- Restore the closed windows. The corrected second page should stay selected.
    for i = 8, 11 do
        local w = F.window("w" .. i, "a")
        w.output = v.workspaces.a.output
        w.app_id = "app-" .. i
        v.windows["w" .. i] = w
    end

    v.workspaces.a.windowIds = {
        "w7", "w2", "w6", "w1", "w5", "w3",
        "w4", "w8", "w9", "w10", "w11"
    }

    h.send(v)
    assertOrder(h, "a", {"w5", "w6", "w7", "w8"})

    -- Shrink again and confirm the corrected page remains selected.
    for i = 8, 11 do
        v.windows["w" .. i] = nil
    end

    v.workspaces.a.windowIds = {
        "w7", "w2", "w6", "w1", "w5", "w3", "w4"
    }

    h.send(v)
    assertOrder(h, "a", {"w5", "w6", "w7"})

    nextPage()
    assertOrder(h, "a", {"w1", "w2", "w3", "w4"})
    assert(#h.requests == 0)
end)

print("Inline window interaction: "..total.." tests passed")
