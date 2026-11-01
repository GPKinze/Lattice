-- Synthetic only. Names intentionally exercise exact compositor labels.
local F = {}
function F.output(name, active, focused)
    return { name = name or "OUT-A", enabled = true, powered = true,
        focused = focused == true, active_workspace = active or "",
        position = { x = 0, y = 0 }, logical_size = { width = 1920, height = 1080 }, scale = 1 }
end
function F.workspace(id, index, name, output, named)
    return { id = id, index = index, name = name, output = output or "OUT-A",
        named = named ~= false, active = index == 1, focused = index == 1,
        occupied = false, window_count = 0, focused_window = "", urgent = false,
        layout = "dwindle", layout_override = false }
end
function F.window(id, workspace, output)
    return { id = id, workspace = workspace or "stable-a", output = output or "OUT-A",
        app_id = "org.example.Editor", title = "Synthetic document", pid = 12345,
        active = false, focused = false, pinned = false, minimized = false,
        visible = true, urgent = false, floating = false, x = 10, y = 20, w = 800, h = 600 }
end
function F.unicode()
    local result = {}
    for i, name in ipairs({ "一", "二", "三", "四", "五" }) do
        result[i] = F.workspace("stable-" .. i, i, name)
    end
    return result
end
return F
