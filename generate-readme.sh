#!/bin/bash
# -- Combine README.md and CHANGELOG.md into README.md

# Check if README.md exists
if [ ! -f README.md ]; then
    echo "README.md does not exist"
    exit 1
fi

# Read in the README.md file
README=$(<README.md)

# Check if README.md contains <!--- CHANGELOG ---> and <!--- END CHANGELOG ---> tags
if ! grep -q '<!--- CHANGELOG --->' README.md || ! grep -q '<!--- END CHANGELOG --->' README.md; then
    echo "README.md does not contain <!--- CHANGELOG ---> and <!--- END CHANGELOG ---> tags"
    exit 1
fi

# Generate the CHANGELOG.md file
git log --pretty=format:"## %s%n%b%n" | sed '/^## /b; /^[[:space:]]*$/b; s/^/* /' > CHANGELOG.md
CHANGELOG=$(<CHANGELOG.md)

# Locate <!--- CHANGELOG ---> in the README.md file
# Replace everything between the two tags with the CHANGELOG.md file and ensure <!--- are still in-place
README=$(echo "$README" | sed -e "/<!--- CHANGELOG --->/,/<!--- END CHANGELOG --->/{ /<!--- CHANGELOG --->/{p; r CHANGELOG.md
        }; /<!--- END CHANGELOG --->/p; d }")

# Write the new README.md file
echo "$README" > README.md