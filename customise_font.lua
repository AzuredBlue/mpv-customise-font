local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local mpoptions = require('mp.options')

local DEFAULT_PLAYRESX = 640
local DEFAULT_PLAYRESY = 360

-- The fonts to be replaced with "only_modify_default_font"
-- Default meaning the main font used for subtitles
-- avoiding to replace other fonts, like signs
local default_styles = {}
local matching_styles = {}
local ass_subtitle = false
local sub_data = nil

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
    blacklist = "sign;song;^ed;^op;title;^os;ending;opening"
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
local styles = {
    -- ASS Styles:
    ass = {
        "FontName=LTFinnegan Medium,Bold=0,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=1,Shadow=0.23,MarginV=20",
        --"FontName=LTFinnegan Medium,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H80000000,Outline=1.2,Shadow=0.5,MarginV=20",        
        -- "FontName=Trebuchet MS,Bold=0,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=2,Shadow=1",
        -- "FontName=LTFinnegan Medium,Bold=0,PrimaryColour=&H00F1F4F9,SecondaryColour=&H000000FF,OutlineColour=&H000A162D,BackColour=&HBE000000,Outline=1.25,Shadow=0.5",
        -- "FontName=Noto Serif,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=1.45,Shadow=0.73",
        "FontName=Gandhi Sans,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H80000000,Outline=1.2,Shadow=0.5,MarginV=20",        
        "FontName=Cronos Pro,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H00000000,BackColour=&H00000000,Outline=1.2,Shadow=0,MarginV=20",
        "FontName=Noto Serif,Bold=1,PrimaryColour=&H00FFFFFF,SecondaryColour=&H000000FF,OutlineColour=&H0012291F,BackColour=&HA012291F,Outline=1.45,Shadow=0.73,MarginV=20",
        -- I recommend leaving this here, so you can always cycle back to default
        ""
    },
    -- Other styles, such as SRT:
    non_ass = {
        {
            name = "LTFinnegan",
            font = "LTFinnegan Medium",
            bold = false,
            blur = 0,
            border_color = "#000000",
            border_size = 2.1,
            shadow_color = "#80000000",
            shadow_offset = 0.9
        },
        {
            name = "Noto Serif",
            font = "Noto Serif", 
            bold = true,
            blur = 0,
            border_color = "#000000",
            border_size = 3.6,
            shadow_color = "#80000000",
            shadow_offset = 1.1
        },
        {
            name = "Gandhi Style",
            font = "Gandhi Sans",
            bold = true,
            blur = 0,
            border_color = "#000000",
            border_size = 2.1,
            shadow_color = "#80000000",
            shadow_offset = 0.9
        },
    }
}

local script_dir = (debug.getinfo(1).source:match("@?(.*/)") or "./")

local script_opts_dir = script_dir:match("^(.-)[/\\]scripts[/\\]")

if script_opts_dir then
    script_opts_dir = utils.join_path(script_opts_dir, "script-opts")
else
    script_opts_dir = os.getenv("APPDATA") and utils.join_path(utils.join_path(os.getenv("APPDATA"), "mpv"), "script-opts") or
                          os.getenv("HOME") and utils.join_path(utils.join_path(utils.join_path(os.getenv("HOME"), ".config"), "mpv"), "script-opts") or
                          nil
end

local function get_config_path()
    return script_opts_dir
end

local function get_playres_scale()
    if sub_data == "" then
        return 1.0
    end

    local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)")) or DEFAULT_PLAYRESX
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)")) or DEFAULT_PLAYRESY

    local xRatio = playresx / DEFAULT_PLAYRESX
    local yRatio = playresy / DEFAULT_PLAYRESY
    return (xRatio >= yRatio) and xRatio or yRatio
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
local function get_default_font_and_styles()
    if not options.only_modify_default_font then return end
    if not sub_data or not sub_data:find("Styles%]") then return end

    local blacklist = options.blacklist
    local whitelist = { "default" }

    local function matches_blacklist(name)
        local lower = name:lower()
        -- Also match OP and ED capitalised
        if name:find("OP") or name:find("ED") then
            return true
        end

        for _, pat in ipairs(blacklist) do
            if lower:find(pat) then
                -- if options.debug then
                --     print("Skipped " .. name .. " for matching " .. pat)
                -- end
                return true
            end
        end
        return false
    end

    local function matches_whitelist(name)
        local lower = name:lower()
        for _, pat in ipairs(whitelist) do
            if lower == pat or lower:find(pat) then
                return true
            end
        end
        return false
    end

    local freq = {}
    local styleDetails = {}
    local orderKeys = {}
    local max_freq = 0
    local max_count = 0
    if options.debug then
        print("Fonts guessing from:")
    end
    for style_line in sub_data:gmatch("Style:([^\r\n]+)") do
        local params = {}
        for param in style_line:gmatch("([^,]+)") do
            table.insert(params, param:match("^%s*(.-)%s*$"))
        end
        if #params >= 7 then -- Need at least style name, font name, size, and 4 colors
            local style_name = params[1]
            if not matches_blacklist(style_name) then
                local font_name = params[2]
                local font_size = params[3]
                local key = font_name .. "|" .. font_size
                
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
                    name = style_name,
                    font = font_name,
                    size = font_size,
                    primary_color = params[4],
                    secondary_color = params[5],
                    outline_color = params[6],
                    back_color = params[7]
                }
                table.insert(styleDetails[key], style_info)
                
                if options.debug then
                    print(string.format("Style: %s - %s, %s, %s, %s, %s, %s", 
                        style_name, font_name, font_size, 
                        params[4], params[5], params[6], params[7]))
                end
            end
        end
    end

    if options.debug and next(freq) ~= nil then
        print("Font+Size frequencies:")
        for key, count in pairs(freq) do
            print("  " .. key .. ": " .. count)
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
                        if options.debug then
                            print("Chosen key was " .. key .. " because it matched the whitelist")
                        end
                        break
                    end
                end
            end
            if chosenKey then break end
        end
    end
    if not chosenKey then
        chosenKey = firstTiedKey
        if options.debug and chosenKey ~= nil then
            print("Chosen key was " .. chosenKey .. " because it was the most common.")
        end
    end

    -- For some reason, this runs faster than auto-selecting subtitles
    -- So sub_data can have old information
    -- If sub_data happens to have only blacklisted styles, it will error
    -- And only doing a return here will make it so it has enough time for sub_data
    -- to update to the new track
    -- I've spent so much time debugging this.
    if not chosenKey then
        print("No key was chosen!")
        return
    end

    default_styles = styleDetails[chosenKey]
    matching_styles = {}
    
    for _, style_info in ipairs(default_styles) do
        table.insert(matching_styles, style_info.name)
    end

    if options.debug then
        local style_list_str = (#matching_styles > 0 and table.concat(matching_styles, ", ")) or "none"
        print(string.format("Final decision: replacing font '%s' (size %s) used by %d styles: %s",
            default_styles[1] and default_styles[1].font or "nil",
            default_styles[1] and default_styles[1].size or "nil",
            #matching_styles,
            style_list_str))
    end
end

local function should_conserve()
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
local function prefix_style(scaled_style)
    local all_parts = {}
    local conserve = should_conserve()

    -- if conserve and options.conserve_style_color and options.debug then
    --     print("More than 1 color detected in the font! Conserving colors.")
    -- end

    for _, style_name in ipairs(matching_styles) do
        local parts = {}
        for param in scaled_style:gmatch("([^,]+)") do
            local key, value = param:match("^([^=]+)=(.+)$")
            if options.conserve_style_color and conserve and key:find("Colour$") then
                -- Don't include Colour if conserve style color is on
            else
                if key and value then
                    table.insert(parts, string.format("%s.%s=%s", style_name, key, value))
                else
                    table.insert(parts, param)
                end
            end 
        end
        table.insert(all_parts, table.concat(parts, ","))
    end
    
    return table.concat(all_parts, ",")
end

local function apply_ass_style()
    local style = styles.ass[options.ass_index]
    if not style then return end
    
    -- Scale the style based on the PlayRes
    local scale = get_playres_scale()
    local scaled_style = style

    if options.alternate_size and #default_styles > 0 then
        scale = scale * options.alternate_font_scale

        local first_style = default_styles[1]
        if first_style then

            local size = first_style.size
            if options.ass_font_size ~= 0 then
                size = options.ass_font_size * scale
            end

            if size then
                size = math.floor((options.alternate_font_scale * tonumber(size)) + 0.5)
                scaled_style = scaled_style .. string.format(",FontSize=%d", size)
            end

        end
    else

        -- Override also if not on alternate size
        if options.ass_font_size ~= 0 then
            size = tonumber(options.ass_font_size * scale)
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
        mp.osd_message("ASS Style: " .. options.ass_index, 2)
    else
        options.non_ass_index = (options.non_ass_index + direction - 1) % #styles.non_ass + 1
        apply_non_ass_style()
        mp.osd_message("SRT Style: " .. styles.non_ass[options.non_ass_index].name, 2)
    end
end

-- Change default font when the subtitles are changed
mp.observe_property("current-tracks/sub", "native", function(name, value)
    ass_subtitle = nil
    if is_ass_subtitle() then
        if options.debug then
            print("Detected change in subtitle tracks!")
        end
        sub_data = mp.get_property("sub-ass-extradata") or ""
        get_default_font_and_styles()
        apply_ass_style()
    else
        apply_non_ass_style()
    end
end
)

-- Save config on shutdown
mp.register_event("shutdown", function()
    save_config()
end)

-- Key Bindings
mp.add_key_binding("k", "cycle_styles_forward", function() cycle_styles(1) end)
mp.add_key_binding("K", "cycle_styles_backward", function() cycle_styles(-1) end)
mp.add_key_binding("Ctrl+k", "toggle_font_size", toggle_font_size)
