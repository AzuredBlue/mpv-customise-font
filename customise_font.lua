local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local mpoptions = require('mp.options')

DEFAULT_PLAYRESX = 640
DEFAULT_PLAYRESY = 360

-- The fonts to be replaced with "only_modify_default_font"
-- Default meaning the main font used for subtitles
-- avoiding to replace other fonts, like signs
DEFAULT_STYLE_NAME = nil
DEFAULT_SIZE = nil
MATCHING_STYLES = {}
sub_data = nil

-- All of these options can be modified in the customise_font.conf
local options = {
    -- Show which fonts are being replaced
    debug = false,
    -- If it should set the subs to a higher position than default
    set_sub_pos = true,
    -- If it should only try to modify the font used for subtitles, instead of all
    only_modify_default_font = true,

    -- Font sizes for SRT. 44 seems to be the best for me.
    -- Scale is the value the default font size is multiplied by
    -- when alternate_size is on. I recommend values 0.9 - 1.1
    default_font_size = 44,
    alternate_font_scale = 0.95,

    -- Default style values
    -- These are modified whenever you change style, no need to manually modify them
    ass_index = 1,
    non_ass_index = 1,
    alternate_size = false,
}

mpoptions.read_options(options, "customise_font")

-- Add your own styles here 
local styles = {
    -- ASS Styles:
    ass = {
        "FontName=Netflix Sans,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&H00000000,Bold=-1,Outline=1.3,Shadow=0,Blur=7",
        "FontName=Gandhi Sans,Bold=1,OutlineColour=&H00402718,BackColour=&H00402718,Outline=1.2,Shadow=0.5",
        "FontName=Gandhi Sans,Bold=1,Outline=1.2,Shadow=0.5",
        -- "FontName=Trebuchet MS,Bold=1,Outline=1.8,Shadow=1",
        -- "FontName=Trebuchet MS,Bold=1,OutlineColour=&H00402718,BackColour=&H00402718,Outline=1.8,Shadow=1",
        -- I recommend leaving this here, so you can always cycle back to default
        ""
    },
    -- Other styles, such as SRT:
    non_ass = {
        {
            name = "Netflix Style",
            font = "Netflix Sans", 
            bold = true,
            blur = 3,
            border_color = "#000000",
            border_size = 2,
            shadow_color = "#000000",
            shadow_offset = 0
        },
        {
            name = "Gandhi Style Blue",
            font = "Gandhi Sans",
            bold = true,
            blur = 0,
            border_color = "#C0182740",
            border_size = 2.1,
            shadow_color = "#C0182740",
            shadow_offset = 0.9
        },
        {
            name = "Gandhi Style",
            font = "Gandhi Sans",
            bold = true,
            blur = 0,
            border_color = "#000000",
            border_size = 2.1,
            shadow_color = "#C0000000",
            shadow_offset = 0.9
        },
        -- {
        --     name = "CR",
        --     font = "Trebuchet MS",
        --     bold = true,
        --     blur = 0,
        --     border_color = "#182740",
        --     border_size = 3,
        --     shadow_color = "#182740",
        --     shadow_offset = 1.5
        -- }
    }
}

local function get_config_path()
    if package.config:sub(1,1) == '\\' then
        -- Windows path
        local appdata = os.getenv("APPDATA")
        if appdata then
            return utils.join_path(utils.join_path(appdata, "mpv"), "script-opts")
        else
            local home = os.getenv("USERPROFILE")
            if home then
                return utils.join_path(
                    utils.join_path(
                        utils.join_path(
                            utils.join_path(home, "AppData"),
                        "Roaming"),
                    "mpv"),
                "script-opts")
            end
        end
    else
        -- Unix path
        local home = os.getenv("HOME")
        if home then
            return utils.join_path(utils.join_path(home, ".config"), "mpv")
        end
    end
    return nil
end

local function ensure_config_directory()
    local config_path = get_config_path()
    if not config_path then return false end
    
    local success, err = utils.file_info(config_path)
    if not success then
        msg.verbose("Creating config directory:", config_path)
        return utils.subprocess({
            args = {"mkdir", "-p", config_path},
            cancellable = false
        })
    end
    return true
end

local function get_playres_scale()
    if sub_data == "" then
        return 1.0
    end

    local playresx = tonumber(sub_data:match("PlayResX:%s*(%d+)")) or DEFAULT_PLAYRESX
    local playresy = tonumber(sub_data:match("PlayResY:%s*(%d+)")) or DEFAULT_PLAYRESY

    local xRatio = playresx / DEFAULT_PLAYRESX
    local yRatio = playresy / DEFAULT_PLAYRESY
    if xRatio >= yRatio then
        return xRatio
    else
        return yRatio
    end
end

local function scale_ass_style(style, scale)
    if scale == 1 then return style end
    
    return style:gsub("([%w]+)=([%d%.]+)", function(key, val)
        local scaled_properties = {
            Outline = true, Shadow = true
        }
        
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
    
    local blacklist = { "sign", "song", "^ed", "^op", "title", "^os", "ending", "opening" }
    local whitelist = { "default" }

    local function matches_blacklist(name)
        local lower = name:lower()
        for _, pat in ipairs(blacklist) do
            if lower:find(pat) then
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
    local styleNames = {}
    local orderKeys = {}
    local max_count = 0

    for style_line in sub_data:gmatch("Style:([^\r\n]+)") do
        local params = {}
        for param in style_line:gmatch("([^,]+)") do
            table.insert(params, param:match("^%s*(.-)%s*$"))
        end
        if #params >= 3 then
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
                if freq[key] > max_count then
                    max_count = freq[key]
                end

                styleNames[key] = styleNames[key] or {}
                table.insert(styleNames[key], style_name)
            end
        end
    end

    if options.debug then
        print("Font+Size frequencies:")
        for key, count in pairs(freq) do
            print("  " .. key .. ": " .. count)
        end
    end

    -- Choose the key to replace
    local chosenKey, firstTiedKey = nil, nil
    for _, key in ipairs(orderKeys) do
        if freq[key] == max_count then
            if not firstTiedKey then
                firstTiedKey = key
            end
            for _, name in ipairs(styleNames[key]) do
                if matches_whitelist(name) then
                    chosenKey = key
                    if options.debug then
                        print("Chosen key was " .. key .. " because it matched the whitelist")
                    end
                    break
                end
            end
            if chosenKey then break end
        end
    end
    if not chosenKey then
        chosenKey = firstTiedKey
        if options.debug then
            print("Chosen key was " .. chosenKey .. " because it was the first tied key in the file")
        end
    end

    local popular_font, popular_size = chosenKey:match("([^|]+)|(.+)")
    DEFAULT_STYLE_NAME = popular_font
    DEFAULT_SIZE = popular_size
    MATCHING_STYLES = styleNames[chosenKey]

    if options.debug then
        local style_list_str = (#MATCHING_STYLES > 0 and table.concat(MATCHING_STYLES, ", ")) or "none"
        print(string.format("Final decision: replacing font '%s' (size %s) used by %d styles: %s",
            DEFAULT_STYLE_NAME or "nil",
            DEFAULT_SIZE or "nil",
            #MATCHING_STYLES,
            style_list_str))
    end
end


-- Prefix the style with the style names, so it only changes them.
local function prefix_style_with_styles(style_names, scaled_style)
    local all_parts = {}
    
    for _, style_name in ipairs(style_names) do
        local parts = {}
        for param in scaled_style:gmatch("([^,]+)") do
            local key, value = param:match("^([^=]+)=(.+)$")
            if key and value then
                table.insert(parts, string.format("%s.%s=%s", style_name, key, value))
            else
                table.insert(parts, param)
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

    if options.alternate_size then
        -- Scale it more up/down depending on the alternate font scale
        scale = scale * options.alternate_font_scale
        scaled_style = scaled_style .. string.format(",FontSize=%d", math.floor((options.alternate_font_scale*DEFAULT_SIZE) + 0.5))
    end

    scaled_style = scale_ass_style(scaled_style, scale)

    if #MATCHING_STYLES > 0 then
        scaled_style = prefix_style_with_styles(MATCHING_STYLES, scaled_style)
    end

    -- Fix LayoutRes
    -- Instead use sub-ass-use-video-data=aspect-ratio 
    
    mp.set_property("sub-ass-style-overrides", scaled_style)
    
    if options.set_sub_pos then
        mp.set_property("sub-pos", 98)
    end
end

local function apply_non_ass_style()
    local style = styles.non_ass[options.non_ass_index]
    if not style then return end

    -- Scale font size based on alternate_size
    font_size = options.default_font_size
    if options.alternate_size then
        font_size = math.floor(options.alternate_font_scale * options.default_font_size + 0.5)
    end

    mp.set_property_native("sub-font", style.font)
    mp.set_property_native("sub-bold", style.bold)
    mp.set_property_native("sub-font-size", font_size)
    mp.set_property_native("sub-blur", style.blur)
    mp.set_property_native("sub-border-color", style.border_color)
    mp.set_property_native("sub-border-size", style.border_size)
    mp.set_property_native("sub-shadow-color", style.shadow_color)
    mp.set_property_native("sub-shadow-offset", style.shadow_offset)

    if options.set_sub_pos then
        mp.set_property("sub-pos", 98)
    end
    
end

local function save_config()
    if not ensure_config_directory() then return end
    
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

    -- Write updated content
    file = io.open(config_path, "w")
    if file then
        file:write(table.concat(lines, "\n"))
        file:close()
    end
end

local function is_ass_subtitle()
    local track = mp.get_property_native("current-tracks/sub")
    return track and track.codec == "ass"
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
    save_config()
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
    save_config()
end

-- Change default font when the subtitles are changed
mp.observe_property("current-tracks/sub", "native", function(name, value)
    sub_data = mp.get_property("sub-ass-extradata") or ""
    if is_ass_subtitle() then
        if options.debug then
            print("Detected change in subtitle tracks!")
        end
        get_default_font_and_styles()
        apply_ass_style()
    else
        apply_non_ass_style()
    end
end
)

-- Key Bindings
mp.add_key_binding("k", "cycle_styles_forward", function() cycle_styles(1) end)
mp.add_key_binding("K", "cycle_styles_backward", function() cycle_styles(-1) end)
mp.add_key_binding("Ctrl+k", "toggle_font_size", toggle_font_size)
