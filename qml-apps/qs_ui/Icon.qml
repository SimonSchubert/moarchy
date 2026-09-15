// A symbolic SVG, recoloured to the surface ink.
//
// Quickshell.iconPath() asks the icon theme (Yaru-magenta here) at the
// control's 44px slot and comes back empty. GTK finds the same names
// through Adwaita's fallback chain. We load Adwaita's file directly, and
// keep the themed lookup as the fallback for systems that are not our image.
//
// Those SVGs ship with fill="#2e3436". libadwaita tints them; Image does
// not, so on a dark grid they are invisible. ColorOverlay is that tint.
import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects

Item {
  id: root
  property var names: []
  property int size: 18  // Metrics.ICON_INK; Adwaita fills the canvas, MD does not
  property int slot: 44
  property color color: "#ffffff"

  width: slot
  height: slot

  readonly property var files: ({
    "view-list-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-list-symbolic.svg",
    "view-grid-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-grid-symbolic.svg",
    "view-app-grid-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-app-grid-symbolic.svg",
    "go-previous-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg",
    "pan-start-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-start-symbolic.svg",
    "pan-down-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-down-symbolic.svg",
    "pan-end-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-end-symbolic.svg",
    "checkbox-checked-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/checkbox-checked-symbolic.svg",
    "system-search-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/system-search-symbolic.svg",
    "view-more-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-more-symbolic.svg",
    "open-menu-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/open-menu-symbolic.svg",
    "view-pin-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-pin-symbolic.svg",
    "starred-symbolic": "/usr/share/icons/Adwaita/symbolic/status/starred-symbolic.svg",
    "non-starred-symbolic": "/usr/share/icons/Adwaita/symbolic/status/non-starred-symbolic.svg",
    "color-select-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/color-select-symbolic.svg",
    "user-trash-symbolic": "/usr/share/icons/Adwaita/symbolic/places/user-trash-symbolic.svg",
    "list-add-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/list-add-symbolic.svg",
    "window-close-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/window-close-symbolic.svg",
    "action-unavailable-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/action-unavailable-symbolic.svg",
    "object-select-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/object-select-symbolic.svg",
    "view-refresh-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-refresh-symbolic.svg",
    "edit-clear-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-clear-symbolic.svg",
    "edit-find-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-find-symbolic.svg",
    "computer-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/computer-symbolic.svg",
    "drive-harddisk-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/drive-harddisk-symbolic.svg",
    "network-wireless-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/network-wireless-symbolic.svg",
    "system-run-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/system-run-symbolic.svg",
    "pan-up-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-up-symbolic.svg",
    "alarm-symbolic": "/usr/share/icons/Adwaita/symbolic/status/alarm-symbolic.svg",
    "mark-location-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/mark-location-symbolic.svg",
    "appointment-new-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/appointment-new-symbolic.svg",
    "edit-delete-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-delete-symbolic.svg",
    "media-playlist-repeat-symbolic": "/usr/share/icons/Adwaita/symbolic/status/media-playlist-repeat-symbolic.svg",
    "x-office-calendar-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/x-office-calendar-symbolic.svg",
    "preferences-system-time-symbolic": "/usr/share/icons/Adwaita/symbolic/legacy/preferences-system-time-symbolic.svg",
    "media-playback-start-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/media-playback-start-symbolic.svg",
    "media-playback-pause-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/media-playback-pause-symbolic.svg",
    "media-playback-stop-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/media-playback-stop-symbolic.svg",
    "list-remove-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/list-remove-symbolic.svg",
    "document-edit-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/document-edit-symbolic.svg",

    // A file manager draws one glyph per row and has no say in how many rows
    // there are, so its names are the one block here that is a *set*: a folder,
    // the eight mimetypes Adwaita actually ships, and the places and devices
    // that make up a sidebar. Adwaita has no glyph for "a file of some other
    // kind" beyond text-x-generic, which is why that one is every row's last
    // resort rather than a type of its own.
    "folder-symbolic": "/usr/share/icons/Adwaita/symbolic/places/folder-symbolic.svg",
    "inode-directory-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/inode-directory-symbolic.svg",
    "text-x-generic-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/text-x-generic-symbolic.svg",
    "image-x-generic-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/image-x-generic-symbolic.svg",
    "audio-x-generic-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/audio-x-generic-symbolic.svg",
    "video-x-generic-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/video-x-generic-symbolic.svg",
    "font-x-generic-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/font-x-generic-symbolic.svg",
    "package-x-generic-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/package-x-generic-symbolic.svg",
    "x-office-document-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/x-office-document-symbolic.svg",
    "x-office-spreadsheet-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/x-office-spreadsheet-symbolic.svg",
    "x-office-presentation-symbolic": "/usr/share/icons/Adwaita/symbolic/mimetypes/x-office-presentation-symbolic.svg",
    "user-home-symbolic": "/usr/share/icons/Adwaita/symbolic/places/user-home-symbolic.svg",
    "user-desktop-symbolic": "/usr/share/icons/Adwaita/symbolic/places/user-desktop-symbolic.svg",
    "folder-download-symbolic": "/usr/share/icons/Adwaita/symbolic/places/folder-download-symbolic.svg",
    "folder-documents-symbolic": "/usr/share/icons/Adwaita/symbolic/places/folder-documents-symbolic.svg",
    "folder-pictures-symbolic": "/usr/share/icons/Adwaita/symbolic/places/folder-pictures-symbolic.svg",
    "folder-music-symbolic": "/usr/share/icons/Adwaita/symbolic/places/folder-music-symbolic.svg",
    "folder-videos-symbolic": "/usr/share/icons/Adwaita/symbolic/places/folder-videos-symbolic.svg",
    "drive-removable-media-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/drive-removable-media-symbolic.svg",
    "folder-new-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/folder-new-symbolic.svg",
    "edit-copy-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-copy-symbolic.svg",
    "edit-cut-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-cut-symbolic.svg",
    "edit-paste-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-paste-symbolic.svg",
    "document-open-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/document-open-symbolic.svg",
    "go-up-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/go-up-symbolic.svg",
    "go-home-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/go-home-symbolic.svg",
    "view-sort-ascending-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-sort-ascending-symbolic.svg"
  })

  // A name that is already a path is used as it is: "/usr/share/...",
  // "file://..." or whatever Qt.resolvedUrl() hands back for a file sitting
  // beside the QML that asked for it.
  //
  // The map above can only name files that are on the image, and an app whose
  // subject is a glyph no icon theme here has -- a stopwatch, an hourglass --
  // would otherwise need a second copy of this file to draw one. Such a plugin
  // ships the SVG next to its QML and passes
  // `Qt.resolvedUrl("glyph-stopwatch.svg")` instead, with a themed name after
  // it in the list as the fallback.
  function direct(name: string): string {
    var text = String(name)
    if (text.indexOf("file:") === 0 || text.indexOf("qrc:") === 0
        || text.charAt(0) === "/")
      return text
    return ""
  }

  // Which candidate we are on. An Adwaita install somewhere other than
  // /usr/share/icons, or a system with a different theme entirely, only shows
  // up as an Image that failed to load, so failing is how we walk the list.
  property int attempt: 0
  onNamesChanged: root.attempt = 0

  function candidate(n) {
    var list = root.names || []
    var i
    for (i = 0; i < list.length; i++) {
      var path = root.direct(list[i]) || root.files[String(list[i])]
      if (!path) continue
      // The map's entries are bare paths and a direct name may already carry a
      // scheme, so one is added only where there is not one.
      if (n === 0) return path.charAt(0) === "/" ? "file://" + path : path
      n--
    }
    // The themed lookup is the portable half, and it is second because it is
    // the expensive one: Quickshell.iconPath() walks the icon theme, which on
    // our image misses anyway. Nothing pays for it until the paths above fail.
    for (i = 0; i < list.length; i++) {
      var themed = Quickshell.iconPath(String(list[i]), true)
      if (!themed) continue
      if (n === 0) return themed
      n--
    }
    return ""
  }

  readonly property string source: root.candidate(root.attempt)

  Image {
    id: img
    anchors.centerIn: parent
    width: root.size
    height: root.size
    sourceSize.width: root.size
    sourceSize.height: root.size
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    source: root.source
    visible: false
    onStatusChanged: {
      if (status !== Image.Error) return
      if (root.candidate(root.attempt + 1) !== "") root.attempt++
    }
  }

  ColorOverlay {
    anchors.fill: img
    source: img
    color: root.color
    visible: img.status === Image.Ready
  }
}
