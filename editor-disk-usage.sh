#!/usr/bin/env bash
# Bash 3.2+ (including macOS's bundled Bash), GNU/BSD du. Read-only.
# Measures allocated space in known editor paths; not a package dependency audit.
set -u
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage: bash editor-disk-usage.sh [--vscode-path PATH] [--nvim-path PATH]
Reports application + user data usage for VS Code and Neovim on macOS/Linux.
Repeat path options to include custom installations, profiles or NVIM_APPNAMEs.
Totals exclude shared libraries, external language servers and remote machines.
EOF
}
vs_extra=(); nv_extra=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --vscode-path|--nvim-path)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      if [ "$1" = --vscode-path ]; then vs_extra+=("$2"); else nv_extra+=("$2"); fi
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$(uname -s)" in Darwin|Linux) ;; *) echo 'Requires macOS or Linux.' >&2; exit 1 ;; esac

# Resolve directory aliases and file symlinks without GNU realpath/readlink -f.
canonical() {
  local p="$1" target count=0
  while [ -L "$p" ]; do
    count=$((count + 1)); [ "$count" -le 40 ] || return 1
    target=$(readlink "$p") || return 1
    case "$target" in /*) p="$target" ;; *) p="$(dirname "$p")/$target" ;; esac
  done
  if [ -d "$p" ]; then (cd "$p" && pwd -P)
  else printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"; fi
}
paths=(); labels=()
add() {
  local p i
  [ -e "$2" ] || return 0
  p=$(canonical "$2") || return 0
  # Count each directory once, even if a candidate is inside another candidate.
  for i in "${!paths[@]}"; do
    case "$p/" in "${paths[$i]}/"*) return 0 ;; esac
  done
  for i in "${!paths[@]}"; do
    case "${paths[$i]}/" in "$p/"*) unset 'paths[i]' 'labels[i]' ;; esac
  done
  # Appending via += handles holes left by removing overlapping paths.
  paths+=("$p"); labels+=("$1")
}
human() { awk -v k="$1" 'BEGIN { if(k>=1048576) printf "%.2f GiB",k/1048576; else printf "%.1f MiB",k/1024 }'; }
report() {
  local i k total=0 result
  printf '\n%s\n' "$1"
  for i in "${!paths[@]}"; do
    # -k gives KiB on both BSD and GNU du; errors remain visible on stderr.
    result=$(du -sk "${paths[$i]}"); k=$(printf '%s\n' "$result" | awk 'NR==1 {print $1}')
    case "$k" in ''|*[!0-9]*) printf '  unreadable: %s\n' "${paths[$i]}"; continue ;; esac
    total=$((total + k))
    printf '  %10s  %-16s %s\n' "$(human "$k")" "${labels[$i]}" "${paths[$i]}"
  done
  printf '  TOTAL: %s\n' "$(human "$total")"
  [ "${#paths[@]}" -gt 0 ] || printf '  No known paths found; use a --*-path option.\n'
  TOTAL_KIB=$total
}

config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
cache=${XDG_CACHE_HOME:-$HOME/.cache}
state=${XDG_STATE_HOME:-$HOME/.local/state}

for p in /Applications/Visual\ Studio\ Code.app "$HOME/Applications/Visual Studio Code.app" \
  /usr/share/code /usr/lib/code /opt/visual-studio-code /opt/vscode /snap/code/current; do add app "$p"; done
exe=$(command -v code 2>/dev/null || true)
if [ -n "$exe" ] && [ -e "$exe" ]; then
  exe=$(canonical "$exe")
  # Native VS Code distributions keep bin/code next to resources/app.
  root=$(dirname "$(dirname "$exe")")
  if [ -d "$root/resources/app" ]; then add app "$root"; else add launcher "$exe"; fi
fi
add extensions "$HOME/.vscode"
add config/data "$config/Code"
add cache "$cache/Code"
add config/data "$HOME/Library/Application Support/Code"
add cache "$HOME/Library/Caches/com.microsoft.VSCode"
add cache "$HOME/Library/Caches/com.microsoft.VSCode.ShipIt"
add saved-state "$HOME/Library/Saved Application State/com.microsoft.VSCode.savedState"
for p in "$HOME/.local/share/flatpak/app/com.visualstudio.code" /var/lib/flatpak/app/com.visualstudio.code; do add flatpak-app "$p"; done
add flatpak-data "$HOME/.var/app/com.visualstudio.code"
add snap-data "$HOME/snap/code"
for p in "${vs_extra[@]}"; do add custom "$p"; done
report 'VS Code (stable)'; vs_total=$TOTAL_KIB

paths=(); labels=()
exe=$(command -v nvim 2>/dev/null || true)
if [ -n "$exe" ] && [ -e "$exe" ]; then
  exe=$(canonical "$exe"); add binary "$exe"
  add runtime "$(dirname "$(dirname "$exe")")/share/nvim"
fi
add runtime /usr/share/nvim
add runtime /usr/local/share/nvim
[ -z "${VIMRUNTIME:-}" ] || add runtime "$VIMRUNTIME"
app=${NVIM_APPNAME:-nvim}
add config "$config/$app"
add plugins/data "$data/$app"
add cache "$cache/$app"
add state "$state/$app"
for p in "${nv_extra[@]}"; do add custom "$p"; done
report "Neovim ($app)"; nv_total=$TOTAL_KIB

printf '\nVS Code: %s | Neovim: %s\n' "$(human "$vs_total")" "$(human "$nv_total")"
if [ "$nv_total" -gt 0 ] && [ "$vs_total" -gt 0 ]; then
  awk -v v="$vs_total" -v n="$nv_total" 'BEGIN {printf "VS Code / Neovim: %.2fx\n",v/n}'
fi
printf '\nAllocated space; known paths only. Shared dependencies and external tools excluded.\n'
printf 'Flatpak/Snap paths may include multiple retained versions. Permission errors mean partial totals.\n'

