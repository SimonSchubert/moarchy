// A box that holds boxes, or rows.
//
// The list shape on this phone: one fill behind the whole list, the rows
// flush inside it with nothing between them but the gap their own padding
// leaves. No rules, no hairlines, no fill per row -- a row lights up only
// under a thumb, and then as a rounded rectangle inset far enough that its
// corner is concentric with the group's own.
//
// That inset is `Metrics.GROUP_PAD`, and it is the whole reason the number
// exists: `Metrics.inner(RADIUS_LG, GROUP_PAD)` is `RADIUS_MD`, so a ListRow
// pressed at the top of a group curves the same way the group does.
import QtQuick
import "Metrics.js" as Metrics

Card {
  id: root
  pad: Metrics.GROUP_PAD
  radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
  spacing: 0
}
