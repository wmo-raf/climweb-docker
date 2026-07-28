#!/bin/bash
set -e

# get current working directory
WORKING_DIR=$(pwd)

# hooks sample file
hooks_sample_file="$WORKING_DIR/webhook/hooks.yaml.sample"

# .env file
env_file="$WORKING_DIR/.env"

# Check if hooks sample file exists
if [ ! -e "$hooks_sample_file" ]; then
    echo "Sample hooks file does not exist: $hooks_sample_file"
    exit 1
fi

# Check if .env file exists
if [ ! -e "$env_file" ]; then
    echo ".env file not found at $env_file. Please set up your .env file first."
    exit 1
fi

# Use Django's SECRET_KEY as the webhook secret — already set in every installation.
UPGRADE_WEBHOOK_SECRET=$(grep -E "^SECRET_KEY=" "$env_file" | cut -d'=' -f2- | tr -d '"')

if [ -z "$UPGRADE_WEBHOOK_SECRET" ]; then
    echo "SECRET_KEY is not set in $env_file. Please set it up before running this script."
    exit 1
fi

# new hooks file
hooks_file="$WORKING_DIR/webhook/hooks.yaml"

# The secret is emitted inside a double-quoted YAML scalar, so a '"' or '\' in the
# key would break the file. Bail out loudly rather than write something broken.
# (A backslash would also be mangled by awk's -v escape processing below.)
case "$UPGRADE_WEBHOOK_SECRET" in
    *[\"\\]*)
        echo "SECRET_KEY contains a quote or backslash, which cannot be embedded in hooks.yaml."
        echo "Regenerate SECRET_KEY without those characters, then re-run this script."
        exit 1
        ;;
esac

# Literal (non-regex, non-metacharacter) find-and-replace.
#
# Django's SECRET_KEY routinely contains characters that string-substitution tools
# treat as special in the REPLACEMENT text. Two separate tools get this wrong:
#   * sed          — an unescaped '&' expands to the whole match
#   * bash >= 5.2  — ${var//pat/rep} does the same, via patsub_replacement,
#                    which is enabled by default
# Both silently reinsert the placeholder into the middle of the secret. awk's
# index()/substr() have no metacharacter handling at all, so they are safe on
# every bash and every platform.
literal_replace() {
    # $1 = needle, $2 = replacement; text on stdin
    awk -v needle="$1" -v rep="$2" '
    {
        out = ""
        line = $0
        while ((i = index(line, needle)) > 0) {
            out = out substr(line, 1, i - 1) rep
            line = substr(line, i + length(needle))
        }
        print out line
    }'
}

# write out hooks_file
literal_replace "WORKING_DIR" "$WORKING_DIR" < "$hooks_sample_file" \
    | literal_replace "UPGRADE_WEBHOOK_SECRET_PLACEHOLDER" "$UPGRADE_WEBHOOK_SECRET" \
    > "$hooks_file"

# verify the substitution actually happened and the secret round-trips exactly
if grep -q 'UPGRADE_WEBHOOK_SECRET_PLACEHOLDER' "$hooks_file"; then
    echo "Placeholder still present in $hooks_file — substitution failed. Aborting."
    exit 1
fi

if ! grep -Fq "value: \"$UPGRADE_WEBHOOK_SECRET\"" "$hooks_file"; then
    echo "Secret was not written correctly to $hooks_file. Aborting."
    exit 1
fi

echo "Webhook config written to $hooks_file"
