--!nonstrict
local State = require("./lib/state.luau")
local model = State.new()
local started, stopped, dirty = false, false, true
local checking = false
local lastLine = noctalia.nowMs()
local owner = tostring(lastLine)
local helper = nil
local launches = 0

local function publish()
    if dirty then
        noctalia.state.set("lattice.state", State.view(model))
        dirty = false
    end
end

local function onLine(line)
    if stopped then return end
    lastLine = noctalia.nowMs()
    local ok, message = pcall(noctalia.json.decode, line)
    if not ok or type(message) ~= "table" or type(message.data) ~= "table" then
        State.invalid(model)
    elseif message.event == "lattice.transport" then
        State.transport(model, message.data.status, message.data.generation)
    elseif message.event == "lattice.snapshot" then
        if message.data.generation == model.generation then State.liveness(model, true) end
        State.apply(model, message.data.snapshot, message.data.generation)
    elseif message.event == "lattice.invalid" then
        if message.data.generation == model.generation then
            State.invalid(model, message.data.family)
        end
    elseif message.event == "lattice.heartbeat" then
        -- Liveness is explicit; unchanged compositor state is not a timeout.
        if message.data.generation == model.generation then State.liveness(model, true) end
    else
        State.invalid(model)
    end
    dirty = true
end

local function quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function start()
    if started or stopped then return end
    if launches >= 4 then
        model.error = "reader_restart_limit"
        dirty = true
        return
    end
    local directory = noctalia.pluginDir()
    if not directory or not noctalia.commandExists("python3") then
        model.error = "python3_or_plugin_directory_unavailable"
        dirty = true
        return
    end
    -- exec eliminates the intermediate shell. The reader has parent-death
    -- protection and owns reconnection; repeated Luau stream callbacks do not
    -- accumulate on every compositor reconnect.
    helper = directory .. "/ipc_reader.py"
    started = noctalia.runStream("exec python3 -B -u " .. quote(helper)
        .. " --owner " .. quote(owner) .. " --generation-base " .. tostring(model.generation), onLine)
    launches = launches + 1
    lastLine = noctalia.nowMs()
    if not started then model.error = "stream_start_failed"; dirty = true end
end

function update()
    if started and not stopped and not checking and noctalia.nowMs() - lastLine > 6000 then
        State.liveness(model, false)
        dirty, checking = true, true
        -- Never infer child death from an idle compositor or launch duplicates.
        local accepted = noctalia.processMatches(function(alive)
            checking = false
            if stopped then return end
            if not alive then
                started = false
                State.transport(model, "disconnected", model.generation)
                dirty = true
            end
            lastLine = noctalia.nowMs()
        end, helper, "--owner " .. owner)
        if not accepted then checking = false; lastLine = noctalia.nowMs() end
    end
    start()
    publish() -- Coalesces bursts; no desktop state is polled.
end

function onExit(_signal, _reason)
    stopped = true
    State.transport(model, "stopped", model.generation)
    dirty = true
    publish()
    -- Noctalia cancels its owned stream on runtime teardown. The reader also
    -- handles SIGTERM, broken stdout, and abrupt parent death independently.
end

noctalia.setUpdateInterval(100)
start()
publish()
