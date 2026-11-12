import qs.modules.common
import QtQuick

StyledText {
    id: root

    // The vendored components pass the icon's Material Symbol name as `text`.
    // Asura does not carry the Material Symbols font, so that name would
    // render as literal text (or nothing). Keep the original name in
    // `_rawName` (updated only when `text` is itself a Material Symbol name,
    // so a rewritten codepoint never clobbers it) and map it onto a Font
    // Awesome 4.7 codepoint via Appearance.iconMap. An unmapped name leaves
    // `_mappedGlyph` empty and renders nothing, as before.
    property string _rawName: ""
    property string _mappedGlyph: {
        var m = Appearance?.iconMap
        if (!m || _rawName === "") return ""
        var g = m[_rawName]
        return (g === undefined) ? "" : g
    }

    onTextChanged: {
        var m = Appearance?.iconMap
        if (m && m[text] !== undefined) {
            _rawName = text
        }
        if (_mappedGlyph !== "" && text !== _mappedGlyph) {
            text = _mappedGlyph
        }
    }

    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    property real truncatedFill: fill.toFixed(1) // Reduce memory consumption spikes from constant font remapping
    renderType: Text.NativeRendering
    font {
        hintingPreference: Font.PreferNoHinting
        family: _mappedGlyph !== "" ? "Font Awesome 4.7" : (Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded")
        pixelSize: iconSize
        weight: Font.Normal + (Font.DemiBold - Font.Normal) * truncatedFill
        variableAxes: {
            "FILL": truncatedFill,
            // "wght": font.weight,
            // "GRAD": 0,
            "opsz": iconSize,
        }
    }

    Behavior on fill { // Leaky leaky, no good
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}
