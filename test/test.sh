#!/bin/bash

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
TOP_DIR=$(cd $SCRIPT_DIR/..; pwd)

# Exit immediately if a command exits with a non-zero status
set -e

# Temporary directory for test output
TEMP_DIR="$SCRIPT_DIR/temp_test_output"
mkdir -p "$TEMP_DIR"

# Directory for test data
DSD_INPUT_DIR="$SCRIPT_DIR/data/dsf"
EXPECTED_FLAC_DIR="$SCRIPT_DIR/data/expected_flac"

# Flag to track test failures
FAIL=0

# Path to the executable
EXECUTABLE="$TOP_DIR/src/dsf2flac"

# Execute test cases
for DSD_FILE in $(ls "$DSD_INPUT_DIR"/*.dff); do
    BASENAME=$(basename "$DSD_FILE" .dff)
    EXPECTED_FLAC_FILE="$EXPECTED_FLAC_DIR/$BASENAME.flac"
    GENERATED_FLAC_FILE="$TEMP_DIR/$BASENAME.flac"

    echo "Testing $DSD_FILE..."

    # Run the executable to convert the file
    if ! $EXECUTABLE -i "$DSD_FILE" -o "$GENERATED_FLAC_FILE"; then
        echo "Error: Failed to process $DSD_FILE"
        FAIL=1
        continue
    fi

    # Compare the expected output with the generated output (using hash values)
    EXPECTED_HASH=$(md5sum "$EXPECTED_FLAC_FILE" | awk '{print $1}')
    GENERATED_HASH=$(md5sum "$GENERATED_FLAC_FILE" | awk '{print $1}')

    if [ "$EXPECTED_HASH" != "$GENERATED_HASH" ]; then
        echo "Error: Output mismatch for $DSD_FILE"
        FAIL=1
    else
        echo "Success: $DSD_FILE"
    fi
done

# Return exit code 1 if any test fails
if [ $FAIL -ne 0 ]; then
    echo "Some tests failed."
    exit 1
else
    echo "All tests passed!"
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"
