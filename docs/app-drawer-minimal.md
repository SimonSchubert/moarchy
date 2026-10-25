# The minimal app drawer — specification

A second app drawer: one row per app, alphabetical, with a monochrome glyph
instead of artwork and an A–Z rail down the side. Present tense, normative.

It does not replace [`moarchy.app-drawer`](gestures.md). Both ship, both are
sheets, and which one an edge raises is the setting that already decides that
([`gestures.md`](gestures.md) Q1). The shipped pairing does not move.

**Why a second plugin rather than a mode on the first.** The two disagree about
what a launcher *is* — a grid you recognise by artwork against a list you read
by name — and that disagreement reaches the model, the delegate, the scroll
axis and the icon. `AppDrawer.qml` is 2500 lines with a search index and an
uninstall card in it; a branch through all of that for a second layout is how
one file comes to serve neither. What they genuinely share is the sheet
machinery, and that is already `moarchy.common`.

Ids are `M<n>`, cited by any check that proves one.

Lines marked **?** are a decision I am recommending, not one you have made.

## Vocabulary

| Term | What it means |
| --- | --- |
| **the minimal app drawer** | This sheet. `moarchy.app-drawer-minimal` · `app-drawer-minimal` · **Minimal app drawer** |
| **the app drawer** | [`moarchy.app-drawer`](gestures.md) §N — the grid, unchanged by any of this |
| **the rail** | The column of letters down the right-hand edge of the list |
| **the glyph** | The one-colour icon a row draws, from the icon font, in the theme's ink |

---

## A. What it is

**M1** It is a sheet, on the same terms as the other four: full-screen, put
away rather than left running, and `Sheet.js` is where its id is written.
→ `node scripts/sheet-test.js` passes with five sheets, and
`omarchy-shell app-drawer-minimal state` answers `open` or `closed`

**M2** It arrives from the edge that raised it and closes back along the same
axis, through the same `Edge.js` table and the same `DragTracker` as every
other sheet. There is no second drag implementation here.
→ `grep -c 'Shared.DragTracker' moarchy.app-drawer-minimal/AppDrawerMinimal.qml`
is 2 — the sheet and its handle — and `scripts/style-check.sh` §F stays green

**M3 ?** The shipped pairing is unchanged: the strip raises the app drawer and
the right edge the workspace overview. This one is a value the two edges can
take, and nothing else selects it.
→ with no `ui.toml`, `moarchy-ui get gesture-bottom` == `app-drawer`;
`moarchy-ui gesture-bottom app-drawer-minimal` then makes
`omarchy-shell gestures status` report
`bottom=moarchy.app-drawer-minimal`

**M4** Both drawers may be on the phone at once and neither knows about the
other. Opening either puts the other away, because they are both rank-1 sheets
and that is B6's rule with no exception written for them.
→ with the minimal drawer open, `omarchy-shell app-drawer open` leaves
`omarchy-shell app-drawer-minimal state` == `closed`

## B. The list

**M5** One row per app, in the order `appLibrary.sortedEntries("")` gives —
which is already alphabetical by the name the app drawer draws. Two launchers
listing the same apps in two different orders is the defect this avoids by
asking the same question.
→ `omarchy-shell app-drawer-minimal rows` and `omarchy-shell app-drawer
entries` name the same set

**M6** A row is a glyph, a name, and nothing else. No subtitle, no category, no
badge: the screen is a list you read down, and a second line halves how many
apps a thumb can reach without scrolling.
→ `omarchy-shell app-drawer-minimal rows` prints `id`, `glyph` and `name`, and
every row is `Style.space(46)` tall

**M7** A tap launches the app down the app drawer's own path — the hop to a
free workspace, the Android routing, the splash — and dismisses the sheet.
Nothing about *what launching means* is decided twice.
→ `omarchy-shell app-drawer-minimal launch org.moarchy.Clock.plugin` answers
`ok` and the sheet closes

## C. The icons

**M8** Every icon is one glyph from the icon font, painted in the theme's menu
ink. No app artwork is drawn on this screen at all. That is the whole point of
it: a column of full-colour squares at 24px is a column of coloured squares,
and one ink makes the list read as a list.
→ `grep -c 'appLibrary.iconSource' moarchy.app-drawer-minimal/*.qml` is 0

**M9** A theme switch restyles it, because the ink is `Color.menu.text` and
never a literal.
→ `scripts/style-check.sh` finds no hex in the plugin (C4)

**M10** The glyph comes from the desktop entry's `Categories`, most specific
first, with a short override table for the entries whose categories do not say
what they are — Weather is `Utility;` and nothing else. Anything unmatched is
one generic glyph rather than a blank.
→ `omarchy-shell app-drawer-minimal rows` prints a non-empty glyph on every
row, and `node scripts/glyph-test.js` passes

**M11** Every glyph literal is one character and is in the shipped icon font.
This is [`gestures.md`](gestures.md)'s existing rule reaching a new file, not a
new promise — but the table here is 30-odd codepoints written at once, which is
the first time it has been worth saying.
→ `moarchy-selftest`'s icon-literal check covers
`moarchy.app-drawer-minimal/*.qml`, and the codepoints in `Glyphs.js` are
`md-*` names from Nerd Fonts' own `glyphnames.json`

## D. The rail

**M12** A column of letters down the right-hand edge, one per letter the list
actually has an app under. A letter with no app is not drawn — a rail that
offers Q, X and Z on a phone with 34 apps is three dead targets.
→ `omarchy-shell app-drawer-minimal rail` prints only letters that `rows`
also starts a name with

**M13** A touch anywhere on the rail scrolls the list to that letter's first
app, and keeps scrolling as the finger slides up or down it without being
lifted. It is a scrubber, not eleven buttons.
→ `omarchy-shell app-drawer-minimal railTarget M` answers the row index that
`rows` gives the first `m` name

**M14** The rail does not drag the sheet. It is the one control on this surface
exempt from H3, and deliberately: its whole gesture is a vertical drag, and a
sheet that closed whenever somebody scrubbed to S would be a sheet with a rail
nobody could use.
→ the exemption is a comment in the source naming this criterion, and
`scripts/style-check.sh` passes

## E. Search

**M15** The same search pill the app drawer has, in the same place, filtering
the same way — `sortedEntries(query)`, debounced, with a clear button once
there is something to clear.
→ `omarchy-shell app-drawer-minimal type foot` leaves `rows` naming only
matching apps; `type ""` restores the full list

**M16** The rail is absent while a query is showing. Eleven letters down the
side of four results is a rail that cannot take the thumb anywhere it is not
already.
→ after `type foot`, `omarchy-shell app-drawer-minimal rail` is empty

## F. What it is not

**M17** No uninstall card and no long press. Removing an app is the app
drawer's (`gestures.md` §L) and stays there: one screen that can uninstall
things is enough, and it is the one with the artwork you can be sure you
recognised.
→ `grep -c 'moarchy-app-remove' moarchy.app-drawer-minimal/*.qml` is 0

**M18** No settings results. Typing here searches apps and nothing else; the
settings index is the app drawer's (`settings.md` §O).
→ `grep -c 'moarchy.settings' moarchy.app-drawer-minimal/*.qml` is 0

**M19 ?** No Settings row on the two tap triggers
([`gestures.md`](gestures.md) Q10). The *word* works there like every other
sheet word — `normTap` takes its vocabulary from the same table an edge does,
so `moarchy-ui gesture-hold app-drawer-minimal` stores and labels correctly —
but the hold and power pages build their rows from `moarchy-trigger rows`, and
that list is presently naming sheets by identifiers rather than by the
`ui.toml` words it has to write. Adding a fifth row to a list whose other three
do not work would bury the defect rather than fix it.
→ `moarchy-ui gesture-hold app-drawer-minimal` then `moarchy-ui get
gesture-hold-label` reads `Minimal app drawer`
