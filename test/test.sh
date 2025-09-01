#!/bin/bash

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
TOP_DIR=$(cd $SCRIPT_DIR/..; pwd)

# Exit immediately if a command exits with a non-zero status
set -e

# Fail a pipeline if any command errors
set -o pipefail

# Temporary directory for test output
TEMP_DIR="$SCRIPT_DIR/temp_test_output"
mkdir -p "$TEMP_DIR"

# Directory for test data
DSD_INPUT_DIR="$SCRIPT_DIR/data/dsf"

# Optional expectations (override via environment variables)
# e.g., EXPECTED_CHANNELS=2 EXPECTED_SR=88200 CONVERT_OPTS="--rate 88200 --bits 24"
EXPECTED_CHANNELS="${EXPECTED_CHANNELS:-}"
EXPECTED_SR="${EXPECTED_SR:-}"
CONVERT_OPTS="${CONVERT_OPTS:-}"

# Flag to track test failures
FAIL=0

# Path to the executable
EXECUTABLE="$TOP_DIR/src/dsf2flac"

# Check required external tools early
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: required command '$1' not found"; exit 1; }
}
require_cmd "$EXECUTABLE"
require_cmd flac
require_cmd ffmpeg
require_cmd ffprobe
require_cmd metaflac
require_cmd md5sum
require_cmd awk
require_cmd head

# Make globs that don't match expand to empty (not literal)
shopt -s nullglob

# Execute test cases (.dff and .dsf)
for DSD_FILE in "$DSD_INPUT_DIR"/*.dff "$DSD_INPUT_DIR"/*.dsf; do
    [ -e "$DSD_FILE" ] || { echo "No DSD files found under $DSD_INPUT_DIR"; break; }

    BASENAME="$(basename "$DSD_FILE")"
    BASENAME="${BASENAME%.*}"
    GENERATED_FLAC_FILE="$TEMP_DIR/$BASENAME.flac"

    echo "Testing $DSD_FILE..."

    # Run the executable to convert the file
    if ! $EXECUTABLE -i "$DSD_FILE" -o "$GENERATED_FLAC_FILE" $CONVERT_OPTS; then
        echo "Error: Failed to process $DSD_FILE"
        FAIL=1
        continue
    fi

    # --- Additional validation for correctness as FLAC ---

    # 1) File signature check: first 4 bytes must be "fLaC"
    SIG="$(head -c 4 "$GENERATED_FLAC_FILE" || true)"
    if [ "$SIG" != "fLaC" ]; then
        echo "Error: FLAC signature missing for $GENERATED_FLAC_FILE"
        FAIL=1
        continue
    else
        echo "OK: FLAC signature present"
    fi

    # 2) Format validity / decodability
    if ! flac -t "$GENERATED_FLAC_FILE" >/dev/null 2>&1; then
        echo "Error: 'flac -t' failed (format test) for $GENERATED_FLAC_FILE"
        FAIL=1
        continue
    fi
    if ! ffmpeg -hide_banner -loglevel error -nostdin -i "$GENERATED_FLAC_FILE" -f null - >/dev/null 2>&1; then
        echo "Error: ffmpeg decode failed for $GENERATED_FLAC_FILE"
        FAIL=1
        continue
    fi
    echo "OK: Decoding passes (flac -t and ffmpeg)"

    # 3) Stream metadata checks (codec, channels, sample_rate)
    FFINFO="$(ffprobe -v error -select_streams a:0 \
             -show_entries stream=codec_name,channels,sample_rate \
             -of default=noprint_wrappers=1:nokey=1 "$GENERATED_FLAC_FILE")" || {
        echo "Error: ffprobe failed for $GENERATED_FLAC_FILE"
        FAIL=1
        continue
    }

    # ffprobe with nokey=1 prints three lines in the order: codec_name, channels, sample_rate
    CODEC="$(echo "$FFINFO" | sed -n '1p')"
    CH="$(echo "$FFINFO" | sed -n '2p')"
    SR="$(echo "$FFINFO" | sed -n '3p')"

    if [ "$CODEC" != "flac" ]; then
        echo "Error: codec_name=$CODEC (expected flac)"
        FAIL=1
        continue
    fi
    if [ -n "$EXPECTED_CHANNELS" ] && [ "$CH" != "$EXPECTED_CHANNELS" ]; then
        echo "Error: channels=$CH (expected $EXPECTED_CHANNELS)"
        FAIL=1
        continue
    fi
    if [ -n "$EXPECTED_SR" ] && [ "$SR" != "$EXPECTED_SR" ]; then
        echo "Error: sample_rate=$SR (expected $EXPECTED_SR)"
        FAIL=1
        continue
    fi
    echo "OK: Stream metadata valid (codec=$CODEC, channels=$CH, sample_rate=$SR)"

    # 4) FLAC internal test only (skip MD5/PCM comparison)
    if ! flac --test "$GENERATED_FLAC_FILE" >/dev/null 2>&1; then
        echo "Error: flac --test failed for $GENERATED_FLAC_FILE"
        FAIL=1
        continue
    fi
    echo "OK: flac --test passed"

    echo "Success: $DSD_FILE"
done

# Return exit code 1 if any test fails
if [ $FAIL -ne 0 ]; then
    echo "Some tests failed."
    # Clean up temporary files on failure as well
    rm -rf "$TEMP_DIR"
    exit 1
else
    echo "All tests passed!"
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"
