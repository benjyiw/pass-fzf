#!/usr/bin/env bats

load helpers

setup_file() { pfzf_setup_file; }
teardown_file() { pfzf_teardown_file; }
setup() { pfzf_setup; pfzf_install_otp; }
teardown() { pfzf_teardown; }

pfzf_expect() {
    local keys="$1"; shift
    run expect "$PFZF_REPO/test/expect/prompt.exp" "$keys" pass fzf "$@"
    output="${output//$'\r'/}"
}

@test "Enter copies the OTP code" {
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect '\r' -i
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "y copies the OTP code without needing Enter" {
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect 'y' -i
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "Y copies the OTP code" {
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect 'Y' -i
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "n keeps the password on the clipboard" {
    export PFZF_SELECT=totp
    pfzf_expect 'n' -i
    [ "$status" -eq 0 ]
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "N keeps the password on the clipboard" {
    export PFZF_SELECT=totp
    pfzf_expect 'N' -i
    [ "$status" -eq 0 ]
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "other keys are ignored until y/n/Enter" {
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect 'x y' -i
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "Ctrl-C at the prompt leaves the password on the clipboard" {
    export PFZF_SELECT=totp
    pfzf_expect '\003' -i
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "the prompt follows the password copy message" {
    export PFZF_SELECT=totp
    pfzf_expect 'n' -i
    [[ "$output" == *"Copied totp to clipboard. Will clear in 600 seconds."*"Copy OTP code? (Y/n) "* ]] || false
    [[ "$output" != *"otpauth://"* ]] || false
}

@test "-a -i prints lines 2+, then the copy message, then the prompt" {
    export PFZF_SELECT=totp
    pfzf_expect 'n' -a -i
    [[ "$output" == *"username: alice"*"Copied totp to clipboard."*"Copy OTP code? (Y/n) "* ]] || false
}

@test "no prompt for an entry without an OTP" {
    export PFZF_SELECT=meta
    pfzf_expect '-' -i
    [ "$status" -eq 0 ]
    [ "$(pfzf_clipboard)" = "meta-pw" ]
}

@test "no prompt when otpauth:// only appears mid-line" {
    export PFZF_SELECT=mention
    pfzf_expect '-' -i
    [ "$status" -eq 0 ]
    [ "$(pfzf_clipboard)" = "mention-pw" ]
}

@test "PASSWORD_STORE_FZF_AUTO_OTP=true prompts without -i" {
    export PFZF_SELECT=totp PASSWORD_STORE_FZF_AUTO_OTP=true
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect 'y'
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "PASSWORD_STORE_FZF_AUTO_OTP with a value other than true is ignored" {
    export PFZF_SELECT=totp PASSWORD_STORE_FZF_AUTO_OTP=yes
    pfzf_expect '-'
    [ "$status" -eq 0 ]
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "-o makes -i a no-op: OTP copied, no prompt" {
    export PFZF_SELECT=totp
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect '-' -o -i
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "-i without a terminal skips the prompt and keeps the password" {
    export PFZF_SELECT=totp
    pfzf_run pass fzf -i
    [ "$status" -eq 0 ]
    [ "$output" = "Copied totp to clipboard. Will clear in 600 seconds." ]
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}

@test "-i never copies an otpauth:// URI on line 1 and shows no prompt" {
    export PFZF_SELECT=urionly
    pfzf_expect '-' -i
    [ "$status" -eq 1 ]
    [[ "$output" == *"Use -o to copy the OTP code."* ]] || false
    [ -z "$(pfzf_clipboard)" ]
}

@test "an indented otpauth:// line is detected, like pass-otp" {
    export PFZF_SELECT=indented
    local code; code="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    pfzf_expect 'y' -i
    [ "$status" -eq 0 ]
    pfzf_assert_totp_on_clipboard "$code"
}

@test "Ctrl-C at the prompt restores the terminal settings" {
    export PFZF_SELECT=totp
    # perl's system() ignores SIGINT, so it survives to report the tty state.
    run expect "$PFZF_REPO/test/expect/prompt.exp" '\003' \
        perl -e 'system @ARGV; exec "stty", "-a"' -- pass fzf -i
    output="${output//$'\r'/}"
    [[ "$output" == *"lflags:"* ]] || false
    [[ "$output" != *"-icanon"* ]] || false
    [[ ! "$output" =~ (^|[[:space:]])-echo([[:space:]]|$) ]] || false
    [ "$(pfzf_clipboard)" = "totp-pw" ]
}
