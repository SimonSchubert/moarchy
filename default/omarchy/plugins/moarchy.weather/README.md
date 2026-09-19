# Weather, in the shell

Now, the next day, and the week — where you are, and in the places you named.

<p align="center">
  <img src="docs/screenshots/today.png" width="30%" alt="A dark screen titled Berlin, with a location pin before the name: a sun behind a cloud beside 21 degrees, Partly cloudy under it, then a boxed strip of hours falling from 21 to 16 degrees, four tiles two across for wind, humidity, sunrise and sunset, and a box labelled The week holding five days, each with a coloured bar between its low and its high">
  <img src="docs/screenshots/places.png" width="30%" alt="The places page: a search field, then a box labelled Where you are holding Berlin with a refresh button beside it, a box labelled Saved holding Reykjavík, Cairo and Kyoto with a bin beside each — every row with its symbol, its temperature and its own local clock — then a Units card with a Celsius and Fahrenheit pair of chips, and a ticked Show where I am box over a sentence saying the town is looked up from the connection's address by GeoJS">
  <img src="docs/screenshots/catppuccin-latte.png" width="30%" alt="The same first screen under catppuccin-latte: a near-white window, slate ink, and the same orange and blue bars">
</p>

<p align="center"><em>360×720, the size of a PinePhone's screen under
mobileomarchy. Every colour is the active Omarchy theme's — the temperatures
are its own hues, mixed from the palette rather than picked — and
<code>omarchy-theme-set</code> repaints it without restarting the
shell.</em></p>

This one is not a port. There is no GTK weather app in `apps/`, and there is
not going to be one: it was written for the shell first, which is what an app
opened for nine seconds several times a day should be. Summoning it is
`visible = true` on a window the shell already holds, and the last forecast is
already in memory, so the answer is on the screen before the radio is asked.

## What this is, and what it is not

moarchy-store's `docs/android-gaps.md` puts **Breezy Weather** in tier one —
"radar, air quality, pollen, warnings, many sources" — and names it one of the
three worth writing first. **This is not that app.** There is no radar here, no
air quality, no pollen, no warnings and one source. Writing those was not the
job; the row stays open.

What the same catalogue already has is `gnome-weather`, which is listed,
featured, and whose sweep verdict reads *"Ran at 360x674 and drew correctly;
follows the theme. 1 packages, 0.15 MB"* — and `kweather` beside it. So the
honest version is the calculator's: **this is not a gap, it is the shell
argument**, and two things here are a phone's rather than a desktop's.

- **It is one screen.** Now, today and the week are one column you scroll, not
  three places to navigate between. The places live behind the title, because
  choosing a town is something you do twice a year and reading the sky is
  something you do at a bus stop.
- **It starts instantly**, because it is already running.

## The screen

- **The hero** is on the window's own background, the colour of the status bar
  above it. It used to sit on a band washed in the temperature's hue, and the
  shell does not draw an app under the status bar, so the wash ended in a hard
  line across the top of the screen. The temperature's colour is in the hour
  strip and the week's bars instead, where it is read against something.
- **The strip** is the next twenty-four hours, the one you are in marked both
  by a pill and by the ink of its label. A chance of rain appears above ten per
  cent and not below, because a column of "0%" is twenty-four numbers nobody
  reads.
- **The week** is seven bars on **one scale**: the coldest and warmest of the
  whole week are the two ends of every row, so a bar further right is a warmer
  day. Per-row scaling would draw every day identically and mean nothing. The
  colour is decoration — both ends of each bar carry their own number.
- **The symbols are drawn**, not loaded: eleven of them out of rectangles and
  circles — three with a night half, so fourteen pictures — at whatever size
  they are asked for. Adwaita ships weather
  symbolics and they are drawn on a 16px canvas, where the hero here is 84.
  Rectangles rather than a `Canvas` for Vitals' reason — thirty-two of these
  are on screen at once, and a rectangle repaints nothing when nothing changed.

Nothing carries its meaning by colour alone. Roughly one man in twelve cannot
tell this app's green from its red, so every temperature is written as well as
tinted, and a wet hour says what per cent it is.

## The clock is the forecast's, not the phone's

Every time on the screen — the hours in the strip, sunrise, sunset, which day
is today — is the clock **where the weather is**. That is the whole reason the
request asks for `timeformat=unixtime`: Open-Meteo's default sends naive local
strings like `2026-09-15T14:00` with the offset reported separately, and then
a phone in Berlin reading Denver's forecast has to work out which of the two
clocks each string is on. As seconds it is arithmetic — the wire is UTC, the
offset comes with it, and the local wall clock is `t + offset` read in UTC.

The places page is where that stops being a claim: each town carries its own
time under its temperature, which is also the most useful thing a list of four
towns can say.

## Where you are

The first row on the places page is the town this connection's address is in,
and on a first run it is the screen the app opens on, rather than a search
field over "Nowhere yet". It comes from [GeoJS](https://www.geojs.io), which
answers over HTTPS with no key and no account, and names the country in words —
ipinfo, asked the same question, answers `"DE"`.

**It is a town, not a street.** An address says where the network is rather
than where the phone is: on a home connection that is usually the right town,
and on mobile data it can be wherever the carrier's gateway happens to be.
There is no GPS here. The name carries a pin in the title bar, so a town that
was looked up never reads as one that was chosen.

- It is asked **only while the answer would be on screen** — the phone's own
  place is the one showing, or the places page is open — and then at most once
  a quarter of an hour, which is how long a change of network takes to reach
  the screen.
- **A refresh** on the phone's own place asks the two questions in order, where
  and then the weather there, and the forecast waits for the first answer
  rather than fetching the last town's.
- **A country with no town** is refused rather than forecast. The middle of
  Germany is not anywhere anybody is.
- **The answer is kept in `forecast.json`**, beside its week, and not in
  `places.json` — nobody chose it.
- **Show where I am**, at the bottom of the places page, switches it off. Off
  is forgotten, not hidden: the town leaves the screen at once and the disk at
  the next write, an answer already on its way is dropped unread, and nothing
  is asked until the box is ticked again. The setting is read off the disk
  before the first lookup, not after it, so a phone that said no never sends
  one at startup.

That makes the whole of the network behaviour:

- one `GET` of Open-Meteo's forecast endpoint per place being looked at, at
  most four times an hour, and only while the window is on the screen;
- one `GET` of GeoJS while the phone's own place is on the screen, at most four
  times an hour, and none at all with **Show where I am** off;
- one `GET` of Open-Meteo's geocoder while somebody is typing a town, three
  hundred and fifty milliseconds after they stop;
- nothing else, ever. No key, no account, no identifier — Open-Meteo's free
  tier answers unauthenticated requests and asks for non-commercial use. The
  lookup does send GeoJS the one thing it is being asked about, the
  connection's address, which every request to anybody sends.

A refresh that fails leaves the forecast on screen, says `Not updating · 4 min
ago` in the header, and backs off — a minute, then two and a half, then five,
then ten, and ten minutes flat when the answer was a rate limit.

## The files

`~/.local/share/moarchy-weather/`, or `$MOARCHY_WEATHER_DIR`.

`places.json` is the only thing here a person made — the towns, which one is on
screen, which scale of degrees, and whether to look up where the phone is.
`forecast.json` is the last answer about each of them, and the town the last
lookup found, and is disposable by definition; it exists so that opening the
app in a tunnel shows this morning's forecast rather than a spinner.

`current` is a place's id, or `"here"` for the phone's own place — not that
place's coordinates, because they change when the phone does. A file with no
`locate` in it is read as `true`.

```json
{
 "schema": 1,
 "units": "metric",
 "locate": true,
 "current": "here",
 "places": [
  {"id": "52.524,13.411", "name": "Berlin", "admin": "Berlin",
   "country": "Germany", "lat": 52.524, "lon": 13.411}
 ]
}
```

The id is coordinates to three places — about a hundred metres, closer than any
model resolves — rather than the geocoder's own number, because it is also the
key the cache is stored under and a place typed in off a map has no number.

The cache is written **when the window stops being mapped**, which on this
phone is the event immediately before the app is reclaimed. Not on every
fetch: that is a write onto flash every quarter of an hour, for a file whose
entire purpose is the next cold start.

Both files are read through the kit's `JsonFile`, so one that has been
truncated is moved aside as `*.broken-<epoch>.json` rather than overwritten,
and a forecast off the disk is read exactly as strictly as one off the wire.

## Install on the phone

```sh
plugins/moarchy.weather/install-on-device.sh
```

That copies the plugin into `~/.config/omarchy/plugins/moarchy.weather`,
asks the shell to validate and enable it, writes a `.desktop` entry so the
drawer can summon it, and restarts the shell. Then tap **Weather** in the
drawer.

```sh
omarchy-shell shell toggle moarchy.weather
omarchy-shell weather refresh        # also: place, temperature, toggle
```

## Run it without the shell

`shell.qml` is the same app as its own Quickshell process, for a machine that
has Quickshell and none of omarchy:

```sh
plugins/moarchy.weather/run-local.sh          # vendors ui/, then quickshell -p

# ...or with four towns and a week of made-up weather, and no network at all:
MOARCHY_WEATHER_DIR=/tmp/w plugins/moarchy.weather/demo.py
MOARCHY_WEATHER_DIR=/tmp/w MOARCHY_WEATHER_OFFLINE=1 \
  plugins/moarchy.weather/run-local.sh
```

The plugin host is the only thing that goes missing, and everything that needed
it was already optional: `shell` stays null so the summon-and-return calls are
skipped, `colors.toml` is not staged so the built-in palette stands, and
closing the window ends the process instead of hiding a surface the shell would
otherwise keep alive.

## Checks

```sh
scripts/qml-check.sh moarchy.weather
scripts/qml-shot.sh moarchy.weather     # the pictures above
```

qmllint with every warning fatal, then the two test files, then a real run at
360×720 that fails on any QML diagnostic.

What the tests cannot reach was checked by hand against the live API, in the
container, under the compositor the phone runs: a place with no forecast
fetches one and draws it, typing five letters of a town lists it, and closing
the window writes the week to the disk. Two of those three had never run
outside a fixture, and the first of them is where the fifteen-minute bug
above came from. The address lookup was checked the same way: a first run with
nothing on the disk asked GeoJS, got a town back, and drew that town's
forecast.

The tests are worth more here than the drawing is, because every answer in them
predates the app: a WMO code means what WMO 4677 says it means, 06:41 in Berlin
is 04:41Z whatever the phone is set to, and a week's coldest and warmest are
arithmetic. `tst_forecast.qml` is that half — including the case the live API
found and the fixture had not, that `current` is a *fifteen-minute* observation
and so is never on the hour. `tst_store.qml` is the two files after somebody
has edited them by hand, and where the screen goes when the lookup is switched
on and off.

| variable | what it does |
|---|---|
| `MOARCHY_WEATHER_DIR` | where the places and the cache are kept |
| `MOARCHY_WEATHER_OFFLINE` | draw the cache and never open a socket |
| `MOARCHY_WEATHER_UNITS` | `metric` or `imperial`, for one run |
| `MOARCHY_WEATHER_PAGE` | `places` to open on the places page |
| `MOARCHY_WEATHER_SEARCH` | open the places page with this typed, and look it up — the one screen a harness cannot reach on its own, because a headless compositor has no pointer to tap the field with. It needs the network, so it is not in `shots.sh` |
| `MOARCHY_WEATHER_NOW` | pin the clock, so two pictures agree |
| `MOARCHY_WEATHER_QUIT_AFTER` | quit after N seconds, for headless runs |

## What is not here

No radar, no air quality, no pollen, no warnings, no second source, no widget
on the bar and no notification. The first four are the Breezy Weather row and
are the reason it stays open; air quality is the one of them Open-Meteo would
answer today, on a second endpoint, and it is not here because nobody asked for
it yet.

## Licence

MIT. Forecasts from [Open-Meteo](https://open-meteo.com), whose data is
CC-BY-4.0.
