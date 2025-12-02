# TODO

## General
* Cleanup repository, overall it's structure is all over the place.
* Improve article on managingwp.io
* Look at symlinking the default.json and default.md so that it doesn't need to be copied for each new version.
* move include files into inc folder?
* document how to use the repo.
* Convert code to new API calls.

## v2.2.0
### Add multiple zone support
* [x] Add support for running commands on multiple zones.
* [x] Utilize zones.txt file to define zones or zoneids.
* [x] Add command line argument to specify zones file.
* [ ] Test multiple zone functionality.
* [x] Update examples in README.md to demonstrate multiple zone usage.
* [x] Allow for zones to be added multiple times via argument -d
* [x] Before proceeding count the zones that will be affected and ask for confirmation.

### Plan

#### Phase 1: Core Infrastructure
1. **Create `_load_zones_file` function in `cf-inc.sh`** ✅
   - Read zones from a text file (one domain or zone ID per line)
   - Support comments (lines starting with `#`)
   - Skip empty lines
   - Return array of zones

2. **Add new CLI arguments to `cloudflare-wordpress-rules.sh`** ✅
   - `-zf|--zones-file <file>` - Path to zones file
   - `-d|--domain` - Allow multiple uses (accumulate into array)
   - `-y|--yes` - Skip confirmation prompt
   - `--all-zones` - Process all zones in the account (optional, advanced)

3. **Create zones file format** ✅
   - Create `zones.txt.example` in repo root
   - Format: one domain or zone ID per line
   - Support inline comments with `#`

#### Phase 2: Confirmation & Zone Count
4. **Create `_confirm_zones` function** ✅
   - Count total zones to be affected
   - Display list of zones (truncate if > 10, show "and X more...")
   - Display: "This will affect X zone(s). Continue? [y/N]"
   - Respect `-y|--yes` flag to skip prompt
   - Return 0 (proceed) or 1 (abort)

5. **Create `_run_on_zones` wrapper function** ✅
   - Accept command function and zones array
   - **Call `_confirm_zones` before executing**
   - Loop through each zone
   - Display progress: "Processing zone 1 of N: domain.com"
   - Collect results (success/fail per zone)
   - Summary at end: "Completed: X succeeded, Y failed"

#### Phase 3: Argument Parsing Updates
6. **Update argument parsing** ✅
   - Accumulate multiple `-d` arguments into `DOMAINS` array
   - If `-zf` provided, merge with `DOMAINS` array
   - Validate: require at least one zone source for zone-dependent commands
   - Deduplicate zones (prevent same zone being processed twice)

#### Phase 4: Command Integration
7. **Update commands to support multiple zones** ✅
   - `create-rules` - Apply profile to multiple zones
   - `delete-rules` - Delete rules from multiple zones
   - `list-rules` - List rules for multiple zones
   - `update-rules` - Update rules on multiple zones
   - `get-settings` / `set-settings` - Get/set settings on multiple zones

#### Phase 5: Output & Reporting
8. **Create multi-zone output formatting** ✅ (partial)
   - Clear zone separators in output
   - Option for summary-only mode (`--summary`) - NOT IMPLEMENTED
   - Option for CSV/JSON output for scripting - NOT IMPLEMENTED

9. **Error handling** ✅ (partial)
   - Continue on error (don't stop at first failure)
   - Collect and report all errors at end
   - Add `--stop-on-error` flag for strict mode - NOT IMPLEMENTED

#### Phase 6: Documentation & Testing
10. **Update README.md** ✅
    - Document zones file format
    - Add examples for multi-zone usage
    - Update usage section with new arguments

11. **Create test cases** - NOT IMPLEMENTED
    - Test zones file parsing (valid, invalid, empty)
    - Test multiple `-d` accumulation
    - Test confirmation prompt behavior
    - Test command execution on multiple zones

### Example Usage (Target)
```bash
# Multiple -d arguments
./cloudflare-wordpress-rules.sh -d site1.com -d site2.com -d site3.com -c create-rules default
# Output: "This will affect 3 zone(s). Continue? [y/N]"

# Using zones file
./cloudflare-wordpress-rules.sh -zf zones.txt -c create-rules default

# Skip confirmation with -y
./cloudflare-wordpress-rules.sh -zf zones.txt -c delete-rules -y

# Combined (zones file + additional domain)
./cloudflare-wordpress-rules.sh -zf zones.txt -d extra-site.com -c list-rules