local mp = require 'mp'
local msg = require 'mp.msg'
local options = require 'mp.options'

local autocrop_opts = {
    hwdec_enable = false,
    hwdec_zerocopy = "auto",
    hwdec_copyback = "auto-copy",
    rtxvsr_disable = false,
    rtxvsr_label = "rtxvsr",
    osd = "Autocrop",
    label = "autocrop",
    cropdetect_limit = "24/255",
    cropdetect_round = 16,
    min_apply_width = 0.5,
    min_apply_height = 0.5,
}
options.read_options(autocrop_opts)

mp.set_property_native("user-data/" .. autocrop_opts.label, false)

local autocrop_state = false
local autocrop_eval = false
local cropdetect_poll_timer = nil
local commit_autocrop_sec = 0
local pending_autocrop_time = 0
local pending_autocrop = { w = nil, h = nil, x = nil, y = nil }
local last_autocrop = { w = nil, h = nil, x = nil, y = nil }

local function disable_rtxvsr()
    if mp.get_property_native("user-data/" .. autocrop_opts.rtxvsr_label) then
        mp.commandv("script-message-to", "toggle_rtxvsr", "disable")
    end
end

local function set_userdata(bool)
    mp.set_property_native("user-data/" .. autocrop_opts.label, bool)
end

local function set_hwdec(mode)
    if not autocrop_opts.hwdec_enable then
        mp.set_property("hwdec", "no")
    elseif mode == "zerocopy" then
        mp.set_property("hwdec", autocrop_opts.hwdec_zerocopy)
    elseif mode == "copyback" then
        mp.set_property("hwdec", autocrop_opts.hwdec_copyback)
    end
end

local function get_poll_interval(fps)
    local poll_interval = math.max(math.floor(10 / fps * 10 + 0.5) / 10, 0.1)
    commit_autocrop_sec = poll_interval * 2

    return poll_interval
end

local function remove_autocrop()
    local vf = mp.get_property("vf") or ""
    if not vf:find(autocrop_opts.label, 1, true) then return end

    mp.commandv("vf", "remove", "@" .. autocrop_opts.label)
    mp.set_property("video-crop", "")
end

local function insert_autocrop(fps, poll_interval)
    local reset_frames = math.max(math.floor(poll_interval * fps + 0.5) - 2, 1)
    mp.commandv("vf", "pre", string.format("@%s:cropdetect=limit=%s:reset=%d:round=%d",
        autocrop_opts.label, autocrop_opts.cropdetect_limit, reset_frames, autocrop_opts.cropdetect_round))
end

local function apply_autocrop(meta)
    local is_effective = meta.w and meta.h and meta.x and meta.y and (meta.x > 0 or meta.y > 0 or meta.w < meta.max_w or meta.h < meta.max_h)
    local is_excessive = false
    if is_effective and (meta.w < meta.min_w or meta.h < meta.min_h) then
        msg.warn("Limit: crop < " .. meta.min_w .. "x" .. meta.min_h)
        is_excessive = true
    end

    if not is_effective or is_excessive then
        mp.set_property("video-crop", "")
        return
    end

    mp.set_property("video-crop", string.format("%dx%d+%d+%d", meta.w, meta.h, meta.x, meta.y))
end

local function commit_autocrop(w, h, x, y)
    local now = mp.get_time()
    if w == pending_autocrop.w and h == pending_autocrop.h and x == pending_autocrop.x and y == pending_autocrop.y then
        if now - pending_autocrop_time < commit_autocrop_sec then
            return
        end
    else
        pending_autocrop = { w = w, h = h, x = x, y = y }
        pending_autocrop_time = now
        return
    end

    last_autocrop = { w = w, h = h, x = x, y = y }
    pending_autocrop_time = 0

    local width = mp.get_property_native("width")
    local height = mp.get_property_native("height")
    apply_autocrop({
        w = tonumber(w),
        h = tonumber(h),
        x = tonumber(x),
        y = tonumber(y),
        min_w = width * autocrop_opts.min_apply_width,
        min_h = height * autocrop_opts.min_apply_height,
        max_w = width,
        max_h = height
    })
end

local function update_autocrop()
    local cropdetect_metadata = mp.get_property_native("vf-metadata/" .. autocrop_opts.label)
    if not cropdetect_metadata then return end

    local w = cropdetect_metadata["lavfi.cropdetect.w"]
    local h = cropdetect_metadata["lavfi.cropdetect.h"]
    local x = cropdetect_metadata["lavfi.cropdetect.x"]
    local y = cropdetect_metadata["lavfi.cropdetect.y"]
    if not (w and h and x and y) then return end

    if w == last_autocrop.w and h == last_autocrop.h
       and x == last_autocrop.x and y == last_autocrop.y then
        return
    end

    commit_autocrop(w, h, x, y)
end

local function limit_autocrop()
    if not autocrop_eval
        or mp.get_property_native("pause") ~= false
        or mp.get_property_native("speed") ~= 1
        or mp.get_property_native("seeking") then
        return
    end

    update_autocrop()
end

local function seek_autocrop_suspend()
    last_autocrop = { w = nil, h = nil, x = nil, y = nil }
    pending_autocrop = { w = nil, h = nil, x = nil, y = nil }
    pending_autocrop_time = 0
    autocrop_eval = false
end

local function playback_autocrop_resume()
    autocrop_eval = true
end

local function cleanup_autocrop()
    remove_autocrop()
    if cropdetect_poll_timer then
        cropdetect_poll_timer:kill()
        cropdetect_poll_timer = nil
    end
end

local function start_autocrop()
    if mp.get_property_native("current-tracks/video/image") then
        msg.warn("Limit: video only")
        return false
    end

    local fps = mp.get_property_native("container-fps")
    if not fps then
        msg.warn("Limit: no video")
        return false
    end

    local poll_interval = get_poll_interval(fps)
    insert_autocrop(fps, poll_interval)
    autocrop_eval = true
    cropdetect_poll_timer = mp.add_periodic_timer(poll_interval, limit_autocrop)
    return true
end

local toggle_handlers = {
    enable = function(suppress_osd)
        if autocrop_opts.rtxvsr_disable then disable_rtxvsr() end

        set_hwdec("copyback")
        if not start_autocrop() then
            set_userdata(false)
            set_hwdec("zerocopy")
            return
        end

        mp.register_event("seek", seek_autocrop_suspend)
        mp.register_event("playback-restart", playback_autocrop_resume)
        autocrop_state = true
        set_userdata(true)
        if not suppress_osd then
            mp.osd_message(autocrop_opts.osd .. ": yes")
        end
    end,
    disable = function(suppress_osd)
        mp.unregister_event(seek_autocrop_suspend)
        mp.unregister_event(playback_autocrop_resume)
        cleanup_autocrop()
        autocrop_state = false
        set_userdata(false)
        set_hwdec("zerocopy")
        if not suppress_osd then
            mp.osd_message(autocrop_opts.osd .. ": no")
        end
    end,
}

local function handle_toggle(command, suppress_osd)
    if command == "enable" then
        if autocrop_state then return end
        toggle_handlers.enable(suppress_osd)
    elseif command == "disable" then
        if not autocrop_state then return end
        toggle_handlers.disable(suppress_osd)
    else
        toggle_handlers[autocrop_state and "disable" or "enable"]()
    end
end

mp.register_event("end-file", function() handle_toggle("disable", true) end)
mp.register_script_message("toggle_autocrop", handle_toggle)
mp.register_script_message("enable", function() handle_toggle("enable", true) end)
mp.register_script_message("disable", function() handle_toggle("disable", true) end)
