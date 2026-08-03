# Decode a JWT's header and payload (needs jq); the signature is printed, not verified.
jwtd() {
    if ! command -v jq >/dev/null; then
        echo "jwtd: needs jq (brew install jq)" >&2
        return 127
    fi
    jq -R 'split(".") | .[0],.[1] | @base64d | fromjson' <<< "${1}"
    echo "Signature: $(echo "${1}" | awk -F'.' '{print $3}')"
}

# Strip the password from a PDF -> passwordless copy (needs qpdf).
# Usage: pdfunlock input.pdf [output.pdf]   (default output: <input>-unlocked.pdf)
# Prompts for the password hidden, so it never lands in shell history.
pdfunlock() {
    if [[ -z "$1" ]]; then
        echo "usage: pdfunlock input.pdf [output.pdf]" >&2
        return 2
    fi
    if ! command -v qpdf >/dev/null; then
        echo "pdfunlock: needs qpdf (brew install qpdf)" >&2
        return 127
    fi
    local in="$1"
    local out="${2:-${1%.pdf}-unlocked.pdf}"
    local pw
    read -rs "pw?Password for $in: "
    echo
    if printf '%s' "$pw" | qpdf --password-file=- --decrypt "$in" "$out"; then
        echo "Unlocked -> $out"
    else
        echo "Failed (wrong password, or file not encrypted?)" >&2
        return 1
    fi
}

# Copy an image file to the macOS clipboard as PNG data (pasteable into Docs, Slack, etc.)
imgcopy() {
    if ! command -v osascript >/dev/null; then
        echo "imgcopy: needs osascript (macOS only)" >&2
        return 127
    fi
    if [[ ! -f "$1" ]]; then
        echo "imgcopy: no such file: $1" >&2
        return 1
    fi
    osascript -e "set the clipboard to (read (POSIX file \"$(realpath "$1")\") as «class PNGf»)" \
        && echo "copied: $1"
}
