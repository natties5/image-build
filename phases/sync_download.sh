#!/usr/bin/env bash
# phases/sync_download.sh — Rule-driven image discovery, dry-run, and download.
# See: /rebuild-project-doc/02_DOWNLOAD_IMAGE_SYSTEM.md
#
# Usage:
#   sync_download.sh --os <name> [--version <ver>] [--dry-run]
#
# HARD RULES (from 10_AI_IMPLEMENTATION_NOTES.md):
#   - Never hardcode image URLs — use discovery engine
#   - Never mark .ready before checksum passes
#   - Never mix discovery logic with download logic
#   - Input = .env, Output = .json, Quick state = flag files
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/core_paths.sh
source "${SCRIPT_DIR}/../lib/core_paths.sh"
# shellcheck source=../lib/common_utils.sh
source "${LIB_DIR}/common_utils.sh"

PHASE="sync"
CURL_FETCH_TIMEOUT="${CURL_FETCH_TIMEOUT:-30}"
_CURL_OPTS=(-s -L --max-time "${CURL_FETCH_TIMEOUT}" --retry 2 --retry-delay 3)

# ─── Sync config variables (populated by load_sync_config) ────────────────────
OS_FAMILY=""
MIN_VERSION=""
TRACKED_VERSIONS=""
DISCOVERY_MODE=""
LATEST_LOGIC=""
INDEX_URL_TEMPLATE=""
INDEX_URL_FALLBACK=""
CHECKSUM_FILE=""
HASH_ALGO=""
ARCH_PRIORITY=""
FORMAT_PRIORITY=""
IMAGE_REGEX=""
CODENAME_MAP=""
# shellcheck disable=SC2034
DRY_RUN_SUPPORTED="yes"

# ─── Argument parsing ─────────────────────────────────────────────────────────
_SYNC_OPT_OS=""
_SYNC_OPT_VERSION=""
_SYNC_OPT_DRY_RUN=false

parse_args() {
  [[ $# -gt 0 ]] || {
    echo "Usage: $0 --os <name> [--version <ver>] [--dry-run]" >&2
    exit 2
  }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os)       _SYNC_OPT_OS="$2"; shift 2 ;;
      --version)  _SYNC_OPT_VERSION="$2"; shift 2 ;;
      --dry-run)  _SYNC_OPT_DRY_RUN=true; shift ;;
      --help|-h)
        echo "Usage: $0 --os <name> [--version <ver>] [--dry-run]"
        exit 0
        ;;
      *) util_die "Unknown argument: $1" 2 ;;
    esac
  done
  [[ -n "$_SYNC_OPT_OS" ]] || util_die "--os <name> is required" 2
}

# ─── Load OS sync config ──────────────────────────────────────────────────────
load_sync_config() {
  local os="$1"
  local cfg="${OS_CONFIG_DIR}/${os}/sync.env"
  [[ -f "$cfg" ]] || util_die "Sync config not found: ${cfg}"
  # shellcheck source=/dev/null
  source "$cfg"
  [[ -n "$OS_FAMILY" ]]          || util_die "OS_FAMILY not set in $cfg"
  [[ -n "$MIN_VERSION" ]]        || util_die "MIN_VERSION not set in $cfg"
  [[ -n "$TRACKED_VERSIONS" ]]   || util_die "TRACKED_VERSIONS not set in $cfg"
  [[ -n "$DISCOVERY_MODE" ]]     || util_die "DISCOVERY_MODE not set in $cfg"
  [[ -n "$INDEX_URL_TEMPLATE" ]] || util_die "INDEX_URL_TEMPLATE not set in $cfg"
  [[ -n "$CHECKSUM_FILE" ]]      || util_die "CHECKSUM_FILE not set in $cfg"
  [[ -n "$HASH_ALGO" ]]          || util_die "HASH_ALGO not set in $cfg"
  [[ -n "$IMAGE_REGEX" ]]        || util_die "IMAGE_REGEX not set in $cfg"
  util_log_info "Loaded sync config: $cfg"
}

# ─── Version comparison ───────────────────────────────────────────────────────
# Returns 0 if v1 >= v2 (supports major.minor.patch format)
version_ge() {
  local v1="$1" v2="$2"
  # Guard: if both are identical strings (including "latest"), return true
  [[ "$v1" == "$v2" ]] && return 0
  # Guard: non-numeric version strings always pass
  [[ "$v1" =~ ^[0-9] ]] || return 0
  [[ "$v2" =~ ^[0-9] ]] || return 0
  awk -v v1="$v1" -v v2="$v2" 'BEGIN {
    n1 = split(v1, a, ".")
    n2 = split(v2, b, ".")
    maxn = (n1 > n2) ? n1 : n2
    for (i = 1; i <= maxn; i++) {
      ai = (a[i] == "") ? 0 : a[i] + 0
      bi = (b[i] == "") ? 0 : b[i] + 0
      if (ai > bi) exit 0
      if (ai < bi) exit 1
    }
    exit 0
  }'
}

# ─── Codename resolution ──────────────────────────────────────────────────────
# Looks up version in CODENAME_MAP ("12:bookworm 13:trixie") and returns codename.
resolve_codename() {
  local version="$1"
  [[ -z "$CODENAME_MAP" ]] && echo "" && return
  local pair
  for pair in $CODENAME_MAP; do
    local k="${pair%%:*}" v="${pair##*:}"
    [[ "$k" == "$version" ]] && echo "$v" && return
  done
  echo ""
}

# ─── URL template resolution ──────────────────────────────────────────────────
# Substitutes {VERSION} and {CODENAME} in a template string.
resolve_url_template() {
  local tmpl="$1" version="$2" codename="${3:-}"
  local url="${tmpl/\{VERSION\}/$version}"
  url="${url/\{CODENAME\}/$codename}"
  # Strip trailing slash for consistent URL building
  echo "${url%/}"
}

# ─── Checksum content fetch ───────────────────────────────────────────────────
fetch_checksum_content() {
  local index_url="$1" checksum_file="$2"
  local full_url="${index_url}/${checksum_file}"
  util_log_info "Fetching checksum: ${full_url}"
  local content
  content=$(curl "${_CURL_OPTS[@]}" "$full_url") || {
    util_log_error "curl failed for: ${full_url}"
    return 1
  }
  [[ -n "$content" ]] || { util_log_error "Empty response from: ${full_url}"; return 1; }
  echo "$content"
}

# ─── Index scan: find checksum file URL in directory listing ──────────────────
discover_checksum_url() {
  local index_url="$1" checksum_pattern="$2"
  util_log_info "Scanning index for checksum pattern /${checksum_pattern}/: ${index_url}/"
  local html
  html=$(curl "${_CURL_OPTS[@]}" "${index_url}/") || {
    util_log_error "Failed to fetch index listing: ${index_url}/"
    return 1
  }
  # Extract href values from anchor tags
  local found_href
  found_href=$(echo "$html" \
    | grep -oE 'href="[^"]+"' \
    | sed 's/href="//;s/"//' \
    | grep -E "$checksum_pattern" \
    | sort -V \
    | tail -1) || true
  [[ -n "$found_href" ]] || {
    util_log_error "No checksum file matching /${checksum_pattern}/ found at: ${index_url}/"
    return 1
  }
  # Build absolute URL
  if [[ "$found_href" == http* ]]; then
    echo "$found_href"
  else
    local clean="${found_href#/}"
    echo "${index_url}/${clean}"
  fi
}

# ─── Parse checksum file lines ────────────────────────────────────────────────
# Normalizes two formats:
#   Format 1 (GNU): "HASH  *filename" or "HASH  filename"
#   Format 2 (BSD/Fedora): "SHA256 (filename) = HASH"
# Output: lines of "HASH FILENAME" (space-separated, no asterisk)
parse_checksum_lines() {
  local content="$1"
  # Normalize BSD format to GNU format first
  local normalized
  normalized=$(printf '%s\n' "$content" \
    | sed -E 's/^[A-Z0-9]+ \(([^)]+)\) = ([a-fA-F0-9]+)$/\2  \1/')
  # Parse GNU format lines
  printf '%s\n' "$normalized" \
    | grep -E '^[a-fA-F0-9]{32,}[[:space:]]' \
    | awk '{hash=$1; fname=$NF; sub(/^\*/, "", fname); if (fname != "") print hash, fname}'
}

# ─── Arch detection ───────────────────────────────────────────────────────────
filename_arch() {
  local fname="$1"
  if echo "$fname" | grep -qiE 'amd64'; then
    echo "amd64"
  elif echo "$fname" | grep -qiE 'x86_64'; then
    echo "x86_64"
  else
    echo ""
  fi
}

# ─── Format detection ─────────────────────────────────────────────────────────
filename_format() {
  local fname="$1"
  case "${fname##*.}" in
    img)   echo "img" ;;
    qcow2) echo "qcow2" ;;
    raw)   echo "raw" ;;
    *)     echo "" ;;
  esac
}

# ─── Priority scores (lower = preferred) ──────────────────────────────────────
arch_score() {
  local arch="$1"
  local i=0
  for p in $ARCH_PRIORITY; do
    [[ "$p" == "$arch" ]] && echo "$i" && return
    (( i++ )) || true
  done
  echo "99"
}

format_score() {
  local fmt="$1"
  local i=0
  for p in $FORMAT_PRIORITY; do
    [[ "$p" == "$fmt" ]] && echo "$i" && return
    (( i++ )) || true
  done
  echo "99"
}

# ─── Filter candidates and select winner ──────────────────────────────────────
# Input : newline-separated "HASH FILENAME" lines; index_url; version
# Output: single line "HASH FILENAME DOWNLOAD_URL ARCH FORMAT"
filter_and_select() {
  local checksum_lines="$1" index_url="$2" version="$3"
  local effective_regex="${IMAGE_REGEX/\{VERSION\}/$version}"

  # Collect candidates: "ARCH_SCORE:FORMAT_SCORE:HASH:FILENAME:ARCH:FMT"
  local candidates=()
  while IFS=" " read -r hash filename; do
    [[ -z "$filename" ]] && continue
    # Apply IMAGE_REGEX filter
    [[ "$filename" =~ $effective_regex ]] || continue
    local arch fmt
    arch="$(filename_arch "$filename")"
    fmt="$(filename_format "$filename")"
    [[ -z "$arch" || -z "$fmt" ]] && continue
    local sa sf
    sa="$(arch_score "$arch")"
    sf="$(format_score "$fmt")"
    candidates+=("${sa}:${sf}:${hash}:${filename}:${arch}:${fmt}")
  done <<< "$checksum_lines"

  if [[ ${#candidates[@]} -eq 0 ]]; then
    util_log_error "No candidates matched regex '${effective_regex}' in checksum file"
    return 1
  fi

  util_log_info "Candidate count (before scoring): ${#candidates[@]}"

  # Sort: for sort_version, sort by filename (version-aware) so last = highest
  # Then sort by arch_score asc, format_score asc — take last line (best match)
  local sorted_winner
  if [[ "$LATEST_LOGIC" == "sort_version" ]]; then
    # Sort by filename field (4th colon-delimited) version-aware, then by scores
    sorted_winner=$(printf '%s\n' "${candidates[@]}" \
      | sort -t: -k4 -V \
      | sort -t: -k1,1n -k2,2n \
      | tail -1)
  else
    # current_folder / latest_symlink: sort only by score, take best
    sorted_winner=$(printf '%s\n' "${candidates[@]}" \
      | sort -t: -k1,1n -k2,2n \
      | head -1)
  fi

  # Parse winner fields
  local sa sf w_hash w_file w_arch w_fmt
  IFS=: read -r sa sf w_hash w_file w_arch w_fmt <<< "$sorted_winner"

  util_log_info "Selected: ${w_file} [arch=${w_arch} fmt=${w_fmt} sa=${sa} sf=${sf}]"
  local download_url="${index_url}/${w_file}"
  echo "${w_hash} ${w_file} ${download_url} ${w_arch} ${w_fmt}"
}

# ─── Write JSON manifest ──────────────────────────────────────────────────────
write_manifest() {
  local os_family="$1" version="$2" mode="$3" status="$4"
  local filename="$5" hash="$6" arch="$7" fmt="$8"
  local download_url="$9" checksum_source="${10}"
  local failure_reason="${11:-}"
  local json_path
  json_path="$(core_state_json "$PHASE" "$os_family" "$version")"
  local workspace_path="${IMAGES_DIR}/${os_family}/${version}/${filename}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)"
  cat > "$json_path" <<EOF
{
  "os_family": "$(util_escape_json "$os_family")",
  "version": "$(util_escape_json "$version")",
  "status": "$(util_escape_json "$status")",
  "mode": "$(util_escape_json "$mode")",
  "arch_selected": "$(util_escape_json "$arch")",
  "format_selected": "$(util_escape_json "$fmt")",
  "filename": "$(util_escape_json "$filename")",
  "download_url": "$(util_escape_json "$download_url")",
  "checksum": "$(util_escape_json "$hash")",
  "hash_algo": "$(util_escape_json "$HASH_ALGO")",
  "checksum_source": "$(util_escape_json "$checksum_source")",
  "workspace_path": "$(util_escape_json "$workspace_path")",
  "discovery": {
    "mode": "$(util_escape_json "$DISCOVERY_MODE")",
    "index_url_template": "$(util_escape_json "$INDEX_URL_TEMPLATE")",
    "latest_logic": "$(util_escape_json "$LATEST_LOGIC")"
  },
  "failure_reason": "$(util_escape_json "$failure_reason")",
  "generated_at": "$(util_escape_json "$ts")"
}
EOF
  util_log_info "Manifest written: $json_path"
}

# ─── Write failure outputs ────────────────────────────────────────────────────
write_failure() {
  local os_family="$1" version="$2" mode="$3" reason="$4"
  local json_path; json_path="$(core_state_json "$PHASE" "$os_family" "$version")"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)"
  cat > "$json_path" <<EOF
{
  "os_family": "$(util_escape_json "$os_family")",
  "version": "$(util_escape_json "$version")",
  "status": "failed",
  "mode": "$(util_escape_json "$mode")",
  "filename": "",
  "download_url": "",
  "checksum": "",
  "hash_algo": "$(util_escape_json "$HASH_ALGO")",
  "failure_reason": "$(util_escape_json "$reason")",
  "generated_at": "$(util_escape_json "$ts")"
}
EOF
  # Clear any success flags, set failed flag
  for flag_name in ready dryrun-ok; do
    rm -f "$(core_flag_path "$PHASE" "$os_family" "$version" "$flag_name")"
  done
  touch "$(core_flag_path "$PHASE" "$os_family" "$version" "failed")"
  util_log_error "Sync FAILED [${os_family} ${version}]: ${reason}"
}

# ─── Hash verification ────────────────────────────────────────────────────────
verify_file_hash() {
  local filepath="$1" expected_hash="$2" algo="$3"
  util_log_info "Verifying ${algo} hash: $(basename "$filepath")"
  local actual_hash
  case "$algo" in
    sha256) actual_hash=$(sha256sum "$filepath" | awk '{print $1}') ;;
    sha512) actual_hash=$(sha512sum "$filepath" | awk '{print $1}') ;;
    sha384) actual_hash=$(sha384sum "$filepath" | awk '{print $1}') ;;
    md5)    actual_hash=$(md5sum "$filepath" | awk '{print $1}') ;;
    *)      util_die "Unsupported hash algo: ${algo}. Supported: sha256 sha512 sha384 md5" ;;
  esac
  if [[ "$actual_hash" == "$expected_hash" ]]; then
    util_log_info "Hash OK: ${actual_hash}"
    return 0
  else
    util_log_error "Hash MISMATCH — expected: ${expected_hash} | actual: ${actual_hash}"
    return 1
  fi
}

# ─── Download image (resume-capable) ─────────────────────────────────────────
download_image() {
  local url="$1" dest_dir="$2" filename="$3"
  local dest_path="${dest_dir}/${filename}"
  [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
  # Check available disk space (require at least 3GB free)
  local avail_mb
  avail_mb="$(df -m "$dest_dir" 2>/dev/null | awk 'NR==2{print $4}')" || true
  if [[ -n "$avail_mb" ]] && (( avail_mb < 3000 )); then
    util_log_error "Insufficient disk space: ${avail_mb}MB available in ${dest_dir} (need 3000MB)"
    return 1
  fi
  util_log_info "Downloading: ${url}"
  util_log_info "Destination: ${dest_path}"
  if command -v wget >/dev/null 2>&1; then
    wget --continue \
         --timeout="${DOWNLOAD_TIMEOUT:-3600}" \
         --tries=3 \
         --progress=dot:giga \
         -O "$dest_path" \
         "$url" >/dev/null
  elif command -v curl >/dev/null 2>&1; then
    curl -L --continue-at - --max-time "${DOWNLOAD_TIMEOUT:-3600}" --retry 2 \
         --progress-bar \
         -o "$dest_path" "$url" >/dev/null
  else
    util_die "Neither wget nor curl is available"
  fi
  [[ -f "$dest_path" ]] || { util_log_error "Download produced no file: ${dest_path}"; return 1; }
  local size; size=$(wc -c < "$dest_path" | tr -d ' ')
  util_log_info "Download complete: ${size} bytes"
}

# ─── Process a single OS version ─────────────────────────────────────────────
process_version() {
  local os_family="$1" version="$2" dry_run="$3"
  local mode="dry-run"; $dry_run || mode="download"

  # Set up log file for this os/version
  local log_path; log_path="$(core_log_path "$PHASE" "$os_family" "$version")"
  util_init_log_file "$log_path"
  util_log_info "=== sync_download: ${os_family} ${version} [${mode}] ==="

  # ── VERSION FLOOR CHECK ────────────────────────────────────────────────────
  if ! version_ge "$version" "$MIN_VERSION"; then
    util_log_info "Skipping ${os_family} ${version}: below min_version floor (${MIN_VERSION})"
    return 0
  fi
  # ?? RESOLVE INDEX URL ??????????????????????????????????????????????????????
  local codename=""
  [[ -n "$CODENAME_MAP" ]] && codename="$(resolve_codename "$version")"
  local primary_index_url fallback_index_url index_url index_url_source
  primary_index_url="$(resolve_url_template "$INDEX_URL_TEMPLATE" "$version" "$codename")"
  index_url="$primary_index_url"
  index_url_source="primary"
  util_log_info "Index URL (primary): ${primary_index_url}"

  # ?? FETCH CHECKSUM CONTENT (primary -> fallback) ??????????????????????????
  local checksum_content="" checksum_source="" fetch_ok=false

  if [[ "$DISCOVERY_MODE" == "checksum_driven" ]]; then
    checksum_source="${index_url}/${CHECKSUM_FILE}"
    checksum_content="$(fetch_checksum_content "$index_url" "$CHECKSUM_FILE" 2>/dev/null)" || true
    if [[ -n "$checksum_content" ]]; then
      fetch_ok=true
    fi

    if [[ "$fetch_ok" != "true" ]] && [[ -n "${INDEX_URL_FALLBACK:-}" ]]; then
      fallback_index_url="$(resolve_url_template "$INDEX_URL_FALLBACK" "$version" "$codename")"
      util_log_warn "Primary checksum fetch failed, trying fallback: ${fallback_index_url}"
      index_url="$fallback_index_url"
      index_url_source="fallback"
      checksum_source="${index_url}/${CHECKSUM_FILE}"
      checksum_content="$(fetch_checksum_content "$index_url" "$CHECKSUM_FILE" 2>/dev/null)" || true
      [[ -n "$checksum_content" ]] && fetch_ok=true
    fi

    if [[ "$fetch_ok" != "true" ]]; then
      write_failure "$os_family" "$version" "$mode" \
        "Failed to fetch checksum file from primary/fallback for: ${CHECKSUM_FILE}"
      return 1
    fi

  elif [[ "$DISCOVERY_MODE" == "index_scan" ]]; then
    checksum_source="$(discover_checksum_url "$index_url" "$CHECKSUM_FILE" 2>/dev/null)" || true
    if [[ -n "$checksum_source" ]]; then
      util_log_info "Discovered checksum URL: ${checksum_source}"
      checksum_content="$(curl "${_CURL_OPTS[@]}" "$checksum_source" 2>/dev/null)" || true
      [[ -n "$checksum_content" ]] && fetch_ok=true
    fi

    if [[ "$fetch_ok" != "true" ]] && [[ -n "${INDEX_URL_FALLBACK:-}" ]]; then
      fallback_index_url="$(resolve_url_template "$INDEX_URL_FALLBACK" "$version" "$codename")"
      util_log_warn "Primary index-scan failed, trying fallback: ${fallback_index_url}"
      index_url="$fallback_index_url"
      index_url_source="fallback"
      checksum_source="$(discover_checksum_url "$index_url" "$CHECKSUM_FILE" 2>/dev/null)" || true
      if [[ -n "$checksum_source" ]]; then
        util_log_info "Discovered checksum URL (fallback): ${checksum_source}"
        checksum_content="$(curl "${_CURL_OPTS[@]}" "$checksum_source" 2>/dev/null)" || true
        [[ -n "$checksum_content" ]] && fetch_ok=true
      fi
    fi

    if [[ "$fetch_ok" != "true" ]]; then
      write_failure "$os_family" "$version" "$mode" \
        "Failed to find/fetch checksum via index_scan from primary/fallback"
      return 1
    fi

  else
    util_die "Unknown DISCOVERY_MODE: ${DISCOVERY_MODE}"
  fi

  util_log_info "Using index URL source: ${index_url_source} (${index_url})"

  # Normalize hash-only per-file checksum content (e.g. Alpine .sha512)
  local _single_hash _cs_base _derived_file
  _single_hash="$(printf '%s' "$checksum_content" | tr -d '\r[:space:]')"
  if [[ "$_single_hash" =~ ^[a-fA-F0-9]{32,}$ ]]; then
    _cs_base="${checksum_source##*/}"
    _derived_file="${_cs_base%.sha256}"
    _derived_file="${_derived_file%.sha512}"
    _derived_file="${_derived_file%.SHA256}"
    _derived_file="${_derived_file%.SHA512}"
    if [[ -n "$_derived_file" ]] && [[ "$_derived_file" != "$_cs_base" ]]; then
      checksum_content="${_single_hash}  ${_derived_file}"
      util_log_info "Derived filename from checksum artifact: ${_derived_file}"
    fi
  fi


  local raw_line_count
  raw_line_count=$(printf '%s\n' "$checksum_content" | wc -l | tr -d ' ')
  util_log_info "Checksum source: ${checksum_source} (${raw_line_count} raw lines)"

  # ── PARSE CHECKSUM ENTRIES ─────────────────────────────────────────────────
  local parsed_lines
  parsed_lines="$(parse_checksum_lines "$checksum_content")"
  local candidate_count
  candidate_count=$(printf '%s\n' "$parsed_lines" | grep -c . 2>/dev/null || echo "0")
  util_log_info "Parsed entries: ${candidate_count}"

  # ── FILTER AND SELECT ──────────────────────────────────────────────────────
  local winner
  winner="$(filter_and_select "$parsed_lines" "$index_url" "$version")" || {
    write_failure "$os_family" "$version" "$mode" \
      "No matching candidate after applying IMAGE_REGEX='${IMAGE_REGEX}'"
    return 1
  }

  local w_hash w_file w_url w_arch w_fmt
  read -r w_hash w_file w_url w_arch w_fmt <<< "$winner"

  util_log_info "Winner:  ${w_file}"
  util_log_info "  URL:   ${w_url}"
  util_log_info "  Hash:  ${w_hash} (${HASH_ALGO})"
  util_log_info "  Arch:  ${w_arch}  Format: ${w_fmt}"

  # ── DRY-RUN PATH ──────────────────────────────────────────────────────────
  if $dry_run; then
    # Print result table to stdout
    printf "\n"
    printf "  %-12s %-10s %-50s\n" "OS" "Version" "Selected Image"
    printf "  %-12s %-10s %-50s\n" "$os_family" "$version" "$w_file"
    printf "  %-12s %-10s %-50s\n" "" "" "  ${HASH_ALGO}: ${w_hash}"
    printf "  %-12s %-10s %-50s\n" "" "" "  URL: ${w_url}"
    printf "\n"

    # Write manifest + flag (no download, no ready flag)
    write_manifest "$os_family" "$version" "dry-run" "dryrun-ok" \
      "$w_file" "$w_hash" "$w_arch" "$w_fmt" "$w_url" "$checksum_source" ""

    for flag_name in failed ready; do
      rm -f "$(core_flag_path "$PHASE" "$os_family" "$version" "$flag_name")"
    done
    touch "$(core_flag_path "$PHASE" "$os_family" "$version" "dryrun-ok")"
    util_log_info "Dry-run COMPLETE: ${os_family} ${version}"
    return 0
  fi

  # ── REAL DOWNLOAD PATH ─────────────────────────────────────────────────────
  local dest_dir="${IMAGES_DIR}/${os_family}/${version}"
  local dest_path="${dest_dir}/${w_file}"

  # Check if we have a valid cached file
  if [[ -f "$dest_path" ]]; then
    util_log_info "Local file exists — verifying cache: ${dest_path}"
    if verify_file_hash "$dest_path" "$w_hash" "$HASH_ALGO"; then
      util_log_info "Cache valid — skipping download"
      write_manifest "$os_family" "$version" "download" "cached-valid" \
        "$w_file" "$w_hash" "$w_arch" "$w_fmt" "$w_url" "$checksum_source" ""
      for flag_name in failed dryrun-ok; do
        rm -f "$(core_flag_path "$PHASE" "$os_family" "$version" "$flag_name")"
      done
      touch "$(core_flag_path "$PHASE" "$os_family" "$version" "ready")"
      return 0
    else
      util_log_warn "Cache invalid — removing and re-downloading"
      rm -f "$dest_path"
    fi
  fi

  # Download
  download_image "$w_url" "$dest_dir" "$w_file" || {
    write_failure "$os_family" "$version" "$mode" "Download failed: ${w_url}"
    return 1
  }

  # Verify after download — HARD FAIL if mismatch
  if ! verify_file_hash "$dest_path" "$w_hash" "$HASH_ALGO"; then
    util_log_error "Removing corrupt file: ${dest_path}"
    rm -f "$dest_path"
    write_failure "$os_family" "$version" "$mode" \
      "Checksum mismatch after download — file removed"
    return 1
  fi

  # Write success outputs
  write_manifest "$os_family" "$version" "download" "downloaded-valid" \
    "$w_file" "$w_hash" "$w_arch" "$w_fmt" "$w_url" "$checksum_source" ""

  for flag_name in failed dryrun-ok; do
    rm -f "$(core_flag_path "$PHASE" "$os_family" "$version" "$flag_name")"
  done
  # .ready flag written ONLY after checksum passes
  touch "$(core_flag_path "$PHASE" "$os_family" "$version" "ready")"
  util_log_info "Download COMPLETE and verified: ${os_family} ${version} → ${dest_path}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  core_ensure_runtime_dirs
  load_sync_config "$_SYNC_OPT_OS"

  # Determine which versions to process
  local versions_to_process=()
  if [[ -n "$_SYNC_OPT_VERSION" ]]; then
    versions_to_process=("$_SYNC_OPT_VERSION")
  else
    read -ra versions_to_process <<< "$TRACKED_VERSIONS"
  fi

  local had_failure=false
  for ver in "${versions_to_process[@]}"; do
    process_version "$_SYNC_OPT_OS" "$ver" "$_SYNC_OPT_DRY_RUN" || had_failure=true
  done

  if $had_failure; then
    util_log_error "One or more versions had failures. Logs: ${LOG_SYNC_DIR}/"
    exit 1
  fi

  util_log_info "sync_download complete for OS: ${_SYNC_OPT_OS}"
}

main "$@"
