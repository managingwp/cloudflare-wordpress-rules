#!/bin/bash
# -- Combine README.md and CHANGELOG.md into README.md
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
README_PATH="$SCRIPT_DIR/.."
README_FILE="${README_PATH}/README.md"
CHANGELOG_FILE="${README_PATH}/CHANGELOG.md"
# Check if README.md exists
if [ ! -f README.md ]; then
    echo "README.md does not exist"
    exit 1
fi

# Read in the README.md file
README=$(<${README_FILE})

# Check if README.md contains <!--- CHANGELOG ---> and <!--- END CHANGELOG ---> tags
echo "Checking for <!--- CHANGELOG ---> and <!--- END CHANGELOG ---> tags in README.md"
if ! grep -q '<!--- CHANGELOG --->' ${README_FILE} || ! grep -q '<!--- END CHANGELOG --->' ${README_FILE}; then
    echo "File $README_FILE does not contain <!--- CHANGELOG ---> and <!--- END CHANGELOG ---> tags"
    exit 1
fi

# Generate the CHANGELOG.md file
git log --pretty=format:"## %s%n%b" | sed '/^## /b; /^$/d; s/^/* /' > ${CHANGELOG_FILE}
CHANGELOG=$(<${CHANGELOG_FILE})

# Locate <!--- CHANGELOG ---> in the README.md file
# Replace everything between the two tags with the CHANGELOG.md file and ensure <!--- are still in-place
README=$(echo "$README" | sed -e "/<!--- CHANGELOG --->/,/<!--- END CHANGELOG --->/{ /<!--- CHANGELOG --->/{p; r CHANGELOG.md
        }; /<!--- END CHANGELOG --->/p; d }")
# Write the new README.md file
echo "$README" > ${README_FILE}