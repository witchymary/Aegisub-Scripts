export script_name = "All-Rounder"
export script_description = "Rounds tag values and drawing coordinates"
export script_author = "witchymary"
export script_version = "0.0.1"
export script_namespace = "witchy.allrounder"

DependencyControl = require "l0.DependencyControl"
depctrl = DependencyControl{
    feed: "https://raw.githubusercontent.com/witchymary/Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
            feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
            feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    }
}
LineCollection, ASS = depctrl\requireModules!
logger = depctrl\getLogger!


round_to = (value, decimals = 0) ->
    mult = 10 ^ decimals
    if value >= 0
        math.floor(value * mult + 0.5) / mult
    else
        math.ceil(value * mult - 0.5) / mult


snap_positive = (step, value, shortest, safe) ->
    grid = round_to(value / step) * step
    return grid unless shortest

    half = step / 2
    source = if safe then value else grid

    for decimals = 0, 10
        candidate = round_to source, decimals
        return candidate if math.abs(candidate - grid) < half
    grid


calculate_precision = (precision, value, shortest = true, safe = false) ->
    precision = tonumber precision
    logger\fatal "Invalid precision: must be a positive number." unless precision and precision > 0

    value = tonumber value
    logger\fatal "Invalid value: must be a numeric value." unless value

    if value < 0
        0 - snap_positive precision, -value, shortest
    else
        snap_positive precision, value, shortest, safe


-- Shorthand for simplicity
-- libass has 1/8 px precision for coordinate values
round = (value, step = 0.125) -> calculate_precision step, value


round_draw_commands = (drawing) ->
    for cnt in *drawing.contours
        for cmd in *cnt.commands
            params = { cmd\getTagParams! }
            cmd\set unpack [ round p for p in *params ]


round_tag_section = (section) ->
    for tag in *section\getTags { "position", "origin" }
        x, y = tag\getTagParams!
        tag\set round(x), round(y)

    for tag in *section\getTags { "move" }
        p = { tag\getTagParams! }
        tag\set round(p[1]), round(p[2]), round(p[3]), round(p[4]), p[5] or 0, p[6] or 0

    -- Rectangular clips have whole pixel precision
    for tag in *section\getTags { "clip_rect", "iclip_rect" }
        x1, y1, x2, y2 = tag\getTagParams!
        tag\set round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)

    -- Clip tags inherit DrawingBase, which disables set
    for tag in *section\getTags { "clip_vect", "iclip_vect" }
        round_draw_commands tag

    nil


main = (sub, sel) ->
    lines = LineCollection sub, sel
    return if #lines.lines == 0
    lines\runCallback (lines, line, i) ->
        data = ASS\parse line

        data\callback ((section) ->
            round_tag_section section

            -- Process any transforms embedded in this section
            -- Each transform's .tags field is its own inner ASS.Section.Tag
            section\callback ((transform) ->
                round_tag_section transform.tags
                nil
            ), "transform"

            nil
        ), ASS.Section.Tag

        data\callback ((section) ->
            round_draw_commands section
            nil
        ), ASS.Section.Drawing

        aegisub.progress.set (i/#lines.lines)*100
        aegisub.progress.task "Processing lines #{i}/#{#lines.lines}"

        data\commit!
    lines\replaceLines!

depctrl\registerMacro main