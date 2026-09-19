import QtQuick
import "Metrics.js" as Metrics

Text {
  id: root
  property string role: "body"
  property int bodySize: 16
  property bool dim: role === "caption" || role === "overline" || role === "dim"

  font.family: Metrics.FONT
  font.pixelSize: Metrics.typeSize(root.bodySize, root.role === "dim" ? "caption" : root.role)
  font.weight: {
    if (root.role === "title") return Font.DemiBold
    if (root.role === "subtitle") return Font.DemiBold
    if (root.role === "overline") return Font.DemiBold
    return Font.Normal
  }
  font.letterSpacing: root.role === "overline" ? 1.2 : 0
  wrapMode: Text.WordWrap
}
