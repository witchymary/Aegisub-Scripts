export script_name = "All-Rounder"
export script_description = "Round tag and drawing coordinates to the nearest integer or up to two decimal places"
export script_author = "witchymary"
export script_version = "0.1.1"
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
    value = tonumber value
    logger\fatal "Invalid value: must be a numeric value." unless value

    mult = 10 ^ decimals
    scaled = value * mult
    rounded = if scaled >= 0 then math.floor(scaled + 0.5) else math.ceil(scaled - 0.5)
    rounded / mult


round_draw_commands = (drawing, decimals = 0) ->
    for cnt in *drawing.contours
        for cmd in *cnt.commands
            params = { cmd\getTagParams! }
            continue if #params == 0
            cmd\set unpack [ round_to p, decimals for p in *params ]
    
    nil


round_tag_section = (section, decimals = 0) ->
    for tag in *section\getTags { "position", "origin" }
        x, y = tag\getTagParams!
        tag\set round_to(x, decimals), round_to(y, decimals)

    for tag in *section\getTags { "move" }
        p = { tag\getTagParams! }
        tag\set round_to(p[1], decimals), round_to(p[2], decimals), round_to(p[3], decimals), round_to(p[4], decimals), p[5] or 0, p[6] or 0

    -- libass truncates rectangular clips to integers
    for tag in *section\getTags { "clip_rect", "iclip_rect" }
        x1, y1, x2, y2 = tag\getTagParams!
        tag\set (math.modf x1), (math.modf y1), (math.modf x2), (math.modf y2)

    -- Vectorial clip tags inherit DrawingBase, so reuse same function
    for tag in *section\getTags { "clip_vect", "iclip_vect" }
        round_draw_commands tag, decimals

    nil


round_macro = (decimals) -> (sub, sel) ->
    lines = LineCollection sub, sel
    return if #lines.lines == 0
    lines\runCallback (lines, line, i) ->
        aegisub.cancel! if aegisub.progress.is_cancelled!

        data = ASS\parse line

        data\callback ((section) ->
            round_tag_section section, decimals

            -- Process any transforms embedded in this section
            -- Each transform's .tags field is its own inner ASS.Section.Tag
            -- Only relevant for rect clips, unless other tags are added
            section\callback ((transform) ->
                round_tag_section transform.tags, decimals
                nil
            ), "transform"

            nil
        ), ASS.Section.Tag

        data\callback ((section) ->
            round_draw_commands section, decimals

            nil
        ), ASS.Section.Drawing

        aegisub.progress.set (i/#lines.lines)*100
        aegisub.progress.task "Processing lines #{i}/#{#lines.lines}"

        data\commit!
    lines\replaceLines!

depctrl\registerMacros {
    {"Round",               "Round coordinates and drawings to nearest integer",  round_macro 0}
    {"Round to 1 Decimal",  "Round coordinates and drawings to 1 decimal place",  round_macro 1}
    {"Round to 2 Decimals", "Round coordinates and drawings to 2 decimal places", round_macro 2}
}