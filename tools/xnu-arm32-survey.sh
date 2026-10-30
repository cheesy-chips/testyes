#!/bin/bash
# SPDX-License-Identifier: MIT
# Which of Apple's open-source XNU releases carry 32-bit ARM code, and in what state?
#
# usage: tools/xnu-arm32-survey.sh [TAG ...]
#   default: the last release of each line from OS X 10.5 (xnu-1228) to iOS 16.5 (xnu-8796)
#   env XNU_URL   where to fetch from (default: github.com/apple-oss-distributions/xnu; a local clone
#                 that has the tags will do: XNU_URL=file:///path/to/xnu)
#
# Only the lists of file names are fetched (git's blob:none filter), plus two small files per tag, into a
# temporary directory that is removed at the end. Nothing is written to the repository. This is how the
# table in docs/s4-armv7-port.md was made; it needs git and a route to the remote.
#
# columns:  files      files in the release
#           osfmk/arm  files under osfmk/arm/  (the 32-bit machine layer, shared with 64-bit in later releases)
#           osfmk/arm64
#           locore.s   whether osfmk/arm/locore.s exists: the 32-bit exception vectors. When it is gone,
#                      so is the ability to build a 32-bit kernel from that release.
#           arm cfg    SUPPORTED_ARM_MACHINE_CONFIGS in makedefs/MakeInc.def ("-": not there; NONE: no
#                      32-bit machine can be built without adding one)
#           arm64 cfg  the same for 64-bit (BCM2837 is the generic machine this project builds)
#           board_cfg  lines in pexpert/pexpert/arm/board_config.h (a stub of 9 lines means the board
#                      definitions were taken out of the public release)
set -u
URL=${XNU_URL:-https://github.com/apple-oss-distributions/xnu.git}
DEFAULT_TAGS="xnu-1228.15.4 xnu-1456.1.26 xnu-1504.15.3 xnu-1699.32.7 xnu-2050.48.11 xnu-2422.115.4
xnu-2782.40.9 xnu-3248.60.10 xnu-3789.70.16 xnu-4570.71.2 xnu-4903.270.47 xnu-6153.141.1 xnu-7195.141.2
xnu-8019.80.24 xnu-8020.140.41 xnu-8792.81.2 xnu-8796.121.2"
case "${1:-}" in -h|--help) sed -n '3,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;; esac
TAGS=${*:-$DEFAULT_TAGS}

command -v git >/dev/null || { echo "xnu-arm32-survey: git is needed" >&2; exit 1; }
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp"
git -C "$tmp" remote add origin "$URL"

printf '%-18s %6s %9s %11s %9s  %-10s %-26s %s\n' tag files osfmk/arm osfmk/arm64 locore.s "arm cfg" "arm64 cfg" board_cfg
for t in $TAGS; do
	# the file list only; a server that cannot filter (a local clone) is asked for the whole tag
	git -C "$tmp" fetch -q --depth 1 --filter=blob:none origin "refs/tags/$t:refs/tags/$t" 2>/dev/null ||
	git -C "$tmp" fetch -q --depth 1 origin "refs/tags/$t:refs/tags/$t" 2>/dev/null || {
		printf '%-18s (cannot fetch this tag from %s)\n' "$t" "$URL"; continue; }
	list=$tmp/list
	git -C "$tmp" ls-tree -r --name-only "$t" > "$list"
	n=$(wc -l < "$list" | tr -d ' ')
	a=$(grep -c '^osfmk/arm/' "$list" || true)
	a64=$(grep -c '^osfmk/arm64/' "$list" || true)
	if grep -qx 'osfmk/arm/locore.s' "$list"; then loc=yes; else loc=no; fi
	def=$(git -C "$tmp" show "$t:makedefs/MakeInc.def" 2>/dev/null || true)
	armcfg=$(printf '%s\n' "$def" | sed -n 's/^SUPPORTED_ARM_MACHINE_CONFIGS[[:space:]]*=[[:space:]]*//p' | tail -n1)
	a64cfg=$(printf '%s\n' "$def" | sed -n 's/^SUPPORTED_ARM64_MACHINE_CONFIGS[[:space:]]*=[[:space:]]*//p' | tail -n1)
	if grep -qx 'pexpert/pexpert/arm/board_config.h' "$list"; then
		bc=$(git -C "$tmp" show "$t:pexpert/pexpert/arm/board_config.h" 2>/dev/null | wc -l | tr -d ' ')
	else
		bc=-
	fi
	printf '%-18s %6s %9s %11s %9s  %-10s %-26s %s\n' "$t" "$n" "$a" "$a64" "$loc" "${armcfg:--}" "${a64cfg:--}" "$bc"
done
