#!/usr/bin/env python3
"""Where the phone is, three more places, and a week of weather for each.

The plugins in this repository that talk to a network have the same problem
when somebody wants to look at them: the screen is only interesting once an
answer has arrived, and an answer that arrives is different every time it does.
The GTK apps solve it with a `demo.py` that writes their store by hand, and the
screenshot harness runs it before it photographs anything. This is that file
for a plugin rather than an app -- same idea, same place on the disk.

    MOARCHY_WEATHER_DIR=/tmp/w plugins/moarchy.weather/demo.py
    MOARCHY_WEATHER_DIR=/tmp/w MOARCHY_WEATHER_OFFLINE=1 \\
        plugins/moarchy.weather/run-local.sh

Nothing here is random and nothing is fetched. The temperatures are a cosine
with its peak at three in the afternoon, the codes are a fixed list per place,
and the times are anchored to the hour this runs in -- because a fixture dated
last Tuesday draws an empty screen, the app having correctly dropped every hour
of it as past.
"""

from __future__ import annotations

import json
import math
import os
import time
from pathlib import Path

HOURS = 48
DAYS = 7

# name, admin, country, lat, lon, utc offset, night low, day high, the codes
# the week runs through.
#
# HERE is what the address lookup answered, as GeoJS words it -- "State of
# Berlin", and the coordinates it sends rather than the geocoder's -- and it
# goes in forecast.json, which is where the app keeps an answer nobody chose.
HERE = ("Berlin", "State of Berlin", "Germany", 52.4928, 13.4039, 7200, 11.0, 21.0,
        [2, 3, 61, 80, 1, 0, 2])

PLACES = [
    ("Reykjavík", "Capital Region", "Iceland", 64.146, -21.942, 0, 2.0, 8.0,
     [61, 80, 71, 3, 45, 2, 63]),
    ("Cairo", "Cairo", "Egypt", 30.044, 31.236, 10800, 23.0, 36.0,
     [0, 0, 1, 0, 2, 0, 0]),
    ("Kyoto", "Kyoto", "Japan", 35.012, 135.768, 32400, 18.0, 27.0,
     [3, 95, 63, 2, 1, 0, 80]),
]

# Which codes are wet, and how likely this fixture says that is. The app draws
# nothing under ten per cent, so a dry day has to be genuinely dry or every
# column carries a number.
WET = {51: 55, 53: 65, 55: 80, 61: 70, 63: 80, 65: 90, 71: 60, 73: 70,
       75: 80, 80: 45, 81: 60, 82: 75, 85: 55, 86: 65, 95: 70, 96: 80, 99: 85}


def place_id(lat: float, lon: float) -> str:
    return f"{lat:.3f},{lon:.3f}"


def temperature(local_hour: int, low: float, high: float) -> float:
    """A day that is coldest at five in the morning and warmest at three."""
    mid = (low + high) / 2
    swing = (high - low) / 2
    return round(mid + swing * math.cos((local_hour - 15) / 24 * 2 * math.pi), 1)


def forecast_for(place, now: int) -> dict:
    _, _, _, _, _, offset, low, high, codes = place
    hour0 = now - now % 3600
    local_midnight = ((now + offset) // 86400) * 86400 - offset

    hourly = []
    for i in range(HOURS):
        when = hour0 + i * 3600
        local_hour = ((when + offset) % 86400) // 3600
        day_index = (when + offset) // 86400 - (local_midnight + offset) // 86400
        code = codes[int(day_index) % len(codes)]
        # The hourly code is the day's, except that a shower is not raining all
        # night: the odd hours of a shower day are the sky it showers out of.
        if code in (80, 81, 82) and i % 3:
            code = 2
        hourly.append({
            "time": when,
            "temp": temperature(local_hour, low, high),
            "code": code,
            "pop": WET.get(code, 0),
            "day": 6 <= local_hour < 20,
        })

    daily = []
    for i in range(DAYS):
        midnight = local_midnight + i * 86400
        code = codes[i % len(codes)]
        drift = (i - 3) * 0.7
        daily.append({
            "time": midnight,
            "code": code,
            "high": round(high + drift, 1),
            "low": round(low + drift, 1),
            "pop": WET.get(code, 0),
            "sunrise": midnight + 6 * 3600 + 41 * 60,
            "sunset": midnight + 19 * 3600 + 52 * 60,
        })

    current = dict(hourly[0])
    current.update({
        "feels": round(current["temp"] - 1.3, 1),
        "humidity": 62,
        "precip": 0.0,
        "wind": 12.6,
        "from": 315,
    })
    return {"offset": offset, "zone": "", "current": current,
            "hourly": hourly, "daily": daily}


def main() -> None:
    directory = Path(os.environ.get("MOARCHY_WEATHER_DIR")
                     or Path.home() / ".local/share/moarchy-weather")
    directory.mkdir(parents=True, exist_ok=True)
    now = int(os.environ.get("MOARCHY_WEATHER_NOW") or time.time())

    def record(p) -> dict:
        return {"id": place_id(p[3], p[4]), "name": p[0], "admin": p[1],
                "country": p[2], "lat": p[3], "lon": p[4]}

    (directory / "places.json").write_text(json.dumps({
        "schema": 1,
        "units": os.environ.get("MOARCHY_WEATHER_UNITS") or "metric",
        "locate": True,
        "current": "here",
        "places": [record(p) for p in PLACES],
    }, indent=1) + "\n", encoding="utf-8")

    # Found now, so an offline run does not think the answer is stale -- not
    # that it would ask again, but the pictures should not depend on that.
    (directory / "forecast.json").write_text(json.dumps({
        "schema": 1,
        "here": {**record(HERE), "found": now},
        "forecasts": {
            place_id(p[3], p[4]): {"fetched": now, "forecast": forecast_for(p, now)}
            for p in [HERE, *PLACES]
        },
    }, indent=1) + "\n", encoding="utf-8")

    print(f"wrote {directory}/places.json and forecast.json")


if __name__ == "__main__":
    main()
