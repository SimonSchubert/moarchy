# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# demo.py writes a week of mail, the folder list and two parsed bodies -- a
# plain message with a quote, a link and a PDF, and a newsletter that is mostly
# links and pictures -- so every screen here has the thing on it that is hard
# to get right.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot inbox
shot message MOARCHY_MAIL_OPEN=231
shot newsletter MOARCHY_MAIL_OPEN=229
shot reply MOARCHY_MAIL_OPEN=231 MOARCHY_MAIL_REPLY=all
shot compose MOARCHY_MAIL_PAGE=compose "MOARCHY_MAIL_TO=Jonas Weber <jonas@example.com>, ha" \
  MOARCHY_MAIL_SUBJECT=Copenhagen MOARCHY_MAIL_FOCUS=to
shot folders MOARCHY_MAIL_PAGE=folders
shot unsent MOARCHY_MAIL_EXTRAS=1
shot menu MOARCHY_MAIL_MENU=230
shot setup MOARCHY_MAIL_NOACCOUNT=1 MOARCHY_MAIL_PAGE=setup "MOARCHY_MAIL_TYPED=Ada Okonkwo|ada@example.org|correct horse"
shot setup-refused MOARCHY_MAIL_NOACCOUNT=1 MOARCHY_MAIL_PAGE=setup \
  "MOARCHY_MAIL_TYPED=Ada Okonkwo|ada@gmail.com|correct horse" \
  "MOARCHY_MAIL_NOTE=Gmail needs an app password, made at myaccount.google.com/apppasswords." \
  "MOARCHY_MAIL_ERROR=This account wants an app password, which is made in the provider's security settings, rather than the account's own password."

[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-inbox "THEME=$THEMES/catppuccin-latte/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte-newsletter MOARCHY_MAIL_OPEN=229 "THEME=$THEMES/catppuccin-latte/colors.toml"
[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night-message MOARCHY_MAIL_OPEN=231 "THEME=$THEMES/tokyo-night/colors.toml"
shot square-inbox CORNERS=square
