# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# demo.py writes a call log and a contacts file beside it, so Recents and
# Contacts have people in them. The call screens are staged: there is no modem
# in the container, so MOARCHY_PHONE_FAKE_CALL puts one call on the screen in
# the state named and nothing is sent anywhere.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot keypad MOARCHY_PHONE_TYPED="+44 7700 900"
shot recents MOARCHY_PHONE_PAGE=recents
shot contacts MOARCHY_PHONE_PAGE=contacts
shot ringing MOARCHY_PHONE_FAKE_CALL=ringing
shot dialing MOARCHY_PHONE_FAKE_CALL=dialing MOARCHY_PHONE_FAKE_NUMBER="+49 152 90999999"
shot active MOARCHY_PHONE_FAKE_CALL=active
shot tones MOARCHY_PHONE_FAKE_CALL=keypad
shot waiting MOARCHY_PHONE_FAKE_CALL=waiting

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night-recents MOARCHY_PHONE_PAGE=recents "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-keypad MOARCHY_PHONE_TYPED="+44 7700 900" "THEME=$THEMES/catppuccin-latte/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-ringing MOARCHY_PHONE_FAKE_CALL=ringing "THEME=$THEMES/catppuccin-latte/colors.toml"
shot square-active MOARCHY_PHONE_FAKE_CALL=active CORNERS=square
