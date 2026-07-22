# TODO

## General

* Add --csv to list-rules command and export data as csv.
* Cleanup repository, overall it's structure is all over the place.
* Improve article on managingwp.io
* ~~Look at symlinking the default.json and default.md so that it doesn't need to be copied for each new version.~~ **DONE** — `default.json`/`.md` are now symlinks to latest numbered release (`mwp-rules-v207`)
* move include files into inc folder?
* document how to use the repo.
* Convert code to new API calls.
* Create bash and zsh auto-completion scripts.

## Completed (v2.4.0)

* Replaced `mwp-rules-latest` with `mwp-rules-beta` (v3 schema)
* Created `bin/build.sh` — unified build orchestrator
* Created `bin/release.sh` — promote beta to numbered release
* Updated `.gitignore` to allowlist bundled profiles
* Added symlink safety to `generate-md.sh`
* Removed stale `mwp-rules-v206` (unversioned copy of latest)
