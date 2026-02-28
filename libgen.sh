#!/usr/bin/env bash
# Regenerate library.json from the skills/ and agents/ directories on disk.
# Preserves all metadata for specs already present in library.json;
# creates minimal stubs for newly discovered specs.
#
# Adapted from: https://github.com/akm-rs/akm (bin/akm cmd_skills_libgen)
#
# Usage: ./libgen.sh [TARGET_DIR]
#   TARGET_DIR defaults to the directory containing this script.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

_check_deps() {
  if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is required but not installed. Run: sudo apt install jq${NC}" >&2
    exit 1
  fi
}

_extract_fm_field() {
  local file="$1" field="$2"
  sed 's/\r$//' "$file" \
    | sed -n '/^---$/,/^---$/p' \
    | grep -m1 "^${field}:" \
    | sed "s/^${field}:[[:space:]]*//; s/^[\"']//; s/[\"']$//" || true
}

_skills_libgen_for_dir() {
  local target_dir="$1"
  local library_file="$target_dir/library.json"

  # Load existing library.json — preserve ALL metadata for known specs
  local -A existing_specs
  if [[ -f "$library_file" ]]; then
    while IFS= read -r spec_json; do
      local eid
      eid="$(echo "$spec_json" | jq -r '.id')"
      existing_specs["$eid"]="$spec_json"
    done < <(jq -c '.specs[]' "$library_file")
  fi

  local specs_json="[]"
  local count=0

  # Scan skills
  if [[ -d "$target_dir/skills" ]]; then
    for skill_dir in "$target_dir/skills"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local id
      id="$(basename "$skill_dir")"
      local md_file="$skill_dir/SKILL.md"
      [[ -f "$md_file" ]] || continue

      ((count++)) || true

      if [[ -n "${existing_specs[$id]+x}" ]]; then
        specs_json=$(echo "$specs_json" | jq --argjson spec "${existing_specs[$id]}" '. + [$spec]')
      else
        local name desc
        name="$(_extract_fm_field "$md_file" "name")"
        desc="$(_extract_fm_field "$md_file" "description")"
        [[ -z "$name" ]] && name="$id"
        [[ -z "$desc" ]] && desc=""
        specs_json=$(echo "$specs_json" | jq \
          --arg id "$id" --arg type "skill" --arg name "$name" --arg desc "$desc" \
          '. + [{"id":$id,"type":$type,"name":$name,"description":$desc,"core":false,"tags":[],"triggers":{}}]')
      fi
    done
  fi

  # Scan agents
  if [[ -d "$target_dir/agents" ]]; then
    for md_file in "$target_dir/agents"/*.md; do
      [[ -f "$md_file" ]] || continue
      local id
      id="$(basename "$md_file" .md)"
      ((count++)) || true

      if [[ -n "${existing_specs[$id]+x}" ]]; then
        specs_json=$(echo "$specs_json" | jq --argjson spec "${existing_specs[$id]}" '. + [$spec]')
      else
        local name desc
        name="$(_extract_fm_field "$md_file" "name")"
        desc="$(_extract_fm_field "$md_file" "description")"
        [[ -z "$name" ]] && name="$id"
        [[ -z "$desc" ]] && desc=""
        specs_json=$(echo "$specs_json" | jq \
          --arg id "$id" --arg type "agent" --arg name "$name" --arg desc "$desc" \
          '. + [{"id":$id,"type":$type,"name":$name,"description":$desc,"core":false,"tags":[],"triggers":{}}]')
      fi
    done
  fi

  # Write library.json
  echo "$specs_json" | jq '{version: 1, specs: .}' > "$library_file"

  echo -e "${GREEN}Library regenerated ($count specs)${NC}"
  echo "  Specs on disk: $count"
}

# --- Main ---

_check_deps

target_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [[ ! -d "$target_dir/skills" && ! -d "$target_dir/agents" ]]; then
  echo -e "${RED}Error: Cannot locate a directory with skills/ or agents/ in $target_dir${NC}" >&2
  exit 1
fi

_skills_libgen_for_dir "$target_dir"
