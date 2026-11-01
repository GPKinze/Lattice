local root = arg[1] or "."
local State = dofile(root .. "/lib/state.luau")
local F = dofile(root .. "/tests/fixtures/synthetic.luau")
local total = 0
local function test(name, fn)
    assert(pcall(fn), name)
    total = total + 1
    print("ok " .. total .. " - " .. name)
end
local function host(options)
    options = options or {}
    local h = { now = 10, streams = 0, publications = 0, messages = {}, live = true }
    local env = setmetatable({}, { __index = _G })
    env.require = function(path) assert(path == "./lib/state.luau"); return State end
    env.noctalia = {
        nowMs = function() return h.now end,
        pluginDir = function() return "/synthetic/path with 'quote" end,
        commandExists = function(name) assert(name == "python3"); return not options.missing end,
        setUpdateInterval = function(ms) h.interval = ms end,
        state = { set = function(key, value)
            assert(key == "lattice.state")
            h.view, h.publications = value, h.publications + 1
        end },
        json = { decode = function(line)
            if line == "bad" then return nil, "synthetic invalid JSON" end
            if line == "throw" then error("decoder failure") end
            return h.messages[line]
        end },
        runStream = function(command, callback)
            h.streams, h.command, h.callback = h.streams + 1, command, callback
            return options.startFails ~= true
        end,
        processMatches = function(callback, helper, owner)
            assert(helper:find("ipc_reader.py", 1, true) and owner == "--owner 10")
            callback(h.live)
            return true
        end,
    }
    assert(loadfile(root .. "/service.luau", "t", env))()
    function h.send(event, data)
        h.messages.next = { event = event, data = data }
        h.callback("next")
    end
    h.env = env
    return h
end
test("single stream, fixed tick and safely quoted exec", function()
    local h = host()
    for _ = 1, 50 do h.env.update() end
    assert(h.streams == 1 and h.interval == 100)
    assert(h.command:sub(1, 5) == "exec " and h.command:find("'\\''", 1, true))
end)
test("initial snapshots and burst publication are coalesced", function()
    local h = host()
    h.send("lattice.transport", { status = "connected", generation = 1 })
    for _, family in ipairs({"windows", "outputs", "workspaces"}) do
        local data = family == "workspaces" and F.unicode() or family == "outputs" and { F.output() } or {}
        h.send("lattice.snapshot", { generation = 1, snapshot = { event = family, data = data } })
    end
    assert(not h.view.ready and h.publications == 1)
    h.env.update()
    assert(h.view.ready and h.publications == 2)
    for _ = 1, 500 do h.send("lattice.heartbeat", { generation = 1 }) end
    h.env.update()
    assert(h.publications == 3 and h.streams == 1)
end)
test("invalid JSON and decoder exceptions never escape", function()
    local h = host()
    h.callback("bad"); h.callback("throw"); h.env.update()
    assert(h.view.invalidEvents == 2 and not h.view.ready)
end)
test("disconnect and reconnect reuse owned child", function()
    local h = host()
    h.send("lattice.transport", { status = "connected", generation = 1 })
    h.send("lattice.transport", { status = "disconnected", generation = 1 })
    h.env.update(); assert(not h.view.ready)
    h.send("lattice.transport", { status = "connected", generation = 2 })
    h.env.update()
    assert(h.view.generation == 2 and h.streams == 1)
end)
test("watchdog restarts only after confirmed process death", function()
    local h = host()
    h.now = 8000; h.env.update()
    assert(h.streams == 1)
    h.live = false; h.now = 16000; h.env.update()
    assert(h.streams == 2)
end)
test("teardown ignores queued lines and prevents restart", function()
    local h = host()
    h.env.onExit(15, "disable")
    h.send("lattice.transport", { status = "connected", generation = 1 })
    h.now = 99999; h.env.update()
    assert(h.view.status == "stopped" and h.streams == 1)
end)
test("missing dependency fails visibly without launch", function()
    local h = host({ missing = true })
    assert(h.streams == 0 and h.view.error == "python3_or_plugin_directory_unavailable")
end)
test("failed launch is retried without assuming a child exists", function()
    local h = host({ startFails = true })
    h.env.update()
    assert(h.streams == 2 and h.view.error == "stream_start_failed")
end)
test("live reader stall recovers without spawning another process", function()
    local h = host()
    h.send("lattice.transport", { status = "connected", generation = 1 })
    h.now = 8000; h.env.update()
    assert(h.view.status == "unresponsive" and h.streams == 1)
    h.send("lattice.heartbeat", { generation = 1 }); h.env.update()
    assert(h.view.status == "synchronizing" and h.streams == 1)
end)
test("unexpected helper death retries are bounded", function()
    local h = host()
    h.live = false
    for i = 1, 20 do h.now = i * 8000; h.env.update() end
    assert(h.streams == 4 and h.view.error == "reader_restart_limit")
end)
print("Service: " .. total .. " tests passed")
