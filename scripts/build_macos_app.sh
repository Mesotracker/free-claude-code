#!/bin/sh
set -eu

FCC_MACOS_BUNDLE_ID="io.github.alishahryar1.free-claude-code"
FCC_MACOS_OWNER_FILE=".free-claude-code-owner"
FCC_MACOS_BUNDLE_NAME="Free Claude Code.app"

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
packaged_icon="$repository_root/src/free_claude_code/assets/app-icon.icns"

dest_directory=$PWD
desktop_command=""
icon_path=""
dry_run=0

show_usage() {
    cat <<'USAGE'
Usage: build_macos_app.sh [options]

Builds the Contents folder of the Free Claude Code macOS application bundle,
the same bundle scripts/install.sh installs into ~/Applications.

Options:
  --dest DIR             Parent directory for the bundle (default: current directory).
  --fcc-desktop PATH     Absolute path of the fcc-desktop command the launcher runs.
                         Omit it to build a launcher that finds fcc-desktop at launch.
  --icon PATH            Icon file copied to Contents/Resources/AppIcon.icns
                         (default: the packaged FCC app icon).
  --dry-run              Print the planned actions without writing files.
  --help                 Show this help text.

The bundle folder is named "Free Claude Code.app". Rename or move that folder to
place the bundle, and keep its executable bit when copying it to another machine.
USAGE
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

step() {
    printf '\n==> %s\n' "$1"
}

quote_arg() {
    case "$1" in
        *[!A-Za-z0-9_./:@%+=,-]*|"")
            escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
            printf '"%s"' "$escaped"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

print_command() {
    printf '+'
    for arg in "$@"; do
        printf ' '
        quote_arg "$arg"
    done
    printf '\n'
}

run() {
    print_command "$@"
    if [ "$dry_run" -eq 0 ]; then
        "$@"
    fi
}

shell_quote() {
    escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
    printf "'%s'" "$escaped"
}

bundle_is_fcc_owned() {
    app_dir=$1
    owner_file="$app_dir/Contents/$FCC_MACOS_OWNER_FILE"
    [ -d "$app_dir" ] &&
        [ ! -L "$app_dir" ] &&
        [ -f "$owner_file" ] &&
        [ "$(cat "$owner_file")" = "$FCC_MACOS_BUNDLE_ID" ]
}

write_info_plist() {
    cat > "$1" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Free Claude Code</string>
    <key>CFBundleExecutable</key>
    <string>fcc-desktop</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.alishahryar1.free-claude-code</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Free Claude Code</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
}

write_pinned_launcher() {
    {
        printf '%s\n' '#!/bin/sh'
        printf 'exec %s\n' "$(shell_quote "$desktop_command")"
    } > "$1"
}

write_resolving_launcher() {
    cat > "$1" <<'LAUNCHER'
#!/bin/sh
# Locate the installed fcc-desktop command. Finder starts this bundle with a
# minimal environment, so the command is resolved from known install locations.
set -u

fail_launch() {
    message='Free Claude Code could not find the fcc-desktop command. Run the Free Claude Code installer, or set FCC_DESKTOP_COMMAND to the full path of that command.'
    printf '%s\n' "$message" >&2
    if [ -n "${HOME:-}" ] && mkdir -p "$HOME/Library/Logs" 2>/dev/null; then
        printf '%s\n' "$message" >>"$HOME/Library/Logs/free-claude-code-desktop.log" 2>/dev/null || :
    fi
    if command -v osascript >/dev/null 2>&1; then
        osascript -e "display alert \"Free Claude Code\" message \"$message\"" >/dev/null 2>&1 || :
    fi
    exit 1
}

fcc_desktop=""
if [ -n "${FCC_DESKTOP_COMMAND:-}" ] && [ -x "$FCC_DESKTOP_COMMAND" ]; then
    fcc_desktop="$FCC_DESKTOP_COMMAND"
else
    for directory in "${UV_TOOL_BIN_DIR:-}" "${HOME:-}/.local/bin" /opt/homebrew/bin /usr/local/bin; do
        [ -n "$directory" ] || continue
        if [ -x "$directory/fcc-desktop" ]; then
            fcc_desktop="$directory/fcc-desktop"
            break
        fi
    done
fi
if [ -z "$fcc_desktop" ] && command -v fcc-desktop >/dev/null 2>&1; then
    fcc_desktop=$(command -v fcc-desktop)
fi
if [ -z "$fcc_desktop" ]; then
    fail_launch
fi
exec "$fcc_desktop"
LAUNCHER
}

resolve_icon_path() {
    if [ -n "$icon_path" ]; then
        [ -f "$icon_path" ] || fail "No icon file exists at $icon_path."
        return 0
    fi
    icon_path=$packaged_icon
    [ -f "$icon_path" ] ||
        fail "The packaged FCC app icon is missing from $icon_path. Pass --icon PATH."
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dest)
                shift
                [ "$#" -gt 0 ] || fail "--dest requires a directory."
                dest_directory=$1
                ;;
            --fcc-desktop)
                shift
                [ "$#" -gt 0 ] || fail "--fcc-desktop requires a path."
                desktop_command=$1
                ;;
            --icon)
                shift
                [ "$#" -gt 0 ] || fail "--icon requires a path."
                icon_path=$1
                ;;
            --dry-run)
                dry_run=1
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                show_usage >&2
                fail "unknown option: $1"
                ;;
        esac
        shift
    done
}

parse_args "$@"
resolve_icon_path

app_dir="$dest_directory/$FCC_MACOS_BUNDLE_NAME"
contents_dir="$app_dir/Contents"
owner_file="$contents_dir/$FCC_MACOS_OWNER_FILE"
executable_dir="$contents_dir/MacOS"
executable_path="$executable_dir/fcc-desktop"
resources_dir="$contents_dir/Resources"
destination_icon="$resources_dir/AppIcon.icns"

if [ -e "$app_dir" ] || [ -L "$app_dir" ]; then
    bundle_is_fcc_owned "$app_dir" ||
        fail "An app not managed by Free Claude Code already exists at $app_dir. Move it, then rerun this script."
fi

step "Building $app_dir"
run mkdir -p "$executable_dir" "$resources_dir"
if [ "$dry_run" -eq 0 ]; then
    printf '%s\n' "$FCC_MACOS_BUNDLE_ID" > "$owner_file"
    write_info_plist "$contents_dir/Info.plist"
    if [ -n "$desktop_command" ]; then
        write_pinned_launcher "$executable_path"
    else
        write_resolving_launcher "$executable_path"
    fi
    chmod +x "$executable_path"
    cp "$icon_path" "$destination_icon"
else
    printf '+ write %s, %s, and %s\n' "$owner_file" "$contents_dir/Info.plist" "$executable_path"
    print_command cp "$icon_path" "$destination_icon"
fi

if [ "$dry_run" -eq 1 ]; then
    printf '\nDry run complete. No changes were made.\n'
else
    printf '\nBuilt %s\n' "$app_dir"
    printf 'Open it from Finder, or copy the whole %s folder to another Mac.\n' "$FCC_MACOS_BUNDLE_NAME"
fi
