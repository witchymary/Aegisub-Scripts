export script_name = "Clip to Perspective"
export script_description = "Converts a 4-point vector clip into ambient plane data and perspective tags"
export script_author = "witchymary"
export script_version = "0.1.2"
export script_namespace = "witchy.cliptoperspective"

DependencyControl = require "l0.DependencyControl"
depctrl = DependencyControl{
    feed: "https://raw.githubusercontent.com/witchymary/Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
            feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
            feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Perspective", version: "1.2.1", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
            feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Math", version: "0.1.10", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
            feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
    }
}

LineCollection, ASS, perspective, amath = depctrl\requireModules!
{:Quad, :an_xshift, :an_yshift, :relevantTags, :usedTags, :tagsFromQuad} = perspective
{:Point, :Matrix} = amath

complained_about_layout_res = { }

logger = depctrl\getLogger!


cleanupTags = (data) ->
    data\removeTags { "clip_vect", "iclip_vect", "clip_rect", "iclip_rect" }

    defaults = data\getDefaultTags!.tags
    tags = data\getEffectiveTags(1, false, false, false).tags

    tagMatchesDefault = (tag_name) ->
        tag = tags[tag_name]
        return false unless tag
        default_tag = defaults[tag_name]
        return false unless default_tag
        tag\getTagParams! == default_tag\getTagParams!

    tags_to_remove = { }
    for tag_name in *{ "scale_x", "scale_y", "angle", "angle_x", "angle_y",
                      "align", "fontsize", "shear_x", "shear_y", "outline", 
                      "shadow" }
        if tagMatchesDefault tag_name
            table.insert tags_to_remove, tag_name

    data\removeTags tags_to_remove unless #tags_to_remove == 0

    collapseAxisTags = (bitag) ->
        tag_x = "#{bitag}_x"
        tag_y = "#{bitag}_y"
        tx, ty = tags[tag_x], tags[tag_y]
        return unless tx and ty
        vx, vy = tx\getTagParams!, ty\getTagParams!
        if vx == vy
            data\removeTags {tag_x, tag_y}
            if vx != 0
                tag = defaults[bitag]\copy!
                tag\setTagParams vx
                data\insertTags tag
        else
            data\removeTags tag_x if vx == 0
            data\removeTags tag_y if vy == 0

    collapseAxisTags "outline"
    collapseAxisTags "shadow"

    data\cleanTags 4


clipToPlane = (subs, sel) ->
    -- Validation taken from Perspective Motion
    -- https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/blob/acbc0046432b84cf9e5f4eb8e65d7d1aeaf95323/macros/arch.PerspectiveMotion.moon#L246
    return logger\fatal "You need to have a video loaded." if aegisub.frame_from_ms(0) == nil
    lines = LineCollection subs, sel, () -> true
    return if #lines.lines == 0
    
    -- Validation taken from Perspective Motion
    -- https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/blob/acbc0046432b84cf9e5f4eb8e65d7d1aeaf95323/macros/arch.PerspectiveMotion.moon#L39-L47
    _, video_h = aegisub.video_size!
    layout_scale = lines.meta.PlayResY / (lines.meta.LayoutResY or video_h)
    
    if layout_scale != 1 and not complained_about_layout_res[aegisub.file_name! or ""]
        complained_about_layout_res[aegisub.file_name! or ""] = true
        if lines.meta.LayoutResY
            logger\warn("Your file's LayoutResY (#{lines.meta.LayoutResY}) does not match its PlayResY (#{lines.meta.PlayResY}). Unless you know what you're doing you should probably resample to make them match.")
        else
            logger\warn("Your file's PlayResY (#{lines.meta.PlayResY}) does not match your video's height (#{video_h}). You may want to set a LayoutResY for your file.")

    lines\runCallback (lines, line, i) ->
        data = ASS\parse line
        tags = (data\getEffectiveTags 1, false, false, false).tags

        clip = tags.clip_vect or (tags.clip_rect and tags.clip_rect\getVect!)
        return logger\warn "Line #{i}: No vector clip found." unless clip and #clip.contours == 1

        points = [pt for cmd in *(clip.contours[1].commands) for pt in *(cmd\getPoints true)]
        return logger\warn("Line #{i}: Invalid 4-point clip.") unless #points == 4
        
        plane_data = table.concat(["#{pt.x};#{pt.y}" for pt in *points], "|")
        line.extra["_aegi_perspective_ambient_plane"] = plane_data
        
        -- Convert ASSFoundation's Point to arch.Math's Point
        arch_points = [Point(pt.x, pt.y) for pt in *points]
        quad = Quad arch_points

        -- Logic stolen from Perspective Motion
        -- https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/blob/acbc0046432b84cf9e5f4eb8e65d7d1aeaf95323/macros/arch.PerspectiveMotion.moon#L98-L126
        tagvals, w, h, warnings = perspective.prepareForPerspective ASS, data

        for warning in *warnings
            switch warning[1]
                when "zero_size"
                    logger\warn "Line #{i}: Text has zero size, perspective may be inaccurate."
                when "text_and_drawings"
                    logger\warn "Line #{i}: Line mixes text and drawings, perspective may be inaccurate."
                when "move"
                    logger\warn "Line #{i}: Line uses \\move, perspective tags will be applied but position tracking will be lost."
                when "multiple_tags"
                    logger\warn "Line #{i}: Tag \\#{warning[2]} appears multiple times, result may be incorrect."
                when "transform"
                    logger\warn "Line #{i}: Tag \\#{warning[2]} is used inside a \\t transform, result may be incorrect."

        oldscale = { k,tagvals[k].value for k in *{"scale_x", "scale_y"} }

        data\removeTags relevantTags
        data\insertTags [ tagvals[k] for k in *usedTags ]

        rect_at_quad = (sx, sy) ->
            result = Quad.rect 1, 1
            result -= Point(an_xshift[tagvals.align.value], an_yshift[tagvals.align.value])
            result *= Matrix.diag(sx, sy)
            result += Point(0.5, 0.5) -- center it in the UV
            Quad [ quad\uv_to_xy(p) for p in *result ]

        tagsFromQuad tagvals,
            rect_at_quad(1, 1),
            w, h, 2, layout_scale
        tagsFromQuad tagvals,
            rect_at_quad(
                oldscale.scale_x / tagvals.scale_x.value,
                oldscale.scale_y / tagvals.scale_y.value
            ),
            w, h, 2, layout_scale

        cleanupTags data
        data\commit!

    lines\replaceLines!

depctrl\registerMacro clipToPlane