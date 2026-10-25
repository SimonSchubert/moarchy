// Every installed Omarchy theme, and the one call that applies one
// (docs/home.md HM40).
//
// Usage:
//     Shared.ThemeCatalog { id: catalog }
//     ...
//     model: catalog.themes          // [{slug, name, mode, background,
//                                    //   foreground, accent, chips}]
//     catalog.currentSlug            // what current/theme.name says
//     catalog.apply(row)             // omarchy-theme-set, one at a time
//
// The theme picker kept this to itself, and the home menu's theme strip was
// about to be the second copy of a Python scan and a `Process` that each carry
// a paragraph of hard-won reasons. Both now read the same catalogue, so a fix
// to how a theme is named or applied lands in both.
//
// It scans on creation and after every apply. Call scan() when a screen opens
// if it may have been a while: a theme installed meanwhile is otherwise missed.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: catalog

  visible: false

  property var themes: []
  property string currentSlug: ""
  // The theme being applied; "" when none is. One at a time: omarchy-theme-set
  // regenerates every app's template, seven seconds on an A53, and two at once
  // race each other's writes.
  property string pendingSlug: ""

  function scan(): void {
    if (!themeScan.running) themeScan.running = true
  }

  Component.onCompleted: catalog.scan()

  // One subprocess for the whole catalogue rather than a FileView per theme.
  // Twenty-two file watchers for data that only changes when a theme is
  // installed is a lot of inotify for nothing, and the parse is trivial.
  //
  // The display name has to be derived exactly the way omarchy-theme-list
  // derives it -- title-case each hyphen-separated word, then swap hyphens for
  // spaces -- because omarchy-theme-set is given that name and looks the
  // directory back up from it. "rose-pine" must come back as "Rose Pine" and
  // nothing else.
  Probe {
    id: themeScan
    command: ["python3", "-c",
      "import glob, json, os, re\n" +
      "home = os.path.expanduser('~')\n" +
      "bases = [home + '/.config/omarchy/themes', os.environ.get('OMARCHY_PATH', home + '/.local/share/omarchy') + '/themes']\n" +
      "seen = set()\n" +
      "rows = []\n" +
      "for base in bases:\n" +
      "    for d in sorted(glob.glob(base + '/*')):\n" +
      "        slug = os.path.basename(d)\n" +
      "        if slug in seen or not os.path.isdir(d):\n" +
      "            continue\n" +
      "        c = {}\n" +
      "        try:\n" +
      "            for line in open(os.path.join(d, 'colors.toml')):\n" +
      "                m = re.match(r'\\s*([a-z_]+)\\s*=\\s*\"([^\"]+)\"', line)\n" +
      "                if m:\n" +
      "                    c[m.group(1)] = m.group(2)\n" +
      "        except OSError:\n" +
      "            continue\n" +
      "        if 'background' not in c:\n" +
      "            continue\n" +
      "        seen.add(slug)\n" +
      "        name = re.sub(r'(^|-)([a-z])', lambda m: m.group(1) + m.group(2).upper(), slug).replace('-', ' ')\n" +
      "        rows.append({'slug': slug, 'name': name, 'mode': c.get('mode', 'dark'),\n" +
      "                     'background': c['background'], 'foreground': c.get('foreground', '#ffffff'),\n" +
      "                     'accent': c.get('accent', c.get('blue', '#888888')),\n" +
      "                     'chips': [c.get(k, '#888888') for k in ('accent', 'red', 'green', 'yellow', 'blue', 'magenta')]})\n" +
      // current/theme is a staged *copy* of the theme, not a symlink to it, so
      // its basename is always the literal string "theme". The slug lives in
      // current/theme.name, which is what omarchy-theme-current reads.
      "cur = ''\n" +
      "try:\n" +
      "    cur = open(home + '/.local/state/omarchy/current/theme.name').read().strip()\n" +
      "except OSError:\n" +
      "    pass\n" +
      "print(json.dumps({'current': cur, 'themes': rows}))\n"]
    onAnswered: {
      try {
        var parsed = JSON.parse(String(text || "{}"))
        catalog.themes = parsed.themes || []
        catalog.currentSlug = String(parsed.current || "")
      } catch (e) {
        console.warn("theme scan failed to parse:", e)
      }
    }
  }

  // Run, not execDetached, so the exit tells us when to re-read which theme is
  // current. Detached would leave the tick sitting on the old card until the
  // user reopened the screen.
  Process {
    id: applyTheme
    property string slug: ""
    onExited: {
      catalog.pendingSlug = ""
      catalog.scan()
    }
  }

  function apply(row): void {
    if (!row || catalog.pendingSlug !== "" || row.slug === catalog.currentSlug) return
    catalog.pendingSlug = row.slug
    applyTheme.slug = row.slug
    // By display name, because that is omarchy-theme-set's argument, and as
    // argv rather than a shell string because those names carry spaces.
    //
    // By NAME, not by absolute path. This used to be
    // root.omarchyPath + "/bin/omarchy-theme-set", written when OMARCHY_PATH
    // was the vendored checkout in ~/.local/share/omarchy and its bin/ really
    // was where these scripts lived. Packaging moved them: omarchy-config
    // installs upstream's bin/ to /usr/bin (pkgbuilds/omarchy-config/PKGBUILD)
    // and never creates $OMARCHY_PATH/bin at all. The old path therefore named
    // a directory that does not exist, Quickshell could not spawn it, and the
    // picker sat on "Applying..." forever with only
    //   Process failed to start, likely because the binary could not be found.
    //   Command: QList("/usr/share/omarchy/bin/omarchy-theme-set", ...)
    // in the shell log to say so. The selftest had been calling this out as
    // "omarchy-menu is missing from /usr/share/omarchy/bin" the whole time; it
    // was filed as harmless because nothing was thought to need that directory.
    //
    // A bare name is what the rest of the plugins do, and it is what makes the
    // PATH-order shadowing in the PKGBUILD work: /usr/lib/moarchy/bin comes
    // before /usr/bin, so a moarchy counterpart wins if one is ever added.
    applyTheme.command = ["omarchy-theme-set", String(row.name)]
    applyTheme.running = true
  }
}
