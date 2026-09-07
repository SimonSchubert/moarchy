// The Settings tree, flattened and scored, for the drawer's search field.
//
// docs/settings.md section O is the contract. In one sentence: typing in the app
// drawer searches this tree as well as the app catalogue, and a tap on a result
// goes to the row rather than to a screen two levels above it.
//
// ---------------------------------------------------------------------------
// Why a walk and not a list
// ---------------------------------------------------------------------------
// There is exactly one place a settings action is declared, and it is PAGES.
// A second list -- a hand-written "things you can search for" table -- would be
// a list to forget to update, and the way you would find out is a row that works
// everywhere except in search. So the index is derived, and O3 asserts that
// every result names a page and row Settings can actually stand on.
//
// ---------------------------------------------------------------------------
// What is not in it, and why that is structural
// ---------------------------------------------------------------------------
// A page may build its rows at open from a `provider`: the ~420 timezone cities,
// every installed font, every wallpaper in the theme, every live reminder, every
// plugin, every audio device. None of those are in PAGES, so none of them can
// reach this index -- not because a filter drops them but because there is
// nothing here to walk. That is O10, and it is the reason a search for "e" comes
// back with a handful of rows rather than four hundred cities.
//
// `input` rows are skipped: "Minutes" and "Message" are the labels on two fields,
// not destinations, and the row that consumes them (Set a reminder) is indexed.
//
// ---------------------------------------------------------------------------
// Why the scoring bands are upstream's
// ---------------------------------------------------------------------------
// The two lists are read as one screen, so they have to rank the same way. The
// bands below are AppSearch.js's (shell/services/AppSearch.js in the Omarchy
// shell): a name prefix beats an id prefix beats a substring, and inside a band
// the shorter label wins. Nothing here needs to match its numbers exactly -- the
// two lists are never merged -- but a query that puts "Screenshot" above "Screen
// record" in one and below it in the other reads as a bug.
.pragma library

.import "Pages.js" as Pages

// Row types that never make it into the index. Everything else does, and what a
// tap *does* with it is decided in the drawer (O4-O6, O9), not here.
var SKIP_TYPES = { "input": true };

// A row may also opt out by declaring `unlisted: true`, which the walk honours
// below. It exists for one shape: a nav row whose only destination is a page
// built by a `provider`.
//
// The paragraph above about providers says the ~420 timezone cities cannot
// reach this index because there is nothing here to walk. True -- but the
// eleven region rows that lead to them are declared, so they were indexed, and
// the result was that typing "a" answered Asia, Africa, Arctic and America:
// four of five slots spent on buckets whose contents are deliberately
// unsearchable. A row that can only take you to a list search cannot see is
// not a search result, it is scaffolding.
//
// Declared on the row rather than listed by page id here, because a page id in
// this file would be exactly the second list the essay at the top refuses.

// A row that needs a field filled in before it can act is findable but never
// first. "set reminder" matches both `tools.reminders.new/custom` -- the row at
// the bottom of the Set screen, inert until a duration is typed (J8) -- and
// `tools.reminders/new`, the screen that has the field. Untouched, the inert one
// won by two points on label length, so the best answer to "set reminder" was
// the one thing on the list that cannot set a reminder. O9 keeps it reachable
// and this keeps it second.
var NOT_READY_PENALTY = 1000;

var _index = null;

// Matching is done on letters and digits only, so a hyphen or an ampersand in a
// label is not a wall. "Wi-Fi networks" is the case that forced this: the row a
// person is looking for when they type the six most likely characters on this
// phone, and it matched none of them. Separators become spaces rather than
// vanishing, so words stay words and "network" cannot match across the join
// between two of them.
function normalise(text) {
    return String(text).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

// The other half of the same problem. Turning separators into spaces lets
// someone type "wi-fi" and match "Wi-Fi networks"; it does not let them type
// "wifi", which is the spelling they actually use. So there is a second form
// with the separators gone entirely, matched as the lowest band. It can join
// two words into a match no one meant -- that is the price of the band, and it
// is why it ranks below every form that respects word boundaries.
function squash(text) {
    return String(text).toLowerCase().replace(/[^a-z0-9]+/g, "");
}

// The top-level section a page belongs to, by title. Page ids are hierarchical
// all the way down -- "system.time.zone.Europe" is under "system.time.zone" is
// under "system.time" is under "system" -- so the first dotted segment is the
// section and no parent table is needed. A row on the root page is under
// "Settings" itself.
function sectionFor(pageId) {
    var head = String(pageId).split(".")[0];
    if (head === "root") return "Settings";
    var p = Pages.page(head);
    return p ? String(p.title) : "Settings";
}

// Every declared row in every page, once. Memoised: PAGES is static after the
// timezone loop at the bottom of Pages.js runs, and this is walked on every
// keystroke.
// The glyph a page is reached by, from the `nav` row that opens it. Twenty-odd
// rows in the tree carry no glyph of their own -- every radio on every choice
// page: Cloudflare, Firefox, Foot -- because on their own screen they are a
// column of ticks under a header that already has the icon. Pulled out of that
// screen and into a list of five unrelated results, they would be the only rows
// with an empty slot, so they borrow the one their page is reached by.
function navGlyphs() {
    var out = {};
    for (var pid in Pages.PAGES) {
        var rows = Pages.PAGES[pid].rows || [];
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            if (r.type === "nav" && r.page && r.glyph && !out[r.page])
                out[r.page] = String(r.glyph);
        }
    }
    return out;
}

function index() {
    if (_index) return _index;

    var inherited = navGlyphs();
    var out = [];
    for (var pid in Pages.PAGES) {
        var page = Pages.PAGES[pid];
        var rows = page.rows || [];
        var section = sectionFor(pid);
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            if (!r || !r.label) continue;
            if (SKIP_TYPES[r.type]) continue;
            if (r.unlisted) continue;
            var label = String(r.label);
            out.push({
                key: pid + "/" + r.id,
                pageId: pid,
                rowId: String(r.id),
                row: r,
                type: String(r.type || ""),
                label: label,
                glyph: String(r.glyph || inherited[pid] || ""),
                section: section,
                notReady: !!r.requires,
                lower: normalise(label),
                squashed: squash(label + " " + section + " "
                                 + String(r.keywords || "")),
                // Matched but not shown: the section a row lives in, and
                // whatever words the row declares for the case where the one a
                // person types is not in its label.
                haystack: normalise(label + " " + section + " "
                                    + String(r.keywords || ""))
            });
        }
    }
    _index = out;
    return out;
}

// -1 means "no match", exactly as upstream's fuzzyScore uses it.
function scoreOne(hit, term) {
    var lower = hit.lower;
    if (lower.indexOf(term) === 0) return 10000 - lower.length;
    // A word-start inside the label: "record" against "Screen record". Cheaper
    // than a regex and it is the match a person means most often after a prefix.
    if (lower.indexOf(" " + term) >= 0) return 9000 - lower.length;
    if (lower.indexOf(term) >= 0) return 8000 - lower.length;
    if (hit.haystack.indexOf(term) >= 0) return 6000 - lower.length;
    if (hit.squashed.indexOf(squash(term)) >= 0) return 5000 - lower.length;
    return -1;
}

// Every whitespace-separated term must match something, which is what makes
// "screen record" narrow rather than widen. Upstream's allTermsMatch does the
// same, and a search field that behaved differently in its two halves would be
// the kind of thing nobody can describe but everybody notices.
function score(hit, terms) {
    var total = 0;
    for (var i = 0; i < terms.length; i++) {
        var s = scoreOne(hit, terms[i]);
        if (s < 0) return -1;
        total += s;
    }
    return total / terms.length;
}

// The top `limit` rows for a query, best first. An empty query answers nothing
// at all: with the field empty the drawer is the app grid it has always been
// (O1), and that is a decision about the screen rather than a shortcut here.
function search(query, limit) {
    var q = normalise(query);
    if (!q) return [];

    var terms = q.split(" ");
    var rows = index();
    var scored = [];
    for (var i = 0; i < rows.length; i++) {
        var s = score(rows[i], terms);
        if (s < 0) continue;
        if (rows[i].notReady) s -= NOT_READY_PENALTY;
        scored.push({ hit: rows[i], score: s });
    }

    scored.sort(function(a, b) {
        if (a.score !== b.score) return b.score - a.score;
        if (a.hit.label < b.hit.label) return -1;
        if (a.hit.label > b.hit.label) return 1;
        return 0;
    });

    var out = [];
    var n = Math.min(scored.length, limit || 5);
    for (var j = 0; j < n; j++) out.push(scored[j].hit);
    return out;
}
