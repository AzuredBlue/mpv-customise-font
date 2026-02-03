local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local mpoptions = require('mp.options')

local DEFAULT_PLAYRESX = 640
local DEFAULT_PLAYRESY = 360
local cached_scale = nil

-- The fonts to be replaced with "only_modify_default_font"
-- Default meaning the main font used for subtitles
-- avoiding to replace other fonts, like signs
local default_styles = {}
local matching_styles = {}
local ass_subtitle = false
local sub_data = nil

local style_combinations = 0

local abort_handle = nil

-- Forward declarations
local parsed_style_map = nil
local apply_ass_style = nil
local prefix_style = nil
local should_conserve = nil


-- Script replaces sub-ass-style-override, if there were any other overrides in conf
-- save them for "Default"
local existing_sub_style = nil;

-- All of these options can be modified in the customise_font.conf
local options = {
    -- Show which fonts are being replaced
    debug = false,
    -- If it should set the subs to a higher position than default
    set_sub_pos = true,
    -- If it should only try to modify the font used for subtitles, instead of all
    only_modify_default_font = true,
    -- If not nil, it will override the ass font size with this value, multiplied by the scale factor
    -- from PlayResX. I would recommend around ~26
    ass_font_size = 0,

    -- If it should try to conserve the colors of the original fonts
    -- If your style doesnt set the colours, it will conserve the originals
    -- If it sets the color of the  font, this will override that if theres more than
    -- 1 font with different colors
    conserve_style_color = true,

    -- Font sizes for SRT. 44-48 seems to be the best for me.
    -- Scale is the value the default font size is multiplied by
    -- when alternate_size is on. I recommend values 0.9 - 1.1
    default_font_size = 44,
    alternate_font_scale = 0.95,

    -- Default style values
    -- These are modified whenever you change style, no need to manually modify them
    ass_index = 1,
    non_ass_index = 1,
    alternate_size = false,

    -- Blacklist these from being guessed as the default value
    -- blacklist = { "sign", "song", "^ed", "^op", "title", "^os", "ending", "opening"}
    blacklist = "sign;song;^ed;^op;title;^os;ending;opening;kfx;karaoke;eyecatch"
}

mpoptions.read_options(options, "customise_font")

if type(options.blacklist) == "string" and options.blacklist ~= "" then
    local dirs = {}
    for dir in string.gmatch(options.blacklist, "([^,;]+)") do
        table.insert(dirs, (dir:gsub("^%s*(.-)%s*$", "%1"):gsub('[\'"]', '')))
    end
    options.blacklist = dirs
elseif type(options.blacklist) == "string" then
    options.blacklist = {}
end

-- Add your own styles here
local styles = require("styles")

local script_dir = (debug.getinfo(1).source:match("@?(.*/)") or "./")

local script_opts_dir = script_dir:match("^(.-)[/\\]scripts[/\\]")

if script_opts_dir then
    script_opts_dir = utils.join_path(script_opts_dir, "script-opts")
else
    script_opts_dir = os.getenv("APPDATA") and
        utils.join_path(utils.join_path(os.getenv("APPDATA"), "mpv"), "script-opts") or
        os.getenv("HOME") and
        utils.join_path(utils.join_path(utils.join_path(os.getenv("HOME"), ".config"), "mpv"), "script-opts") or
        nil
end

local function get_config_path()
    return script_opts_dir
end

local function printDebug(...)
    if options.debug then
        print(...)
    end
end

local function get_playres_scale()
    if cached_scale then return cached_scale end
    if sub_data == "" then return 1.0 end

    local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)")) or DEFAULT_PLAYRESX
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)")) or DEFAULT_PLAYRESY

    cached_scale = math.max(playresx / DEFAULT_PLAYRESX, playresy / DEFAULT_PLAYRESY)
    return cached_scale
end

local function scale_ass_style(style, scale)
    if scale == 1 then return style end

    return style:gsub("([%w]+)=([%d%.]+)", function(key, val)
        local scaled_properties = { Outline = true, Shadow = true, MarginV = true }
        if scaled_properties[key] then
            return string.format("%s=%.1f", key, tonumber(val) * scale)
        end
        return string.format("%s=%s", key, val)
    end)
end

-- Try to get the 'most popular one'
local function matches_blacklist(name)
    local lower = name:lower()
    -- Also match OP and ED capitalised
    if name:find("OP") or name:find("ED") then
        return true
    end

    if type(options.blacklist) == "table" then
        for _, pat in ipairs(options.blacklist) do
            if lower:find(pat) then
                return true
            end
        end
    end
    return false
end

-- Parse the styles from the subtitle
local function build_style_map()
    if parsed_style_map then return end
    parsed_style_map = {}
    
    if not sub_data then return end

    for style_line in sub_data:gmatch("Style:([^\r\n]+)") do
        local params = {}
        for param in style_line:gmatch("([^,]+)") do
            table.insert(params, param:match("^%s*(.-)%s*$"))
        end
        if #params >= 7 then
            local name = params[1]
            local fontname = params[2]
            local fontsize = params[3]
            parsed_style_map[name] = { 
                font = fontname, 
                size = tonumber(fontsize) or 0,
                primary_color = params[4],
                secondary_color = params[5],
                outline_color = params[6],
                back_color = params[7]
            }
        end
    end
end

local function guess_font_from_metadata()
    if not options.only_modify_default_font then return end
    if not sub_data or not sub_data:find("Styles%]") then return end

    local blacklist = options.blacklist
    local whitelist = { "default" }

    local function matches_whitelist(name)
        local lower = name:lower()
        for _, pat in ipairs(whitelist) do
            if lower == pat or lower:find(pat) then
                return true
            end
        end
        return false
    end
    
    build_style_map()

    -- Avoid small-sized fonts, usually used for signs
    local scale = get_playres_scale()
    local minimum_size = math.floor(18 * scale + 0.5)

    local freq = {}
    local styleDetails = {}
    local orderKeys = {}
    local max_freq = 0
    local max_count = 0
    printDebug("Fonts guessing from:")
    
    for name, info in pairs(parsed_style_map) do
         if not matches_blacklist(name) and info.size > minimum_size then
            local key = info.font .. "|" .. info.size

            if not freq[key] then
                freq[key] = 0
                table.insert(orderKeys, key)
            end
            freq[key] = freq[key] + 1

            if freq[key] > max_freq then
                max_freq = freq[key]
                max_count = 1
            elseif freq[key] == max_freq then
                max_count = max_count + 1
            end

            styleDetails[key] = styleDetails[key] or {}
            local style_info = {
                name = name,
                font = info.font,
                size = info.size,
                primary_color = info.primary_color,
                secondary_color = info.secondary_color,
                outline_color = info.outline_color,
                back_color = info.back_color
            }
            table.insert(styleDetails[key], style_info)

            printDebug(string.format("Style: %s - %s, %s, %s, %s, %s, %s",
                    name, info.font, info.size,
                    info.primary_color, info.secondary_color, info.outline_color, info.back_color))
        end
    end
    
    style_combinations = #orderKeys

    if next(freq) ~= nil then
        printDebug("Font+Size frequencies:")
        for key, count in pairs(freq) do
            printDebug("  " .. key .. ": " .. count)
        end
    end

    -- Choose the key to replace
    local chosenKey, firstTiedKey = nil, nil

    -- Choose the most common key
    for _, key in ipairs(orderKeys) do
        if freq[key] == max_freq then
            -- Choose from the ones that are the most common
            if not firstTiedKey then
                firstTiedKey = key
            end
            -- If theres more than 1 key tied in first place
            if max_count > 1 then
                -- Try to match it to the whitelist to decide
                for _, style_info in ipairs(styleDetails[key]) do
                    if matches_whitelist(style_info.name) then
                        chosenKey = key
                        break
                    end
                end
            end
            if chosenKey then break end
        end
    end
    if not chosenKey then
        chosenKey = firstTiedKey
    end

    -- For some reason, this runs faster than auto-selecting subtitles
    -- So sub_data can have old information
    -- If sub_data happens to have only blacklisted styles, it will error
    -- And only doing a return here will make it so it has enough time for sub_data
    -- to update to the new track
    -- I've spent so much time debugging this.
    if not chosenKey then
        printDebug("No key was chosen!")
        return
    end

    default_styles = styleDetails[chosenKey]
    matching_styles = {}

    -- TODO: If it uses the same font and the size is similar, consider it too? Need to test.

    for _, style_info in ipairs(default_styles) do
        table.insert(matching_styles, style_info.name)
        matching_styles[style_info.name] = {
            name = style_info.name,
            font = style_info.font,
            size = tonumber(style_info.size),
            primary_color = style_info.primary_color,
            secondary_color = style_info.secondary_color,
            outline_color = style_info.outline_color,
            back_color = style_info.back_color
        }
    end

    local style_list_str = (#matching_styles > 0 and table.concat(matching_styles, ", ")) or "none"
    printDebug(string.format("Heuristic approach chose: replacing font '%s' (size %s) used by %d styles: %s",
        default_styles[1] and default_styles[1].font or "nil",
        default_styles[1] and default_styles[1].size or "nil",
        #matching_styles,
        style_list_str))
end

local function get_default_font_and_styles()
    -- Heuristic guess of the "default" font, based on the most used style.
    guess_font_from_metadata()

    -- Apply the guessed styles immediately
    apply_ass_style()

    -- The heuristic approach can fail sometimes, so try to find the actual default font using ffmpeg
    -- It is slower, hence we apply the heuristic first since it's basically instant.

    -- Don't bother with only 1 style, thats the default.
    if style_combinations == 1 then
        return
    end

    local path = mp.get_property("path")
    local track = mp.get_property_native("current-tracks/sub")
    
    if not path or not track or not track["ff-index"] then
        return
    end

    local start_time = mp.get_time()
    
    local video_duration = mp.get_property_native("duration") or 0
    local seek_time = 0
    if video_duration > 0 then
        -- Seek to a halfway point to avoid the opening and ending
        seek_time = video_duration * 0.65
    end

    -- Take a sample of 2 minutes of the subtitle track to get the most used font+size combination
    local args = {
        "ffmpeg", 
        "-loglevel", "quiet", 
        "-ss", string.format("%.2f", seek_time),
        "-i", path, 
        "-t", "120",
        "-map", "0:" .. track["ff-index"], 
        "-f", "ass", 
        "-"
    }

    -- Abort any pending FFmpeg process from a previous call
    if abort_handle then
        mp.abort_async_command(abort_handle)
        abort_handle = nil
    end

    abort_handle = mp.command_native_async({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, res, err)
        abort_handle = nil
        if not success or not res or res.status ~= 0 then
            return
        end

        if mp.get_property("path") ~= path then
            return
        end
        
        local content = res.stdout
        if not content or content == "" then
            return
        end

        local style_usage = {}

        for line in content:gmatch("[^\r\n]+") do
            if line:match("^Dialogue:") then
                -- Format: Dialogue: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
                local style = line:match("Dialogue:%s*[^,]+,[^,]+,[^,]+,([^,]+)")
                if style then
                    style = style:match("^%s*(.-)%s*$")
                    if not matches_blacklist(style) then
                        style_usage[style] = (style_usage[style] or 0) + 1
                    end
                end
            end
        end

        local font_size_usage = {}
        local max_usage = 0
        local most_used_key = nil

        for style, count in pairs(style_usage) do
            local info = parsed_style_map[style]
            if info then
                local key = info.font .. "|" .. info.size
                font_size_usage[key] = (font_size_usage[key] or 0) + count
                
                if font_size_usage[key] > max_usage then
                    max_usage = font_size_usage[key]
                    most_used_key = key
                end
            end
        end
        
        local end_time = mp.get_time()
        local duration_taken = end_time - start_time
        
        if most_used_key then
            local target_font, target_size_str = most_used_key:match("^(.-)|(.*)$")
            local target_size = tonumber(target_size_str) or 0
            
            default_styles = {}
            matching_styles = {}
            
            for name, info in pairs(parsed_style_map) do
                if info.font == target_font and math.abs(info.size - target_size) <= 1 then
                    local style_data = {
                        name = name,
                        font = info.font,
                        size = info.size,
                        primary_color = info.primary_color,
                        secondary_color = info.secondary_color,
                        outline_color = info.outline_color,
                        back_color = info.back_color
                    }
                    table.insert(default_styles, style_data)
                    table.insert(matching_styles, name)
                    matching_styles[name] = style_data
                end
            end
            
            local style_list = table.concat(matching_styles, ", ")
            printDebug(string.format("FFmpeg detected font: %s (Size: %s) used by [%s] (%.4fs)", target_font, target_size, style_list, duration_taken))
            
            -- Apply the new detected default style
            apply_ass_style()
        else 
            printDebug(string.format("Could not detect font (%.4fs)", duration_taken))
        end
    end)
end

should_conserve = function()
    local unique_outline_colors = {}
    for _, style_info in ipairs(default_styles) do
        local outline_color = style_info.outline_color

        if outline_color then
            if not unique_outline_colors[outline_color] then
                unique_outline_colors[outline_color] = true
            end
        end
    end

    local count = 0
    for _ in pairs(unique_outline_colors) do count = count + 1 end

    -- If theres only one outline color, give priority to the one in ass overrides
    -- If theres multiple, conserve, since:
    -- If it contains black, its probably the default font, and the other colors are the ALTs
    -- If it doesnt, trying to guess what to replace and not is a pain, so just conserve.

    return count > 1
end

-- Prefix the style with the style names, so it only changes them.
prefix_style = function(scaled_style)
    local all_parts = {}
    local conserve = should_conserve()
    -- How dark the outline needs to be to be replaced
    local DARKNESS_THRESHOLD = 0.03

    local function hex_to_rgb(h)
        h = h:gsub("^#", "")
        if #h == 3 then
            h = h:sub(1, 1) .. h:sub(1, 1) .. h:sub(2, 2) .. h:sub(2, 2) .. h:sub(3, 3) .. h:sub(3, 3)
        end
        h = h:sub(-6)
        local r = tonumber(h:sub(1, 2), 16) or 0
        local g = tonumber(h:sub(3, 4), 16) or 0
        local b = tonumber(h:sub(5, 6), 16) or 0
        return r, g, b
    end

    local function srgb_to_linear(c)
        c = c / 255.0
        if c <= 0.03928 then
            return c / 12.92
        else
            return ((c + 0.055) / 1.055) ^ 2.4
        end
    end

    local function luminance_from_hex(h)
        local r, g, b = hex_to_rgb(h)
        local rl = srgb_to_linear(r)
        local gl = srgb_to_linear(g)
        local bl = srgb_to_linear(b)
        return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
    end

    -- if conserve and options.conserve_style_color and options.debug then
    --     print("More than 1 color detected in the font! Conserving colors.")
    -- end

    for _, style_name in ipairs(matching_styles) do
        local parts = {}
        local info = matching_styles[style_name]

        for param in scaled_style:gmatch("([^,]+)") do
            local key, value = param:match("^([^=]+)=(.+)$")

            if key and value then
                if options.conserve_style_color and conserve and key:find("Colour$") then
                    local color_field = key:lower():gsub("colour", "_color")

                    -- Decide if the specific color should be modified
                    local modify = false
                    if info and color_field and info[color_field] then
                        local colorval = tostring(info[color_field])
                        local hex = colorval:match("([0-9a-fA-F]+)$")

                        if hex and #hex >= 6 then
                            hex = hex:sub(-6):lower()
                            hex = hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2)

                            local lum = luminance_from_hex(hex)

                            if ((color_field == "outline_color" or color_field == "back_color") and lum <= DARKNESS_THRESHOLD)
                                or (color_field == "primary_color" and hex == "ffffff")
                                or (color_field == "secondary_color" and hex == "ff0000") then
                                modify = true
                            end
                        end
                    end

                    if modify then
                        table.insert(parts, string.format("%s.%s=%s", style_name, key, value))
                    end
                else
                    table.insert(parts, string.format("%s.%s=%s", style_name, key, value))
                end
            else
                table.insert(parts, param)
            end
        end
        table.insert(all_parts, table.concat(parts, ","))
    end

    return table.concat(all_parts, ",")
end

apply_ass_style = function()
    local style = styles.ass[options.ass_index]
    if not style then return end

    -- If its the "Default" style, use the user's mpv.conf style
    if style == "" and existing_sub_style ~= nil then
        mp.set_property("sub-ass-style-overrides", existing_sub_style)
        return
    end

    -- Scale the style based on the PlayRes
    local scale = get_playres_scale()
    local scaled_style = style

    if options.alternate_size and #default_styles > 0 then
        scale = scale * options.alternate_font_scale

        local first_style = default_styles[1]
        if first_style then
            local size = first_style.size
            local existing_fs = scaled_style:match("FontSize=([%d%.]+)")

            if options.ass_font_size ~= 0 or existing_fs then
                size = existing_fs and tonumber(existing_fs) or options.ass_font_size
                size = math.floor(size * scale + 0.5)
            end

            if size then
                size = math.floor((options.alternate_font_scale * tonumber(size)) + 0.5)
                scaled_style = scaled_style:gsub(",?FontSize=[%d%.]+", "")
                scaled_style = scaled_style .. string.format(",FontSize=%d", size)
            end
        end
    else
        local existing_fs = scaled_style:match("FontSize=([%d%.]+)")
        -- Override also if not on alternate size
        if options.ass_font_size ~= 0 or existing_fs then
            -- If scaled_style already contains a FontSize= value, use that as the base size.
            local base_size = existing_fs and tonumber(existing_fs) or options.ass_font_size
            -- Remove any existing FontSize=... to avoid duplication when appending the computed value
            scaled_style = scaled_style:gsub(",?FontSize=[%d%.]+", "")
            local size = math.floor(base_size * scale + 0.5)
            scaled_style = scaled_style .. string.format(",FontSize=%d", size)
        end
    end

    scaled_style = scale_ass_style(scaled_style, scale)

    if #matching_styles > 0 then
        scaled_style = prefix_style(scaled_style)
    end

    -- local aspect_ratio = mp.get_property("video-params/aspect-name")
    -- Doesnt work since it can be nil when launching, width and height cant be nil
    local w = mp.get_property("video-params/w", 1920)
    local h = mp.get_property("video-params/h", 1080)
    local dar = w / h
    local dar_r = math.floor(dar * 100 + 0.5) / 100
    local aspect_ratio = string.format("%.2f:1", dar_r)

    -- Fallback LayoutRes if not in 16:9 (can mess up subtitles)
    if aspect_ratio ~= "1.78:1" then
        scaled_style = scaled_style .. ",LayoutResX=0,LayoutResY=0"
    end

    mp.set_property("sub-ass-style-overrides", scaled_style)

    if options.set_sub_pos then mp.set_property("sub-pos", 98) end
end

local function apply_non_ass_style()
    local style = styles.non_ass[options.non_ass_index]
    if not style then return end

    font_size = options.default_font_size
    if options.alternate_size then
        font_size = math.floor(options.alternate_font_scale * options.default_font_size + 0.5)
    end

    mp.set_property_native("sub-font-size", font_size)

    for key, value in pairs(style) do
        if key ~= "name" then
            local mpv_property_name = "sub-" .. string.gsub(key, "_", "-")
            mp.set_property_native(mpv_property_name, value)
        end
    end

    if options.set_sub_pos then mp.set_property("sub-pos", 98) end
end

local function save_config()
    local config_path = utils.join_path(get_config_path(), "customise_font.conf")

    local dynamic = {
        ass_index = options.ass_index,
        non_ass_index = options.non_ass_index,
        alternate_size = options.alternate_size and "yes" or "no"
    }

    local lines = {}
    local handled = {}
    local file = io.open(config_path, "r")
    if file then
        for line in file:lines() do
            local key = line:match("^%s*([%w_]+)%s*=")
            if key and dynamic[key] then
                table.insert(lines, string.format("%s=%s", key, dynamic[key]))
                handled[key] = true
            else
                table.insert(lines, line)
            end
        end
        file:close()
    end

    for key, value in pairs(dynamic) do
        if not handled[key] then
            table.insert(lines, string.format("%s=%s", key, value))
        end
    end

    file = io.open(config_path, "w")
    if file then
        file:write(table.concat(lines, "\n"))
        file:close()
    end
end

local function is_ass_subtitle()
    if ass_subtitle == nil then
        local track = mp.get_property_native("current-tracks/sub")
        ass_subtitle = track and track.codec == "ass"
    end

    return ass_subtitle
end

local function toggle_font_size()
    options.alternate_size = not options.alternate_size
    if is_ass_subtitle() then
        apply_ass_style()
        mp.osd_message("ASS Font Size: " .. (options.alternate_size and "Alt" or "Normal"), 2)
    else
        apply_non_ass_style()
        mp.osd_message("SRT Font Size: " .. (options.alternate_size and "Alt" or "Normal"), 2)
    end
end

local function cycle_styles(direction)
    if is_ass_subtitle() then
        options.ass_index = (options.ass_index + direction - 1) % #styles.ass + 1
        apply_ass_style()
        local style_str = styles.ass[options.ass_index]
        local style_name = style_str:match("FontName=([^,]+)") or "Default"
        mp.osd_message("ASS Style: " .. style_name .. " (" .. options.ass_index .. ")", 2)
    else
        options.non_ass_index = (options.non_ass_index + direction - 1) % #styles.non_ass + 1
        apply_non_ass_style()
        mp.osd_message("SRT Style: " .. styles.non_ass[options.non_ass_index].name, 2)
    end
end

-- Change default font when the subtitles are changed
mp.observe_property("current-tracks/sub", "native", function(name, value)
    if existing_sub_style == nil then
        existing_sub_style = mp.get_property("sub-ass-style-overrides");
    end

    ass_subtitle = nil
    cached_scale = nil
    parsed_style_map = nil
    if is_ass_subtitle() then
        printDebug("Detected change in subtitle tracks!")
        sub_data = mp.get_property("sub-ass-extradata") or ""
        get_default_font_and_styles()
    else
        apply_non_ass_style()
    end
end
)

-- Save config on shutdown
mp.register_event("shutdown", function()
    save_config()
end)

local function reload()
    package.loaded["styles"] = nil
    styles = require("styles")
    cycle_styles(0)
end

-- Key Bindings
mp.add_key_binding("k", "cycle_styles_forward", function() cycle_styles(1) end)
mp.add_key_binding("K", "cycle_styles_backward", function() cycle_styles(-1) end)
mp.add_key_binding("Ctrl+k", "toggle_font_size", toggle_font_size)
mp.add_key_binding("Ctrl+r", "reload", reload)
