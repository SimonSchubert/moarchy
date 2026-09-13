/* The active theme's palette, for the GTK3 apps (docs/style.md I1).
 *
 * Geary is the GTK3 window a phone actually opens, and the file chooser the
 * xdg portal draws is the other one -- neither can be themed the way
 * gtk.css.tpl themes the GTK4 apps. GTK3's built-in Adwaita has its colours
 * baked in at build time, so the names a user stylesheet overrides are not the
 * ones its rules read: upstream measured exactly that with an offscreen render
 * in basecamp/omarchy#7557, where Adwaita drew identically with and without
 * the overrides.
 *
 * adw-gtk3 is the way around it, and it is why `adw-gtk-theme` is in
 * pkgbuilds/moarchy-meta. It is libadwaita's stylesheet ported to GTK3, and
 * its rules read named colours rather than baked hex, so overriding the names
 * from here reaches them. Two halves, and neither works alone: this file, read
 * through the ~/.config/gtk-3.0/gtk.css symlink, and the gtk-theme switch in
 * bin/omarchy-theme-set-gnome that points GTK3 at adw-gtk3 rather than at
 * Adwaita on every theme set.
 *
 * ---------------------------------------------------------------------------
 * Why only the libadwaita names, and not GTK3's own
 *
 * Counted in adw-gtk3 6.5's own gtk.css: @window_bg_color is read 243 times,
 * @accent_bg_color 164, @headerbar_bg_color 42 -- and @theme_bg_color,
 * @theme_fg_color, @theme_selected_bg_color and @borders exactly ZERO times
 * each. The classic names are not dead there, though: the theme DEFINES them
 * as aliases of these,
 *
 *     @define-color theme_bg_color @window_bg_color;
 *     @define-color theme_selected_bg_color @accent_bg_color;
 *     @define-color borders mix(currentColor,@window_bg_color,0.85);
 *
 * so an app whose own stylesheet asks for @theme_bg_color gets the value set
 * below anyway, and everything adw-gtk3 derives -- borders, backdrops,
 * insensitive text -- derives from these. Overriding the classic names here as
 * well would add nothing and would replace the theme's own derivations with
 * flat guesses, so this file sets the names that are read and stops.
 *
 * A separate file from gtk.css.tpl rather than the same one symlinked twice,
 * because that one opens with a `:root` block of CSS variables and GTK3's
 * parser has no custom properties. The values are the same ones GTK4 gets, so
 * Geary and Contacts agree about what the theme looks like, and the reasoning
 * behind them -- text on the accent is the theme background -- is documented
 * once, there.
 */

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
