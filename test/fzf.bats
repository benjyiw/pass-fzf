#!/usr/bin/env bats

load helpers

setup_file() { pfzf_setup_file; }
teardown_file() { pfzf_teardown_file; }
setup() { pfzf_setup; }
teardown() { pfzf_teardown; }

@test "-s prints the selected entry name and never decrypts" {
    export PFZF_SELECT=meta
    pfzf_run pass fzf -s
    [ "$status" -eq 0 ]
    [ "$output" = "meta" ]
    [ "$(pfzf_gpg_decrypts)" -eq 0 ]
    [ -z "$(pfzf_clipboard)" ]
}

@test "cancelled selection exits 1 with no output and an empty clipboard" {
    export PFZF_SELECT=""
    pfzf_run pass fzf
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [ -z "$(pfzf_clipboard)" ]
}

@test "query arguments are joined and passed to fzf with --select-1" {
    export PFZF_SELECT=meta
    pfzf_run pass fzf -s foo bar
    [ "$status" -eq 0 ]
    [ "$(cat "$PFZF_FZF_ARGS")" = "$(printf -- '-q\nfoo bar\n--select-1')" ]
}

@test "candidates are store-relative names, including subdirectories and spaces" {
    export PFZF_SELECT=meta
    pfzf_run pass fzf -s
    [ "$(LC_ALL=C sort "$PFZF_FZF_INPUT")" = "$(pfzf_expected_candidates)" ]
}

@test "unknown flag prints usage and exits 1" {
    pfzf_run pass fzf -x
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: "* ]] || false
    [ -z "$(pfzf_clipboard)" ]
}

@test "default: copies the password and prints only the copy message" {
    export PFZF_SELECT=totp
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$output" = "Copied totp to clipboard. Will clear in 600 seconds." ]
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "default: decrypts the entry exactly once" {
    export PFZF_SELECT=totp
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$(pfzf_gpg_decrypts)" -eq 1 ]
}

@test "-a prints lines 2+ (otpauth included) before the copy message" {
    export PFZF_SELECT=totp
    pfzf_run pass fzf -a
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' \
        'username: alice' \
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example' \
        'Copied totp to clipboard. Will clear in 600 seconds.')" ]
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "-a never prints the password line" {
    export PFZF_SELECT=meta
    pfzf_run pass fzf -a
    [ "$status" -eq 0 ]
    [[ "$output" != *"meta-pw"* ]] || false
}

@test "-a on a password-only entry prints only the copy message" {
    export PFZF_SELECT=plain
    pfzf_run pass fzf -a
    [ "$status" -eq 0 ]
    [ "$output" = "Copied plain to clipboard. Will clear in 600 seconds." ]
}

@test "PASSWORD_STORE_FZF_SHOW_ALL=true behaves like -a" {
    export PFZF_SELECT=meta PASSWORD_STORE_FZF_SHOW_ALL=true
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' 'username: bob' 'url: https://example.invalid' \
        'Copied meta to clipboard. Will clear in 600 seconds.')" ]
}

@test "PASSWORD_STORE_FZF_SHOW_ALL with a value other than true is ignored" {
    export PFZF_SELECT=meta PASSWORD_STORE_FZF_SHOW_ALL=1
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$output" = "Copied meta to clipboard. Will clear in 600 seconds." ]
}

@test "entry in a subdirectory with a space in its name" {
    export PFZF_SELECT="dir/with space"
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$output" = "Copied dir/with space to clipboard. Will clear in 600 seconds." ]
    [ "$(pfzf_clipboard)" = "nested-pw" ]
}

@test "undecryptable entry exits nonzero and copies nothing" {
    export PFZF_SELECT=corrupt
    pfzf_run pass fzf
    [ "$status" -ne 0 ]
    [[ "$output" != *"Copied"* ]] || false
    [ -z "$(pfzf_clipboard)" ]
}

@test "-o copies the OTP code instead of the password" {
    pfzf_install_otp
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_run pass fzf -o
    [ "$status" -eq 0 ]
    [ "$output" = "Copied OTP code for totp to clipboard. Will clear in 600 seconds." ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "-o does not decrypt in pass-fzf itself (only pass-otp's decrypt)" {
    pfzf_install_otp
    export PFZF_SELECT=totp
    pfzf_run pass fzf -o
    [ "$status" -eq 0 ]
    [ "$(pfzf_gpg_decrypts)" -eq 1 ]
}

@test "-o -a prints lines 2+ then copies the OTP code" {
    pfzf_install_otp
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_run pass fzf -o -a
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' \
        'username: alice' \
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example' \
        'Copied OTP code for totp to clipboard. Will clear in 600 seconds.')" ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "-o on an entry without an OTP fails and copies nothing" {
    pfzf_install_otp
    export PFZF_SELECT=plain
    pfzf_run pass fzf -o
    [ "$status" -ne 0 ]
    [[ "$output" == *"OTP secret not found"* ]] || false
    [ -z "$(pfzf_clipboard)" ]
}

@test "-o without pass-otp installed exits 1 with a clear error" {
    export PFZF_SELECT=totp
    pfzf_run pass fzf -o
    [ "$status" -eq 1 ]
    [ "$output" = "Error: pass-otp extension is required for OTP support" ]
    [ -z "$(pfzf_clipboard)" ]
}

@test "-h prints usage to stdout and exits 0" {
    pfzf_run pass fzf -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Usage: pass fzf [-s] [-a] [-o] [-i] [-h] [query]" ]
    [[ "$output" == *"PASSWORD_STORE_FZF_SHOW_ALL"* ]] || false
    [[ "$output" == *"PASSWORD_STORE_FZF_AUTO_OTP"* ]] || false
}

@test "unknown flag prints the full usage and exits 1" {
    pfzf_run pass fzf -x
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pass fzf [-s] [-a] [-o] [-i] [-h] [query]"* ]] || false
}

@test "an otpauth:// URI on line 1 is never copied as the password" {
    export PFZF_SELECT=urionly
    pfzf_run pass fzf
    [ "$status" -eq 1 ]
    [ "$output" = "Error: line 1 of urionly is an otpauth:// URI, not a password. Use -o to copy the OTP code." ]
    [ -z "$(pfzf_clipboard)" ]
}

@test "-o still copies the OTP code for an entry whose line 1 is the URI" {
    pfzf_install_otp
    export PFZF_SELECT=urionly
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_run pass fzf -o
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "an indented otpauth:// URI on line 1 is never copied as the password" {
    export PFZF_SELECT=indenturi
    pfzf_run pass fzf
    [ "$status" -eq 1 ]
    [ "$output" = "Error: line 1 of indenturi is an otpauth:// URI, not a password. Use -o to copy the OTP code." ]
    [ -z "$(pfzf_clipboard)" ]
}

@test "an empty line 1 is refused, like pass show -c" {
    export PFZF_SELECT=emptypw
    printf 'previous clipboard' > "$PFZF_CLIPBOARD"
    pfzf_run pass fzf
    [ "$status" -eq 1 ]
    [ "$output" = "There is no password to put on the clipboard at line 1." ]
    [ "$(pfzf_clipboard)" = "previous clipboard" ]
}

@test "-o runs the pass that was invoked, not the first pass on PATH" {
    pfzf_install_otp
    export PFZF_SELECT=totp
    mkdir -p "$BATS_TEST_TMPDIR/otherbin"
    printf '#!/bin/sh\necho "wrong pass" >&2\nexit 42\n' > "$BATS_TEST_TMPDIR/otherbin/pass"
    chmod +x "$BATS_TEST_TMPDIR/otherbin/pass"
    export PATH="$BATS_TEST_TMPDIR/otherbin:$PATH"
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_run "$PFZF_REAL_PASS" fzf -o
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "candidates are right when PASSWORD_STORE_DIR has a trailing slash" {
    export PFZF_SELECT=meta PASSWORD_STORE_DIR="$PASSWORD_STORE_DIR/"
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$(LC_ALL=C sort "$PFZF_FZF_INPUT")" = "$(pfzf_expected_candidates)" ]
    [ "$(pfzf_clipboard)" = "meta-pw" ]
}

@test "candidates are right when the store is a symlink" {
    ln -s "$PASSWORD_STORE_DIR" "$BATS_TEST_TMPDIR/linked-store"
    export PFZF_SELECT=meta PASSWORD_STORE_DIR="$BATS_TEST_TMPDIR/linked-store"
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$(LC_ALL=C sort "$PFZF_FZF_INPUT")" = "$(pfzf_expected_candidates)" ]
    [ "$(pfzf_clipboard)" = "meta-pw" ]
}

@test "candidates are right when the store path contains a colon" {
    cp -R "$PASSWORD_STORE_DIR" "$BATS_TEST_TMPDIR/a:b"
    export PFZF_SELECT=meta PASSWORD_STORE_DIR="$BATS_TEST_TMPDIR/a:b"
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$(LC_ALL=C sort "$PFZF_FZF_INPUT")" = "$(pfzf_expected_candidates)" ]
    [ "$(pfzf_clipboard)" = "meta-pw" ]
}

@test "candidates are right when PASSWORD_STORE_DIR is ." {
    cd "$PASSWORD_STORE_DIR"
    export PFZF_SELECT="dir/with space" PASSWORD_STORE_DIR=.
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    [ "$(LC_ALL=C sort "$PFZF_FZF_INPUT")" = "$(pfzf_expected_candidates)" ]
    [ "$(pfzf_clipboard)" = "nested-pw" ]
}

@test "the clipboard clear timer gets its own process group" {
    export PFZF_SELECT=meta
    pfzf_run pass fzf
    [ "$status" -eq 0 ]
    pfzf_wait_timers 1
    [ "$(cut -d' ' -f2 "$PFZF_TIMERS")" != "$(cat "$PFZF_FZF_PGID")" ]
}

@test "the OTP clear timer gets its own process group" {
    pfzf_install_otp
    export PFZF_SELECT=totp
    pfzf_run pass fzf -o
    [ "$status" -eq 0 ]
    pfzf_wait_timers 1
    [ "$(cut -d' ' -f2 "$PFZF_TIMERS")" != "$(cat "$PFZF_FZF_PGID")" ]
}

@test "the original clipboard comes back after the password clears" {
    export PFZF_SELECT=meta
    printf 'original' > "$PFZF_CLIPBOARD"
    pfzf_run pass fzf
    [ "$(pfzf_clipboard)" = "meta-pw" ]
    pfzf_wait_timers 1
    pfzf_expire_timers
    [ "$(pfzf_clipboard)" = "original" ]
}

@test "a sneaky selection outside the store is refused" {
    export PFZF_SELECT="../outside/x"
    mkdir -p "$PFZF_ROOT/outside"
    cp "$PASSWORD_STORE_DIR/meta.gpg" "$PFZF_ROOT/outside/x.gpg"
    pfzf_run pass fzf
    [ "$status" -eq 1 ]
    [[ "$output" == *"sneaky path"* ]] || false
    [ -z "$(pfzf_clipboard)" ]
}

@test "a folder name containing a newline can't smuggle a path out of the store" {
    pfzf_private_store
    mkdir -p "$PASSWORD_STORE_DIR/evil"$'\n'"../outside"
    cp "$PASSWORD_STORE_DIR/meta.gpg" "$PASSWORD_STORE_DIR/evil"$'\n'"../outside/x.gpg"
    export PFZF_SELECT=meta
    pfzf_run pass fzf -s
    [ "$(LC_ALL=C sort "$PFZF_FZF_INPUT")" = "$(pfzf_expected_candidates)" ]
}

@test "a multi-line selection is refused" {
    export PFZF_SELECT=$'meta\nplain'
    pfzf_run pass fzf
    [ "$status" -eq 1 ]
    [ "$output" = "Error: select a single entry." ]
    [ -z "$(pfzf_clipboard)" ]
}

@test "-o works for an entry whose name starts with a dash" {
    pfzf_install_otp
    pfzf_private_store
    cp "$PASSWORD_STORE_DIR/totp.gpg" "$PASSWORD_STORE_DIR/-c.gpg"
    export PFZF_SELECT=-c
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_run pass fzf -o
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "-o works for an entry named like a pass-otp subcommand" {
    pfzf_install_otp
    pfzf_private_store
    cp "$PASSWORD_STORE_DIR/totp.gpg" "$PASSWORD_STORE_DIR/uri.gpg"
    export PFZF_SELECT=uri
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_run pass fzf -o
    [ "$status" -eq 0 ]
    [[ "$output" != *"otpauth://"* ]] || false
    pfzf_assert_totp_on_clipboard "$code"
}

@test "-s prints an entry named -n" {
    pfzf_private_store
    cp "$PASSWORD_STORE_DIR/plain.gpg" "$PASSWORD_STORE_DIR/-n.gpg"
    export PFZF_SELECT=-n
    pfzf_run pass fzf -s
    [ "$status" -eq 0 ]
    [ "$output" = "-n" ]
}
