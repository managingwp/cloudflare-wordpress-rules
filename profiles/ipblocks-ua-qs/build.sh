#!/bin/bash
# filepath: /home/jtrask/git/cloudflare-wordpress-rules/profiles/build.sh

set -e

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <source_file> [output_file]"
  exit 1
fi

SOURCE_FILE="$1"

# Set output file
if [ $# -ge 2 ]; then
  OUTPUT_FILE="$2"
else
  OUTPUT_FILE="${SOURCE_FILE%.src}.json"
fi

# Temporary files
TEMP_DIR=$(mktemp -d)
PROFILE_INFO="${TEMP_DIR}/profile_info.json"
RULES_FILE="${TEMP_DIR}/rules.json"
VARS_FILE="${TEMP_DIR}/variables.json"
VARS_PROCESSED="${TEMP_DIR}/variables_processed.json"

cleanup() {
  rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

echo "Building JSON from $SOURCE_FILE to $OUTPUT_FILE"

# Extract profile information
NAME=$(grep -m1 "^name:" "$SOURCE_FILE" | sed 's/name:\s*//')
DESCRIPTION=$(grep -m1 "^description:" "$SOURCE_FILE" | sed 's/description:\s*//')

echo "{\"name\": \"$NAME\", \"description\": \"$DESCRIPTION\"}" > "$PROFILE_INFO"

# Process the source file line by line
{
  echo "{"
  
  # Variable processing
  var_name=""
  in_var=false
  while IFS= read -r line; do
    # Check for variable definition start
    if [[ $line =~ ^@([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*\[ ]]; then
      var_name="${BASH_REMATCH[1]}"
      in_var=true
      echo "\"$var_name\": ["
      continue
    fi
    
    # Check for end of variable
    if $in_var && [[ $line == *"]"* ]]; then
      # Clean the line, removing comments and the closing bracket
      clean_line=$(echo "$line" | sed 's/#.*//g' | sed 's/\]//g' | xargs)
      
      # Process the values
      if [ -n "$clean_line" ]; then
        values=()
        for val in $clean_line; do
          values+=("\"$val\"")
        done
        
        if [ ${#values[@]} -gt 0 ]; then
          echo -n "${values[*]}"
        fi
      fi
      
      echo "],"
      in_var=false
      continue
    fi
    
    # If we're inside a variable definition, process the line
    if $in_var; then
      # Clean the line, removing comments
      clean_line=$(echo "$line" | sed 's/#.*//g' | xargs)
      
      # Process the values
      if [ -n "$clean_line" ]; then
        values=()
        for val in $clean_line; do
          values+=("\"$val\"")
        done
        
        if [ ${#values[@]} -gt 0 ]; then
          echo -n "${values[*]}, "
        fi
      fi
    fi
  done < "$SOURCE_FILE"
  
  # Remove trailing comma
  sed -i '$ s/,$//' "$VARS_FILE"
  
  echo "}"
} > "$VARS_FILE"

# Process rules
{
  echo "["
  
  # Variables to track state
  in_rule=false
  rule_id=""
  description=""
  action=""
  priority=""
  expr=""
  in_expr=false
  first_rule=true
  
  while IFS= read -r line; do
    # Check for rule start
    if [[ $line =~ ^\[rule:([a-zA-Z0-9_]+)\] ]]; then
      # If we were already processing a rule, output it first
      if $in_rule; then
        # Format the expression
        expr=$(echo "$expr" | tr -s ' \n\t' ' ' | sed 's/^ *//;s/ *$//')
        
        # Replace variables in the expression
        while [[ $expr =~ @([a-zA-Z0-9_]+) ]]; then
          var_name="${BASH_REMATCH[1]}"
          var_value=$(jq -r --arg name "$var_name" '.[$name] | if type == "array" then (map(.) | join(" ")) else . end' "$VARS_FILE")
          expr=${expr//@$var_name/$var_value}
        done
        
        # Output the rule as JSON
        if ! $first_rule; then
          echo ","
        fi
        first_rule=false
        
        echo "  {"
        echo "    \"description\": \"$description\","
        echo "    \"expression\": \"$expr\","
        echo "    \"action\": \"$action\","
        echo "    \"priority\": $priority"
        echo -n "  }"
      fi
      
      # Start new rule
      in_rule=true
      rule_id="${BASH_REMATCH[1]}"
      description=""
      action=""
      priority=""
      expr=""
      in_expr=false
      continue
    fi
    
    # Process rule properties
    if $in_rule; then
      if [[ $line =~ ^description:[[:space:]]*(.*)$ ]]; then
        description="${BASH_REMATCH[1]}"
        continue
      elif [[ $line =~ ^action:[[:space:]]*(.*)$ ]]; then
        action="${BASH_REMATCH[1]}"
        continue
      elif [[ $line =~ ^priority:[[:space:]]*(.*)$ ]]; then
        priority="${BASH_REMATCH[1]}"
        continue
      elif [[ $line =~ ^expression:[[:space:]]*\| ]]; then
        in_expr=true
        continue
      elif $in_expr && [[ $line =~ ^[a-z] ]]; then
        in_expr=false
        continue
      elif $in_expr; then
        expr="$expr $line"
      fi
    fi
  done < "$SOURCE_FILE"
  
  # Handle the last rule
  if $in_rule; then
    # Format the expression
    expr=$(echo "$expr" | tr -s ' \n\t' ' ' | sed 's/^ *//;s/ *$//')
    
    # Replace variables in the expression
    while [[ $expr =~ @([a-zA-Z0-9_]+) ]]; then
      var_name="${BASH_REMATCH[1]}"
      var_value=$(jq -r --arg name "$var_name" '.[$name] | if type == "array" then (map(.) | join(" ")) else . end' "$VARS_FILE")
      expr=${expr//@$var_name/$var_value}
    done
    
    # Output the rule as JSON
    if ! $first_rule; then
      echo ","
    fi
    
    echo "  {"
    echo "    \"description\": \"$description\","
    echo "    \"expression\": \"$expr\","
    echo "    \"action\": \"$action\","
    echo "    \"priority\": $priority"
    echo "  }"
  fi
  
  echo "]"
} > "$RULES_FILE"

# Combine profile info and rules into the final JSON
jq --slurpfile rules "$RULES_FILE" '.rules = $rules[0]' "$PROFILE_INFO" > "$OUTPUT_FILE"

echo "JSON file built successfully: $OUTPUT_FILE"