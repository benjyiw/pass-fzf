#!/usr/bin/env bash
# pass fzf - fuzzy-find an entry in the password store and copy it.
# Based on https://github.com/ficoos/pass-fzf by Saggi Mizrahi (MIT).
# Sourced by pass, which provides $PREFIX, $GPG, $GPG_OPTS, clip and die.
# shellcheck disable=SC2154

# The trailing slash follows a symlinked store.
function candidates() {
    local root="${PREFIX%/}" file
    find -L "$root/" -name '*.gpg' | while IFS= read -r file; do
        file="${file#"$root/"}"
        printf '%s\n' "${file%.gpg}"
    done
}

function candidate_selector_fzf() {
    query=$1
    candidates | fzf -q "$query" --select-1
}

function usage() {
    cat <<_EOF
Usage: $PROGRAM $COMMAND [-s] [-a] [-o] [-i] [-h] [query]
    Fuzzy-find a password store entry and copy its password to the clipboard.
    Nothing from the entry is printed unless -a is given.

    -s  Print the selected entry name and exit.
    -a  Also print the rest of the entry (everything after the password).
        Same as PASSWORD_STORE_FZF_SHOW_ALL=true.
    -o  Copy the OTP code instead of the password (requires pass-otp).
    -i  After copying the password, offer to copy the OTP code if the entry
        has an otpauth:// line. Same as PASSWORD_STORE_FZF_AUTO_OTP=true.
    -h  Show this help.
_EOF
    exit "${1:-1}"
}

function decrypt_entry() {
    local passfile="$PREFIX/$1.gpg"
    [ -f "$passfile" ] || die "Error: $1 is not in the password store."
    "$GPG" -d "${GPG_OPTS[@]}" "$passfile"
}

function print_rest() {
    case "$1" in
        *$'\n'*) printf '%s\n' "${1#*$'\n'}" ;;
    esac
}

# Match pass-otp, which ignores leading whitespace.
function is_otp_line() {
    case "${1#"${1%%[![:blank:]]*}"}" in
        otpauth://*) return 0 ;;
    esac
    return 1
}

function has_otp() {
    local line
    while IFS= read -r line; do
        is_otp_line "$line" && return 0
    done < <(printf '%s\n' "$1")
    return 1
}

# Prints an OTP flag (1/0) followed by line 1; with -a, lines 2+ go to fd 5.
# Run in a subshell so only line 1 reaches the process clip's timer forks.
function summarize_entry() {
    local content
    content=$(decrypt_entry "$1") || exit $?
    [ $show_all -ne 0 ] && print_rest "$content" >&5
    if has_otp "$content"; then printf 1; else printf 0; fi
    printf '%s' "${content%%$'\n'*}"
}

# `pass otp insert` stores the URI as line 1; never copy the seed.
function copy_password() {
    [ -n "$1" ] || die "There is no password to put on the clipboard at line 1."
    is_otp_line "$1" &&
        die "Error: line 1 of $2 is an otpauth:// URI, not a password. Use -o to copy the OTP code."
    clip "$1" "$2"
}

function copy_otp() {
    "$0" otp --help >/dev/null 2>&1 ||
        die "Error: pass-otp extension is required for OTP support"
    "$0" otp -c "$1"
}

# y/Y/Enter: yes, n/N: no, other keys ignored. No terminal: no.
function prompt_otp() {
    local key answer=1 saved
    { exec 4<>/dev/tty; } 2>/dev/null || return 1
    # Ctrl-C during `read -s` would otherwise leave echo off.
    saved=$(stty -g <&4 2>/dev/null)
    trap 'stty "$saved" <&4 2>/dev/null; printf "\n" >&4; exit 130' INT
    trap 'stty "$saved" <&4 2>/dev/null; printf "\n" >&4; exit 143' TERM
    printf 'Copy OTP code? (Y/n) ' >&4
    while IFS= read -rsn1 key <&4; do
        case "$key" in
            ""|y|Y) answer=0; break ;;
            n|N) break ;;
        esac
    done
    trap - INT TERM
    printf '\n' >&4
    exec 4>&-
    return $answer
}

select_only=0
show_all=0
otp_only=0
auto_otp=0
[ "$PASSWORD_STORE_FZF_SHOW_ALL" = true ] && show_all=1
[ "$PASSWORD_STORE_FZF_AUTO_OTP" = true ] && auto_otp=1

while getopts "saoih" o
do
    case "${o}" in
        s) select_only=1 ;;
        a) show_all=1 ;;
        o) otp_only=1 ;;
        i) auto_otp=1 ;;
        h) usage 0 ;;
        *) usage ;;
    esac
done

shift $((OPTIND-1))
query="$*"

res=$(candidate_selector_fzf "$query")
[ -n "$res" ] || exit 1
[ $select_only -ne 0 ] && echo "$res" && exit 0

if [ $show_all -ne 0 ] || [ $otp_only -eq 0 ]; then
    exec 5>&1
    summary=$(summarize_entry "$res") || exit $?
    exec 5>&-
fi

if [ $otp_only -ne 0 ]; then
    copy_otp "$res"
    exit $?
fi

copy_password "${summary#?}" "$res"
if [ $auto_otp -ne 0 ] && [ "${summary:0:1}" = 1 ] && prompt_otp; then
    copy_otp "$res"
    exit $?
fi
exit 0
