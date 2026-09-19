# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# Offline throughout, and that is not a limitation of the container: demo.py
# writes a market seconds old, the window only fetches when its prices are
# older than a minute, and a tracker photographed against the real CoinGecko
# would disagree with itself between one shot and the next.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot market
shot starred MOARCHY_COINS_PAGE=starred
shot search MOARCHY_COINS_SEARCH=sol

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "THEME=$THEMES/catppuccin-latte/colors.toml"
