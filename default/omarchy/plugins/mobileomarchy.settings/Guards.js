// One bash process per page, for every question that page needs answered.
//
// ---------------------------------------------------------------------------
// Why batched, and why per page
// ---------------------------------------------------------------------------
// Upstream's menu does this too (shell/plugins/menu/MenuModel.js, guardScript),
// but for the whole 320-entry tree at once, because a dmenu you can type into
// has to know what every row would match before you have typed it. A phone
// stack only ever shows one page, so it only ever asks about one page -- which
// is the difference between one `pacman -Qi` on the root screen and none.
//
// Batched rather than a Process per row because a fork on a 1.15GHz A53 costs
// far more than the test inside it. A page of a dozen rows is one bash.
//
// ---------------------------------------------------------------------------
// The wire format
// ---------------------------------------------------------------------------
// One line per answer, `<rowId>:<tag>:<value>`, tags:
//
//   w   a `when:` guard. 1 or 0. Row is rendered only on 1.
//   v   a value read: a switch's state, a choice page's current value, an
//       info row's text, a nav row's detail line.
//
// Only the first two colons separate; everything after them is the value, so a
// value carrying a colon or a space survives as itself. Newlines are the one
// thing that would split a value across two lines, so they are folded to spaces
// in the shell rather than encoded here -- which keeps this file free of
// Qt.atob, which a .pragma library has no access to.
.pragma library

// Distinct expressions are captured once and referenced by name. Upstream does
// the same for its six readers; here it falls out of deduplication, which also
// covers the case where two rows happen to read the same thing.
function build(rows, pageReader) {
    var reads = [];        // expression -> index
    var index = {};
    var lines = [];

    function readerFor(expr) {
        if (!(expr in index)) {
            index[expr] = reads.length;
            reads.push(expr);
        }
        return "__r" + index[expr];
    }

    var wants = [];
    if (pageReader)
        wants.push({ id: "__page", expr: pageReader });

    for (var i = 0; i < rows.length; i++) {
        var r = rows[i];
        if (r.when)
            lines.push("if { " + r.when + "; } >/dev/null 2>&1; then echo "
                       + r.id + ":w:1; else echo " + r.id + ":w:0; fi");
        var expr = r.read || r.detailCmd || "";
        if (expr) wants.push({ id: r.id, expr: expr });
    }

    var body = [];
    for (var j = 0; j < wants.length; j++)
        body.push({ id: wants[j].id, name: readerFor(wants[j].expr) });

    var out = [];
    for (var k = 0; k < reads.length; k++)
        out.push("__r" + k + "=$( { " + reads[k] + "; } 2>/dev/null )");
    for (var m = 0; m < body.length; m++)
        out.push("printf '%s:v:%s\\n' " + body[m].id
                 + " \"$(printf '%s' \"$" + body[m].name + "\" | tr '\\n' ' ')\"");

    return out.concat(lines).join("\n") + "\n";
}

// A half-read batch is worse than no batch: `when` hides only on an explicit 0,
// so a truncated answer would *show* rows that should not be there. Upstream
// discards an incomplete batch for the same reason.
function parse(text) {
    var out = { when: {}, value: {} };
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (!line) continue;
        var a = line.indexOf(":");
        if (a < 0) continue;
        var b = line.indexOf(":", a + 1);
        if (b < 0) continue;
        var id = line.substring(0, a);
        var tag = line.substring(a + 1, b);
        var raw = line.substring(b + 1);
        if (tag === "w") out.when[id] = raw === "1";
        else if (tag === "v") out.value[id] = raw.trim();
    }
    return out;
}
