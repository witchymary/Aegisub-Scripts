export script_name = "ShadTrickster"
export script_description = "*Shadtricks Your Lines*"
export script_version = "0.2.1"
export script_author = "witchymary"
export script_namespace = "witchy.shadtrickster"

DependencyControl = require "l0.DependencyControl"
depctrl = DependencyControl{
    feed: "https://raw.githubusercontent.com/witchymary/Aegisub-Scripts/main/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version: "0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
  }
}
LineCollection, ASS = depctrl\requireModules!


process_tag_section = (default_tags, section, previous_alpha) ->
    tags = (section\getEffectiveTags false, false, false).tags

    tags_to_insert = { }

    alpha = if not previous_alpha or tags.alpha1 or previous_alpha == -1
        (tags.alpha1 or default_tags.alpha1)\getTagParams!
    else
        previous_alpha
    
    -- Hacky solution to determine whether \alpha or \1a are the last value in the tag block - the canonical one
    -- The transform is being skipped since it otherwise can mess up with the logic
    for i = #section.tags, 1, -1
        tag_str = section.tags[i]\toString!
        continue if tag_str\find "^\\t"
        if tag_str\find "alpha"
            alpha = tags.alpha\getTagParams!
            break
        elseif tag_str\find "1a"
            break

    if not previous_alpha or tags.color1
        color_params = { (tags.color1 or default_tags.color1)\getTagParams! }
        table.insert tags_to_insert, ASS\createTag("color4", unpack color_params)

    if not previous_alpha
        table.insert tags_to_insert, ASS\createTag("alpha", 0xFF)
        table.insert tags_to_insert, ASS\createTag("alpha4", alpha)
        table.insert tags_to_insert, ASS\createTag("shadow_x", 0.001)
        table.insert tags_to_insert, ASS\createTag("k_bord", 0)
    elseif previous_alpha ~= alpha
        table.insert tags_to_insert, ASS\createTag("alpha4", alpha)

    section\removeTags {"alpha", "alpha1", "alpha3", "alpha4", "color1", "color3",
                        "color4", "k_bord", "shadow", "shadow_x", "shadow_y"}

    section\insertTags tags_to_insert

    alpha


main = (sub, sel) ->
    lines = LineCollection sub, sel
    return if #lines.lines == 0
    lines\runCallback (lines, line) ->
        data = ASS\parse line

        local previous_alpha -- also being used to identify the first tag section
        default_tags = (data\getDefaultTags!).tags

        data\callback ((section) ->
            previous_alpha = process_tag_section default_tags, section, previous_alpha

            -- Process any transforms embedded in this section
            -- Each transform's .tags field is its own inner ASS.Section.Tag
            -- If the transform has alpha, ensure previous_alpha fails a condition in process_tag_section
            section\callback ((tag) ->
                has_alpha = #tag.tags\getTags({"alpha", "1a"}) > 0
                process_tag_section default_tags, tag.tags, previous_alpha
                previous_alpha = -1 if has_alpha
            ), "transform"

            nil

        ), ASS.Section.Tag

        data\cleanTags nil, nil, nil
        data\commit!
    lines\replaceLines!

depctrl\registerMacro main