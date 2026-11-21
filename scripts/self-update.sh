#!/usr/bin/env bash
# Bundled into the app and invoked by UpdateManager.
#   self-update.sh build   <repo-url> <branch> <source-dir>   -> prints APP_PATH=<built app>
#   self-update.sh install <new-app> <target-app> <pid>       -> waits for pid, swaps bundle, relaunches
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"
export GIT_TERMINAL_PROMPT=0

mode="${1:-}"

case "$mode" in
build)
    repo="$2"
    branch="$3"
    src="$4"

    if [ -d "$src/.git" ]; then
        echo "Fetching $branch…"
        git -C "$src" remote set-url origin "$repo"
        git -C "$src" fetch --prune origin "$branch"
        git -C "$src" checkout -B "$branch" "origin/$branch"
        git -C "$src" reset --hard "origin/$branch"
        git -C "$src" clean -fdx -e .build
    else
        echo "Cloning $repo…"
        rm -rf "$src"
        mkdir -p "$(dirname "$src")"
        git clone --branch "$branch" "$repo" "$src"
    fi

    UPDATE_BRANCH="$branch" bash "$src/scripts/build.sh"
    echo "APP_PATH=$src/build/DynamicIsland.app"
    ;;

install)
    new_app="$2"
    target="$3"
    pid="$4"

    case "$target" in
    *.app) ;;
    *) echo "Refusing to replace non-app path: $target" >&2; exit 1 ;;
    esac
    [ -d "$new_app" ] || { echo "Built app not found: $new_app" >&2; exit 1; }

    echo "$(date) Waiting for PID $pid to exit…"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done

    staging="${target%.app}.updating.app"
    rm -rf "$staging"
    ditto "$new_app" "$staging"
    rm -rf "$target"
    mv "$staging" "$target"

    echo "$(date) Installed to $target, relaunching."
    open "$target"
    ;;

*)
    echo "Usage: $0 build|install …" >&2
    exit 2
    ;;
esac
