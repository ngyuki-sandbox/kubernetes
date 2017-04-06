#!/bin/bash

set -eu
cd -- "$(dirname -- "$0")/files"
export LANG=C

usage(){
  cat <<EOS | sed 's/    //'

    Usage: $0 [-d|-n|-f]

    Options:
      -d  diff
      -n  dry run
      -f  rsync
EOS
  exit 1
}

declare -A flags

while getopts dnf OPT; do
  case "$OPT" in
    d) flags[$OPT]=1 ;;
    f) flags[$OPT]=1 ;;
    n) flags[$OPT]=1 ;;
    *) usage  ;;
  esac
done

shift $((OPTIND - 1))

files=()

for f in "$@"; do
  f=$(realpath -- $f)
  files+=("${f#/}")
done
if [[ "${#files[@]}" -eq 0 ]]; then
  files=("")
fi

if [[ -n "${flags[d]-}" ]]; then
  for f in "${files[@]}"; do
    diff -r -u "/$f" "./$f" | grep -v ^Only | colordiff
  done
elif [[ -n "${flags[n]-}" ]]; then
  for f in "${files[@]}"; do
    rsync -rcin "./$f" "/$f"
  done
elif [[ -n "${flags[f]-}" ]]; then
  for f in "${files[@]}"; do
    rsync -rci "./$f" "/$f"
  done
else
  usage
fi
