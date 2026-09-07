// Colour arithmetic, shared by every surface in this shell.
//
// Not a plugin. This directory carries no manifest.json, so the patched
// PluginRegistry walks past it (verified on the device, docs/refactor.md E1)
// and it exists only to be imported:
//
//     import "../moarchy.common/Theme.js" as Theme
//
// Six plugins carried byte-identical copies of these four functions before
// this file, ~120 lines of one text, under a comment in each that said they
// were kept separate "because plugins are separate directories and a relative
// path across them is the kind of thing that breaks silently". The premise was
// testable and false: moarchy.settings already imports Pages.js by relative
// path, and E1 showed the same import reaches a sibling directory.
//
// `.pragma library` because these are pure: no QML scope, no ids, one shared
// instance rather than a copy per importing component. What that costs is
// access to the component -- which is why every input arrives as an argument
// and nothing here reads a property.
.pragma library

// WCAG 2.1 relative luminance and contrast, and a linear composite, so the
// secondary text colour can be computed per theme instead of guessed.
//
// A constant alpha cannot do this job. Measured across all 22 themes'
// colors.toml, foreground at 0.7 over a lifted card falls below AA in six of
// them and reaches 3.14:1 on rose-pine; the alpha that clears AA everywhere
// is 0.9, and at 0.9 a subtitle is within ten percent of its label and the
// hierarchy the alpha existed to create is gone. Calibrating on Catppuccin --
// which passes at 5.44 -- is exactly how a single number looks correct and
// is not. (Method and measurements from the settings work, 4ff1e7f.)
//
// `container` is painted with alpha over the surface, so the background the
// text actually lands on is the blend of the two: measuring against the
// surface alone overstates the contrast by the width of that lift.
function luminance(c) {
    function chan(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
}

function contrastRatio(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

function mix(bg, fg, a) {
    return Qt.rgba(bg.r + a * (fg.r - bg.r),
                   bg.g + a * (fg.g - bg.g),
                   bg.b + a * (fg.b - bg.b), 1)
}

// Start quiet and walk toward the foreground only until the pair clears the
// ratio, so every theme ends up as quiet as it can afford.
function readableOn(bg, fg, from, minRatio) {
    for (var a = from; a < 1.0; a += 0.01) {
        var c = mix(bg, fg, a)
        if (contrastRatio(c, bg) >= minRatio) return c
    }
    return fg
}
