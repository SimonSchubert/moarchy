// Where the places come from, which is two files and neither of them ours.
import QtQuick
import QtTest
import "../Places.js" as Places

TestCase {
  name: "Places"

  readonly property string rs: String.fromCharCode(30)
  readonly property string us: String.fromCharCode(31)

  readonly property string germanDirs: '# This file is written by xdg-user-dirs-update\n'
    + 'XDG_DESKTOP_DIR="$HOME/Schreibtisch"\n'
    + 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
    + 'XDG_PICTURES_DIR="$HOME/Bilder"\n'
    + 'XDG_MUSIC_DIR="$HOME"\n'
    + 'XDG_VIDEOS_DIR=/mnt/media/Videos\n'
    + 'XDG_TEMPLATES_DIR="${HOME}/Vorlagen"\n'

  function test_a_phone_in_german_offers_bilder() {
    var dirs = Places.parseUserDirs(germanDirs, "/home/simon")
    compare(dirs.XDG_PICTURES_DIR, "/home/simon/Bilder")
    compare(dirs.XDG_DESKTOP_DIR, "/home/simon/Schreibtisch")
    compare(dirs.XDG_TEMPLATES_DIR, "/home/simon/Vorlagen")
    // Not every value is under home, and an absolute one is taken as it is.
    compare(dirs.XDG_VIDEOS_DIR, "/mnt/media/Videos")
    // A key pointing at the home directory itself is how xdg-user-dirs writes
    // "this folder is turned off", so it is not a place.
    compare(dirs.XDG_MUSIC_DIR, undefined)
  }

  function test_nothing_at_all_is_an_empty_answer_rather_than_a_failure() {
    compare(Object.keys(Places.parseUserDirs("", "/home/simon")).length, 0)
    compare(Object.keys(Places.parseUserDirs(null, "/home/simon")).length, 0)
    // A relative path is not usable and is not guessed at.
    compare(Object.keys(Places.parseUserDirs('XDG_PICTURES_DIR="Bilder"',
                                             "/home/simon")).length, 0)
  }

  function test_the_english_defaults_stand_when_the_file_is_not_there() {
    var wanted = Places.wanted("/home/simon", {})
    compare(wanted[0].path, "/home/simon/Downloads")
    compare(wanted[0].glyph, "folder-download-symbolic")
    var german = Places.wanted("/home/simon",
                              Places.parseUserDirs(germanDirs, "/home/simon"))
    compare(german[2].path, "/home/simon/Bilder")
  }

  readonly property string df: "Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "dev 1980000 0 1980000 0% /dev\n"
    + "tmpfs 2000000 1200 1998800 1% /run\n"
    + "/dev/mmcblk0p2 29000000 11600000 17400000 40% /\n"
    + "/dev/loop0 128 128 0 100% /snap/core\n"
    + "/dev/mmcblk0p1 500000 60000 440000 12% /boot\n"
    + "/dev/mmcblk1p1 62000000 31000000 31000000 50% /run/media/simon/SD CARD\n"
    + "/dev/mmcblk0p2 29000000 11600000 17400000 40% /\n"

  function test_only_the_volumes_somebody_put_something_on() {
    var volumes = Places.parseVolumes(df)
    compare(volumes.length, 2)
    // Not tmpfs, not /dev, not a loop device -- and not /boot, which is on a
    // real partition and is not a place.
    compare(volumes[0].path, "/")
    compare(volumes[0].label, "Filesystem")
    compare(volumes[0].glyph, "drive-harddisk-symbolic")
    // A mount point may have a space in it and df does not escape one, so it
    // is everything from the sixth column on.
    compare(volumes[1].path, "/run/media/simon/SD CARD")
    compare(volumes[1].label, "SD CARD")
    compare(volumes[1].glyph, "drive-removable-media-symbolic")
  }

  function test_the_blocks_are_read_as_bytes() {
    var volumes = Places.parseVolumes(df)
    // -P counts 1024-byte blocks whatever the filesystem's own block size is.
    compare(volumes[0].total, 29000000 * 1024)
    compare(volumes[0].free, 17400000 * 1024)
  }

  function test_the_probe_is_one_fork_with_two_halves() {
    var probe = Places.parseProbe("/home/simon/Downloads" + us
                                  + "/home/simon/Bilder" + us + rs + df)
    verify(probe.present["/home/simon/Downloads"])
    verify(probe.present["/home/simon/Bilder"])
    verify(!probe.present["/home/simon/Music"])
    compare(probe.volumes.length, 2)
  }

  function test_home_is_a_row_before_anything_has_been_asked() {
    // A places page with nothing on it and no way back to the one place
    // everybody wants would be worse than a page that is briefly one row.
    var rows = Places.rows("/home/simon", {}, null, "")
    compare(rows.length, 1)
    compare(rows[0].label, "Home")
    compare(rows[0].path, "/home/simon")
  }

  function test_only_the_folders_that_are_there_are_offered() {
    var probe = Places.parseProbe("/home/simon/Downloads" + us
                                  + "/home/simon/Pictures" + us + rs + df)
    var rows = Places.rows("/home/simon", {}, probe,
                           "/home/simon/.local/share/Trash")
    var labels = []
    for (var i = 0; i < rows.length; i++) labels.push(rows[i].label)
    compare(labels, ["Home", "Downloads", "Pictures", "Trash",
                     "Filesystem", "SD CARD"])
    // The trash row browses the files, not the directory with the info files
    // in it.
    compare(rows[3].path, "/home/simon/.local/share/Trash/files")
    verify(rows[5].volume)
    verify(rows[5].free > 0)
  }
}
