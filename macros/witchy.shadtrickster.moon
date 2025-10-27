export script_name = "ShadTrickster"
export script_description = "*Shadtricks Your Lines*"
export script_version = "0.1.1"
export script_author = "witchymary"
export script_namespace = "witchy.shadtrickster"

DependencyControl = require "l0.DependencyControl"
depctrl = DependencyControl{
  {
    {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version: "0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
  }
}
LineCollection, ASS = depctrl\requireModules!
logger = depctrl\getLogger!


main = (sub, sel) ->
    lines = LineCollection sub, sel
    return if #lines.lines == 0
    lines\runCallback (lines, line, i) ->
        data = ASS\parse line
        
        local previous_alpha -- also being used to identify the first tag section
        data\callback ((section) ->

            tags = (section\getEffectiveTags false, false, false).tags

            tags_to_insert = { }            
            
            alpha_last = false
            for i = #section.tags, 1, -1
                tag = section.tags[i]\toString!
                if tag\find "alpha"
                    alpha_last = true
                    break
                elseif tag\find "1a"
                    break
            
            if not previous_alpha or tags.color1
                color_params = { (tags.color1 or (data\getDefaultTags!).tags.color1)\getTagParams! }
                table.insert tags_to_insert, ASS\createTag("color4", unpack color_params)
        
            alpha = if alpha_last
                tags.alpha\getTagParams!
            elseif not previous_alpha or tags.alpha1
                (tags.alpha1 or (data\getDefaultTags!).tags.alpha1)\getTagParams!
            else
                previous_alpha
            
            if not previous_alpha
                table.insert tags_to_insert, ASS\createTag("alpha", 0xFF)
                table.insert tags_to_insert, ASS\createTag("alpha4", alpha)
                table.insert tags_to_insert, ASS\createTag("shadow", 0.01)
                table.insert tags_to_insert, ASS\createTag("k_bord", 0)
            elseif previous_alpha ~= alpha
                table.insert tags_to_insert, ASS\createTag("alpha4", alpha)

            previous_alpha = alpha

            section\removeTags {"alpha", "alpha1", "alpha3", "alpha4", "color1", "color3", 
                                "color4", "k_bord", "shadow", "shadow_x", "shadow_y"}
            
            section\insertTags tags_to_insert

            nil

        ), ASS.Section.Tag
        
        data\cleanTags nil, nil, nil
        data\commit!
    lines\replaceLines!

depctrl\registerMacro main