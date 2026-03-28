local mp = require 'mp'
local msg = require 'mp.msg'
local options = require 'mp.options'

local rtxvsr_opts = {
    autoload_enable = false,
    autocrop_disable = false,
    autocrop_label = "autocrop",
    osd = "RTX VSR",
    label = "rtxvsr",
    max_height = 2160,
    min_scale = 1.0000,
    precision = 4,
}
options.read_options(rtxvsr_opts)

mp.set_property_native("user-data/" .. rtxvsr_opts.label, false)

local function set_userdata(bool)
    mp.set_property_native("user-data/" .. rtxvsr_opts.label, bool)
end

local function disable_autocrop()
    if mp.get_property_native("user-data/" .. rtxvsr_opts.autocrop_label) then
        mp.commandv("script-message-to", "toggle_autocrop", "disable")
    end
end

local function remove_rtxvsr()
    local vf = mp.get_property("vf") or ""
    if not vf:find(rtxvsr_opts.label, 1, true) then return end

    mp.commandv("vf", "remove", "@" .. rtxvsr_opts.label)
    set_userdata(false)
end

local function limit_rtxvsr()
    if mp.get_property("current-gpu-context") ~= "d3d11" then
        msg.warn("Limit: d3d11 only")
        return false
    end

    if mp.get_property_native("current-tracks/video/image") then
        msg.warn("Limit: video only")
        return false
    end

    local display_height = mp.get_property_native("display-height")
    local image_height = mp.get_property_native("height")
    if not display_height or not image_height then
        msg.warn("Limit: no video")
        return false
    elseif image_height >= rtxvsr_opts.max_height then
        msg.warn("Limit: height >= " .. rtxvsr_opts.max_height)
        return false
    end

    local multiplier = 10 ^ rtxvsr_opts.precision
    local scale = math.floor(display_height / image_height * multiplier + 0.5) / multiplier
    if scale <= rtxvsr_opts.min_scale then
        msg.warn("Limit: scale <= " .. rtxvsr_opts.min_scale)
        return false
    end

    return scale
end

local function insert_rtxvsr()
    local scale = limit_rtxvsr()
    if not scale then return false end

    local command = string.format("@%s:d3d11vpp=scale=%s:scaling-mode=nvidia", rtxvsr_opts.label, scale)
    mp.commandv("vf", "append", command)
    set_userdata(true)
    return true
end

local toggle_handlers = {
    enable = function(suppress_osd)
        if rtxvsr_opts.autocrop_disable then disable_autocrop() end
        if not insert_rtxvsr() then return end
        if not suppress_osd then
            mp.osd_message(rtxvsr_opts.osd .. ": yes")
        end
    end,
    disable = function(suppress_osd)
        remove_rtxvsr()
        if not suppress_osd then
            mp.osd_message(rtxvsr_opts.osd .. ": no")
        end
    end,
}

local function handle_toggle(command, suppress_osd)
    if command == "enable" then
        if mp.get_property_native("user-data/" .. rtxvsr_opts.label) then return end
        toggle_handlers.enable(suppress_osd)
    elseif command == "disable" then
        if not mp.get_property_native("user-data/" .. rtxvsr_opts.label) then return end
        toggle_handlers.disable(suppress_osd)
    else
        toggle_handlers[mp.get_property_native("user-data/" .. rtxvsr_opts.label) and "disable" or "enable"]()
    end
end

local function handle_autoload()
    if not rtxvsr_opts.autoload_enable then return end

    remove_rtxvsr()
    if not insert_rtxvsr() then end
end

mp.register_event("file-loaded", handle_autoload)
mp.register_event("end-file", function() handle_toggle("disable", true) end)
mp.register_script_message("toggle_rtxvsr", handle_toggle)
mp.register_script_message("enable", function() handle_toggle("enable", true) end)
mp.register_script_message("disable", function() handle_toggle("disable", true) end)
