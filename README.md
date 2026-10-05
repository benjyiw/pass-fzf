# pass-fzf

Fuzzy-find [pass](https://www.passwordstore.org/) entries with
[fzf](https://github.com/junegunn/fzf) and copy them to the clipboard. Secrets are never
printed unless you ask. OTP codes are supported via
[pass-otp](https://github.com/tadfisher/pass-otp).

Fork of [ficoos/pass-fzf](https://github.com/ficoos/pass-fzf). Upstream prints every line
after the password to the terminal, so `otpauth://` URIs and their TOTP secrets end up in
scrollback and terminal logs. It also has no way to copy OTP codes. Upstream hasn't changed
since 2021, so these are fixed here.

## Usage

```
pass fzf [-s] [-a] [-o] [-i] [-h] [query]
```

Copies the selected entry's password (line 1). Nothing else is printed by default.

| Flag | Env var | Effect |
|------|---------|--------|
| `-s` | | Print the entry name and exit |
| `-a` | `PASSWORD_STORE_FZF_SHOW_ALL=true` | Also print lines 2+ |
| `-o` | | Copy the OTP code instead of the password |
| `-i` | `PASSWORD_STORE_FZF_AUTO_OTP=true` | After copying the password, prompt `Copy OTP code? (Y/n)` if the entry has an OTP |
| `-h` | | Help |

## Install

Requires `pass`, `gpg` and `fzf`. `-o` and `-i` also need pass-otp.

```sh
dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}/.extensions"
mkdir -p "$dir"
curl -fsSL https://raw.githubusercontent.com/benjyiw/pass-fzf/main/fzf.bash -o "$dir/fzf.bash"
chmod +x "$dir/fzf.bash"
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

## Changes from upstream

- Lines 2+ (including `otpauth://` secrets) are no longer printed by default; use `-a`.
- Added `-a`, `-o`, `-i`, `-h`.
- Entries are decrypted once instead of twice.
- An `otpauth://` URI on line 1 is never copied as a password.
- Store paths with a trailing slash, symlinks or special characters work.

## Tests

```sh
brew install bats-core shellcheck
bats test/
shellcheck fzf.bash
```

Tests use a throwaway GPG key and store, and never touch your real store or clipboard.

## License

MIT. Based on [pass-fzf](https://github.com/ficoos/pass-fzf) by Saggi Mizrahi; see
[LICENSE](LICENSE).
