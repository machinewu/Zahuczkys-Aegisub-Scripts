script_name = "AutoClip"
script_description = "Add clips to subtitles 𝓪𝓾𝓽𝓸𝓶𝓪𝓰𝓲𝓬𝓪𝓵𝓵𝔂"
script_version = "2.0.2"
script_author = "Zahuczky, Akatsumekusa"
script_namespace = "zah.autoclip"
-- Even when this file doesn't change, version numbering is kept consistent with the python script. 

local hasDepCtrl, DepCtrl = pcall(require, "l0.DependencyControl")
if hasDepCtrl then
    DepCtrl = DepCtrl({
        name = script_name,
        description = script_description,
        version = script_version,
        author = script_author,
        moduleName = script_namespace,
        url = "https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts",
        feed = "https://raw.githubusercontent.com/Zahuczky/Zahuczkys-Aegisub-Scripts/main/DependencyControl.json",
        {
            {
                "ILL.ILL",
                version = "1.1.0",
                url = "https://github.com/TypesettingTools/ILL-Aegisub-Scripts",
                feed = "https://raw.githubusercontent.com/TypesettingTools/ILL-Aegisub-Scripts/main/DependencyControl.json"
            },
            {
                "aka.config",
                version = "1.0.8",
                url = "https://github.com/Akatmks/Akatsumekusa-Aegisub-Scripts",
                feed = "https://raw.githubusercontent.com/Akatmks/Akatsumekusa-Aegisub-Scripts/master/DependencyControl.json"
            },
            {
                "aka.outcome",
                version = "1.0.7",
                url = "https://github.com/Akatmks/Akatsumekusa-Aegisub-Scripts",
                feed = "https://raw.githubusercontent.com/Akatmks/Akatsumekusa-Aegisub-Scripts/master/DependencyControl.json"
            }
        }
    })
    DepCtrl:requireModules()
end
local ILL = require("ILL.ILL")
local Aegi, Ass, Line = ILL.Aegi, ILL.Ass, ILL.Line

local aconfig = require("aka.config").make_editor({
    display_name = "AutoClip",
    presets = {
        ["default"] = { ["python"] = "python3", ["disable_mismatch"] = false }
    },
    default = "default"
})
local outcome = require("aka.outcome")
local ok, err = outcome.ok, outcome.err
local validation_func = function(config)
    if type(config) ~= "table" then
        return err("Missing root table.")
    elseif type(config["python"]) ~= "string" then
        return err("Key \"python\" is missing.")
    elseif type(config["disable_mismatch"]) ~= "boolean" then
        return err("Key \"disable_mismatch\" is missing.")
    end
    return ok(config)
end

local config
local function autoclip(sub, sel, act)
    if not config then
        config = aconfig:read_and_validate_config_if_empty_then_default_or_else_edit_and_save("zah.autoclip", validation_func)
            :ifErr(aegisub.cancel)
            :unwrap()
    end

    local ass = Ass(sub, sel, act)

    local project_props = aegisub.project_properties()
    if not project_props.video_file then
        aegisub.debug.out("[zah.autoclip] AutoClip requires a video to be loaded for clipping.\n")
        aegisub.cancel()
    end
    local video_file = project_props.video_file
    local output_file = aegisub.decode_path("?temp/zah.autoclip" .. string.sub(tostring(math.random()), 2))

    -- Grab frame and clip information and check frame continuity across subtitle lines
    Aegi.progressTitle("Gathering frame information")
    local active = project_props.video_position
    local frames = {}
    local first
    local last
    local active_clip
    local clip
    for line, s, i, n in ass:iterSel() do
        ass:progressLine(s, i, n)

        line.start_frame = aegisub.frame_from_ms(line.start_time)
        line.end_frame = aegisub.frame_from_ms(line.end_time)

        if not first then
            first = line.start_frame
            last = line.end_frame
        else
            first = first <= line.start_frame and first or line.start_frame
            last = last >= line.end_frame and last or line.end_frame
        end

        for j = line.start_frame, line.end_frame - 1 do
            if not frames[j] then
                frames[j] = 1
            else
                frames[j] = frames[j] + 1
        end end

        Line.process(ass, line)
        if type(line.data["clip"]) == "table" then
            if line.start_frame <= active and active < line.end_frame then
                if active_clip == nil then
                    active_clip = line.data["clip"]
                elseif type(active_clip) == "table" then
                    if not (line.data["clip"][1] == active_clip[1] and
                            line.data["clip"][2] == active_clip[2] and
                            line.data["clip"][3] == active_clip[3] and
                            line.data["clip"][4] == active_clip[4]) then
                        active_clip = false
            end end end
                
            if clip == nil then
                clip = line.data["clip"]
            elseif type(clip) == "table" then
                if not (line.data["clip"][1] == clip[1] and
                        line.data["clip"][2] == clip[2] and
                        line.data["clip"][3] == clip[3] and
                        line.data["clip"][4] == clip[4]) then
                    clip = false
    end end end end

    -- Check frame continuity
    local head
    for i = first, last - 1 do
        if not frames[i] then
            for j = i, last - 1 do
                if frames[j] then
                    aegisub.debug.out("[zah.autoclip] Selected lines must be time continuous.\n")
                    aegisub.debug.out("[zah.autoclip] The earliest frame in the selected line is frame " .. tostring(first) .. ", and the latest frame is frame " .. tostring(last - 1) .. ".\n")
                    if i ~= j - 1 then
                        aegisub.debug.out("[zah.autoclip] There is at least one gap from frame " .. tostring(i) .. " to frame " .. tostring(j - 1) .. " that no lines in the selection covers.\n")
                    else
                        aegisub.debug.out("[zah.autoclip] There is at least one gap at frame " .. tostring(i) .. " that no lines in the selection covers.\n")
                    end
                    aegisub.cancel()
            end end
        elseif not config["disable_mismatch"] then
            if head == nil then
                head = frames[i]
            elseif head ~= false and head ~= frames[i] then
                aegisub.debug.out("[zah.autoclip] Number of layers mismatches.\n")
                aegisub.debug.out("[zah.autoclip] There are " .. tostring(head) .. " layers on frame " .. tostring(i - 1) .. ", but there are " .. tostring(frames[i]) .. " layers on frame " .. tostring(i) .. ".\n")
                aegisub.debug.out("[zah.autoclip] If this is intentional and you want to silence this warning, you can disable it in „AutoClip > Configure AutoClip“.\n")
                aegisub.debug.out("[zah.autoclip] Continuing.\n")
                head = false
    end end end

    -- Make sure active is inside [first:last]
    if not (first <= active and active < last) then
        aegisub.debug.out("[zah.autoclip] Video seek head outside the range of selected lines.\n")
        aegisub.debug.out("[zah.autoclip] The selected lines start at frame " .. tostring(first) .. " and end at frame " .. tostring(last - 1) .. " but video seek head is at frame " .. tostring(active) .. ".\n")
        aegisub.debug.out("[zah.autoclip] AutoClip uses video seek head as the reference frame and also by default takes the clipping area from lines containing video seek head.\n")
        aegisub.cancel()
    end

    if active_clip == false then
        aegisub.debug.out("[zah.autoclip] Multiple different rect clips found on lines containing the frame at video seek head.\n")
        aegisub.debug.out("[zah.autoclip] AutoClip requires a rect clip to be set for the area it will be active.\n")
        aegisub.debug.out("[zah.autoclip] AutoClip by default takes this clip from lines containing the frame at video seek head. AutoClip expects one unique rect clip on the lines.\n")
        aegisub.cancel()
    end
    -- Check active_clip and set to clip
    if active_clip then
        clip = active_clip
    else
        if clip == nil then
            aegisub.debug.out("[zah.autoclip] No rect clips found in selected lines.\n")
            aegisub.debug.out("[zah.autoclip] AutoClip requires a rect clip to be set for the area it will be active.\n")
            aegisub.debug.out("[zah.autoclip] AutoClip first checks if such clip exists on lines containing the frame at video seek head, otherwise it fallsbacks and checks for clips in every lines in the selection.\n")
            aegisub.cancel()
        elseif clip == false then
            aegisub.debug.out("[zah.autoclip] No rect clip found in lines containing the frame at video seek head, and there are multiple different rect clips found on other selected line.\n")
            aegisub.debug.out("[zah.autoclip] AutoClip requires a rect clip to be set for the area it will be active.\n")
            aegisub.debug.out("[zah.autoclip] AutoClip first checks if such clip exists on lines containing the frame at video seek head, otherwise it fallsbacks and checks for clips in every lines in the selection.\n")
            aegisub.cancel()
        end
    end

    -- Run commands
    Aegi.progressTitle("Waiting for Python to complete")
    local command = " -m ass_autoclip --input '" .. video_file .. "'" ..
                                    " --output '" .. output_file .. "'" ..
                      string.format(" --clip '%f %f %f %f'", clip[1], clip[2], clip[3], clip[4]) ..
                                    " --first " .. first ..
                                    " --last " .. last ..
                                    " --active " .. active
    if jit.os == "Windows" then
        command = "powershell -Command \"& '" .. config["python"] .. "'" .. command .. "\""
    else
        command = "'" .. config["python"] .. "'" .. command
    end
    local status, terminate, code = os.execute(command)
    if not status then
        if terminate == "exit" then
            aegisub.debug.out("[zah.autoclip] Python exists with code " .. tostring(code) .. ".\n")
        else
            aegisub.debug.out("[zah.autoclip] Python terminated with signal " .. tostring(code) .. ".\n")
        end
        aegisub.debug.out("[zah.autoclip] " .. command .. "\n")
        aegisub.debug.out("[zah.autoclip] Attempting to continue.\n")
    end

    Aegi.progressTitle("Seting clips")
    -- Open output file
    local f, error = io.open(output_file, "r")
    if not f then
        aegisub.debug.out("[zah.autoclip] Failed to open output file:\n")
        aegisub.debug.out("[zah.autoclip] " .. error .. "\n")
        aegisub.cancel()
    end

    -- Read the output file into frames table
    frames = {}
    head = first
    local read
    while true do
        read = f:read("*l")
        if not read then break end

        if read == "empty" then
            frames[head] = nil
        else
            frames[head] = read
        end
        head = head + 1
    end
    if head ~= last then
        aegisub.debug.out("[zah.autoclip] Output file contains less frames than expected.\n")
        aegisub.debug.out("[zah.autoclip] AutoClip will continue but please manually confirm the result after run.\n")
    end

    -- Apply the frames table to subtitle
    for line, s, i, n in ass:iterSel() do
        ass:progressLine(s, i, n)

        ass:removeLine(line, s)
        -- Internal ILL value, may break
        line.isShape = false
        Line.process(ass, line)
        line.text.tagsBlocks[1]:remove("clip")

        Line.callBackFBF(ass, line, function(line_, i_, end_frame)
            if frames[aegisub.frame_from_ms(line_.start_time)] then
                line_.text.tagsBlocks[1]:insert(frames[aegisub.frame_from_ms(line_.start_time)])
            end
            ass:insertLine(line_, s) end)
    end

    return ass:getNewSelection()
end

local function edit_config()
    if not config then
        config = aconfig:read_and_validate_config_if_empty_then_default_or_else_edit_and_save("zah.autoclip", validation_func)
            :ifErr(aegisub.cancel)
            :unwrap()
    end

    local dialog = { { class = "label",                     x = 0, y = 0, width = 30,
                                                            label = "Enter path to your Python executable:" },
                     { class = "edit", name = "python",     x = 0, y = 1, width = 30,
                                                            text = config["python"] },
                     { class = "label",                     x = 0, y = 2, width = 30,
                                                            label = "Do you want to disable warning when the number of layers mismatches?" },
                     { class = "checkbox", name = "disable_mismatch", x = 0, y = 3, width = 30,
                                                            label = "Disable", value = config["disable_mismatch"] } }
    local buttons = { "&Set", "Close" }
    local button_ids = { ok = "&Set", yes = "&Set", save = "&Set", apply = "&Set", close = "Close", no = "Close", cancel = "Close" }

    local button, result_table = aegisub.dialog.display(dialog, buttons, button_ids)

    if button == false or button == "Close" then aegisub.cancel()
    elseif button == "&Set" then
        config = result_table
        aconfig.write_config("zah.autoclip", config)
            :ifErr(function()
                aegisub.debug.out("[aka.config] Failed to write config to file.\n")
                aegisub.debug.out("[aka.config] " .. error .. "\n")
                aegisub.cancel() end)
end end

if hasDepCtrl then
    DepCtrl:registerMacros({
        { "AutoClip", script_description, autoclip },
        { "Configure AutoClip", "Configure AutoClip", edit_config }
    })
else
    aegisub.register_macro("AutoClip/AutoClip", script_description, autoclip)
    aegisub.register_macro("AutoClip/Configure AutoClip", "Configure AutoClip", edit_config)
end
