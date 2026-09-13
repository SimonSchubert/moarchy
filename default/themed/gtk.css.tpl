/* The active theme's palette, for GTK4 and libadwaita apps (docs/style.md I1).
 *
 * Upstream Omarchy themes a GTK app exactly twice: light or dark, and an icon
 * theme -- omarchy-theme-set-gnome, two gsettings calls. Every colour after
 * that is stock Adwaita, so on tokyo-night Contacts sat in Adwaita grey with a
 * stock blue accent while the shell beside it was #1a1b26 with #7aa2f7. On a
 * desktop that is a file manager and some dialogs. Here GNOME's apps ARE the
 * app tier (docs/apps.md), so it is most of what the screen shows.
 *
 * This is a TEMPLATE, and that is the whole trick. omarchy-theme-set-templates
 * renders $OMARCHY_PATH/default/themed/*.tpl on every theme set, substituting
 * the active theme's colors.toml, into
 * ~/.local/state/omarchy/current/theme/gtk.css -- and ~/.config/gtk-4.0/gtk.css
 * is a symlink to that path, made by bin/omarchy-theme-set-gnome. So nothing
 * upstream is patched and nothing is copied into a home: this ships into the
 * same directory sway.conf.tpl already ships into, which upstream's own engine
 * already reads.
 *
 * A theme that ships its own gtk.css keeps it -- the engine only renders a
 * template whose output does not already exist. And if either of the two open
 * upstream PRs lands a default/themed/gtk.css.tpl of its own (basecamp/omarchy
 * #8408, #8584), this file is at the same path in a package that shadows
 * theirs, so it wins until somebody deletes it deliberately.
 *
 * ---------------------------------------------------------------------------
 * Why both syntaxes below
 *
 * libadwaita 1.6 moved its colours to CSS variables, and its own documentation
 * says the @define-color names left behind are compatibility only and "don't
 * pick up overridden colors". Every community solution for this still writes
 * @define-color -- moarchy-store's own theme.py does -- which is evidence that
 * the compat path does something on the versions people run, but the
 * documented path is :root. Both are kept: the variables are what the
 * documentation supports going forward, and the compat names are what a plain
 * GTK4 app that never linked libadwaita reads.
 *
 * ---------------------------------------------------------------------------
 * Named colours only, no widget selectors
 *
 * libadwaita derives borders, shadows, backdrops and high-contrast variants
 * from these, so overriding the names recolours every stock widget -- rows,
 * headers, entries, buttons -- without this file having to know they exist. It
 * is also what keeps it short enough to read.
 *
 * The one judgement call is text drawn ON the accent. sed cannot compute
 * contrast, so accent_fg_color has to be a palette colour picked in advance,
 * and it is the theme BACKGROUND: across upstream's 22 themes the worst
 * separation from the accent it sits on is far wider than `foreground` would
 * have given, and there is no theme where foreground would have been the
 * better pick. Upstream PR #8408 reached the same answer.
 *
 * Everything degrades to stock libadwaita: no colors.toml, no render, no file,
 * and a dangling symlink is a file GTK does not find. Themed by the palette's
 * presence, never broken by its absence (docs/style.md I2).
 */

:root {
  --window-bg-color: {{ background }};
  --window-fg-color: {{ bright_foreground }};

  --view-bg-color: {{ background }};
  --view-fg-color: {{ bright_foreground }};

  --headerbar-bg-color: {{ background }};
  --headerbar-fg-color: {{ bright_foreground }};

  /* Sidebars, cards and popovers are the one step off the background that says
   * "this is a surface on top of that one" -- docs/style.md C2's `container`,
   * in libadwaita's names. lighter_background is the theme's own answer for
   * it; every stock theme defines it, and omarchy-theme-color derives one for
   * a theme that does not. */
  --sidebar-bg-color: {{ lighter_background }};
  --sidebar-fg-color: {{ bright_foreground }};

  --card-bg-color: {{ lighter_background }};
  --card-fg-color: {{ bright_foreground }};

  --popover-bg-color: {{ lighter_background }};
  --popover-fg-color: {{ bright_foreground }};

  --dialog-bg-color: {{ background }};
  --dialog-fg-color: {{ bright_foreground }};

  --accent-bg-color: {{ accent }};
  --accent-fg-color: {{ background }};
  --accent-color: {{ accent }};

  --destructive-bg-color: {{ red }};
  --destructive-fg-color: {{ background }};
  --destructive-color: {{ red }};

  --success-bg-color: {{ green }};
  --success-fg-color: {{ background }};
  --success-color: {{ green }};

  --warning-bg-color: {{ yellow }};
  --warning-fg-color: {{ background }};
  --warning-color: {{ yellow }};

  --error-bg-color: {{ red }};
  --error-fg-color: {{ background }};
  --error-color: {{ red }};
}

/* The compatibility names, for libadwaita before 1.6 and for plain GTK4 apps
 * that never linked libadwaita at all. Same values, and harmless where the
 * variables above are what actually takes. */
@define-color window_bg_color {{ background }};
@define-color window_fg_color {{ bright_foreground }};
@define-color view_bg_color {{ background }};
@define-color view_fg_color {{ bright_foreground }};
@define-color headerbar_bg_color {{ background }};
@define-color headerbar_fg_color {{ bright_foreground }};
@define-color sidebar_bg_color {{ lighter_background }};
@define-color sidebar_fg_color {{ bright_foreground }};
@define-color card_bg_color {{ lighter_background }};
@define-color card_fg_color {{ bright_foreground }};
@define-color popover_bg_color {{ lighter_background }};
@define-color popover_fg_color {{ bright_foreground }};
@define-color dialog_bg_color {{ background }};
@define-color dialog_fg_color {{ bright_foreground }};
@define-color accent_bg_color {{ accent }};
@define-color accent_fg_color {{ background }};
@define-color accent_color {{ accent }};
@define-color destructive_bg_color {{ red }};
@define-color destructive_fg_color {{ background }};
@define-color destructive_color {{ red }};
@define-color success_bg_color {{ green }};
@define-color success_fg_color {{ background }};
@define-color success_color {{ green }};
@define-color warning_bg_color {{ yellow }};
@define-color warning_fg_color {{ background }};
@define-color warning_color {{ yellow }};
@define-color error_bg_color {{ red }};
@define-color error_fg_color {{ background }};
@define-color error_color {{ red }};
