# Tests run the real pass against a throwaway GPG home and store.

PFZF_REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

pfzf_setup_file() {
    # Short path: gpg-agent sockets have a ~104 byte path limit.
    PFZF_ROOT="$(mktemp -d /tmp/pfzf.XXXXXX)"
    export PFZF_ROOT
    export GNUPGHOME="$PFZF_ROOT/gnupg"
    export PASSWORD_STORE_DIR="$PFZF_ROOT/store"
    PFZF_REAL_GPG="$(command -v gpg)"
    export PFZF_REAL_GPG
    PFZF_REAL_PASS="$(command -v pass)"
    export PFZF_REAL_PASS
    mkdir -m 700 "$GNUPGHOME"

    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-gen-key 'pass-fzf test <test@example.invalid>' default default never \
        >/dev/null 2>&1
    local fpr
    fpr="$(gpg --list-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')"
    pass init "$fpr" >/dev/null

    printf 'plain-pw\n' | pass insert -m plain >/dev/null
    printf 'meta-pw\nusername: bob\nurl: https://example.invalid\n' \
        | pass insert -m meta >/dev/null
    printf 'totp-pw\nusername: alice\notpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example\n' \
        | pass insert -m totp >/dev/null
    printf 'mention-pw\nnotes: see otpauth://totp/Fake:x?secret=AAAAAAAAAAAAAAAA\n' \
        | pass insert -m mention >/dev/null
    printf 'nested-pw\n' | pass insert -m 'dir/with space' >/dev/null
    printf 'otpauth://totp/Only:x?secret=JBSWY3DPEHPK3PXP&issuer=Only\n' \
        | pass insert -m urionly >/dev/null
    printf 'indented-pw\n  otpauth://totp/Ind:x?secret=JBSWY3DPEHPK3PXP&issuer=Ind\n' \
        | pass insert -m indented >/dev/null
    printf '\totpauth://totp/IndUri:x?secret=JBSWY3DPEHPK3PXP&issuer=IndUri\n' \
        | pass insert -m indenturi >/dev/null
    printf '\nusername: nopw\n' | pass insert -m emptypw >/dev/null
    printf 'not a gpg file\n' > "$PASSWORD_STORE_DIR/corrupt.gpg"
}

pfzf_teardown_file() {
    gpgconf --kill gpg-agent 2>/dev/null
    rm -rf "$PFZF_ROOT"
}

pfzf_setup() {
    export PFZF_CLIPBOARD="$BATS_TEST_TMPDIR/clipboard"
    export PFZF_SENTINEL="$BATS_TEST_TMPDIR/sentinel"
    export PFZF_GPG_LOG="$BATS_TEST_TMPDIR/gpg.log"
    export PFZF_FZF_ARGS="$BATS_TEST_TMPDIR/fzf.args"
    export PFZF_FZF_INPUT="$BATS_TEST_TMPDIR/fzf.input"
    export PFZF_SELECT=""
    : > "$PFZF_SENTINEL"
    : > "$PFZF_GPG_LOG"

    export PATH="$PFZF_REPO/test/stubs:$PATH"
    export PASSWORD_STORE_ENABLE_EXTENSIONS=true
    export PASSWORD_STORE_CLIP_TIME=600
    export PASSWORD_STORE_EXTENSIONS_DIR="$BATS_TEST_TMPDIR/extensions"
    mkdir -p "$PASSWORD_STORE_EXTENSIONS_DIR"
    cp "$PFZF_REPO/fzf.bash" "$PASSWORD_STORE_EXTENSIONS_DIR/fzf.bash"
    chmod +x "$PASSWORD_STORE_EXTENSIONS_DIR/fzf.bash"
    unset PASSWORD_STORE_FZF_SHOW_ALL PASSWORD_STORE_FZF_AUTO_OTP
}

# Releases the clear-timer stubs (see test/stubs/sleep).
pfzf_teardown() {
    rm -f "$PFZF_SENTINEL"
}

# `run` without a controlling terminal, so /dev/tty can't be opened.
pfzf_run() {
    run perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' -- "$@"
}

pfzf_expected_candidates() {
    printf '%s\n' corrupt 'dir/with space' emptypw indented indenturi mention meta plain totp urionly
}

pfzf_clipboard() {
    cat "$PFZF_CLIPBOARD" 2>/dev/null
}

pfzf_gpg_decrypts() {
    grep -c -- '^-d ' "$PFZF_GPG_LOG"
}

PFZF_TOTP_SECRET=JBSWY3DPEHPK3PXP

pfzf_install_otp() {
    local candidate
    for candidate in \
        "${PFZF_OTP_EXTENSION:-}" \
        "$HOME/.password-store/.extensions/otp.bash" \
        /opt/homebrew/lib/password-store/extensions/otp.bash \
        /usr/local/lib/password-store/extensions/otp.bash \
        /usr/lib/password-store/extensions/otp.bash; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            cp "$candidate" "$PASSWORD_STORE_EXTENSIONS_DIR/otp.bash"
            chmod +x "$PASSWORD_STORE_EXTENSIONS_DIR/otp.bash"
            command -v oathtool >/dev/null || skip "oathtool not installed"
            return 0
        fi
    done
    skip "pass-otp not installed (set PFZF_OTP_EXTENSION=/path/to/otp.bash)"
}

# Accepts the code from before the run or the current one (30s boundary).
pfzf_assert_totp_on_clipboard() {
    local before="$1" after clipped
    after="$(oathtool --totp -b "$PFZF_TOTP_SECRET")"
    clipped="$(pfzf_clipboard)"
    [[ "$clipped" =~ ^[0-9]{6}$ ]] || { echo "clipboard: '$clipped'"; return 1; }
    [ "$clipped" = "$before" ] || [ "$clipped" = "$after" ]
}
