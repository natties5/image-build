#!/usr/bin/env bash
set -Eeuo pipefail

# Session-scoped selected project (set by imagectl_select_project_interactive)
_IMAGECTL_CURRENT_PROJECT=""

# ── Phase helpers (formerly in control_main.sh) ───────────────────────────────

imagectl_phase_requires_version() {
  local phase="$1"
  case "$phase" in
    import|create|configure|clean|publish) return 0 ;;
    *) return 1 ;;
  esac
}

imagectl_phase_is_mutating() {
  local phase="$1"
  case "$phase" in
    import|create|configure|clean|publish) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Remote execution ──────────────────────────────────────────────────────────

imagectl_assert_version_in_manifest_remote() {
  local os="$1" version="$2"
  local v found="no"
  local -a versions=()
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  for v in "${versions[@]}"; do
    [[ "$v" == "$version" ]] && found="yes" && break
  done
  [[ "$found" == "yes" ]] || imagectl_die "version '$version' not in manifest for os '$os'"
}

imagectl_run_phase_remote() {
  local os="$1" phase="$2" version="${3:-}"
  local cmd expected_q

  cmd="$(imagectl_phase_command "$os" "$phase" "$version")" \
    || imagectl_die "phase '$phase' not available for os '$os'"
  imagectl_require_remote_repo_for_script

  if [[ "$phase" == "preflight" && -n "${EXPECTED_PROJECT_NAME:-}" ]]; then
    expected_q="$(printf '%q' "$EXPECTED_PROJECT_NAME")"
    cmd="EXPECTED_PROJECT_NAME=$expected_q $cmd"
  fi

  imagectl_log "run phase os=$os phase=$phase version=${version:-n/a}"
  imagectl_run_remote_repo_cmd "$cmd"
}

imagectl_run_discover_for_os() {
  local os="$1"
  imagectl_os_is_implemented "$os" || imagectl_die "os '$os' is not implemented yet"
  imagectl_log "run download/discover for os=$os"
  imagectl_run_phase_remote "$os" download
}

imagectl_prepare_remote_pipeline_context() {
  imagectl_load_jump_host_config
  imagectl_check_remote_connection >/dev/null
  imagectl_require_remote_repo_for_script
}

# ── Phase sequence ────────────────────────────────────────────────────────────

imagectl_auto_phase_list() {
  printf '%s\n' preflight import create configure clean publish
}

imagectl_auto_run_phase_sequence() {
  local os="$1" version="$2" fail_fast="${3:-yes}"
  local phases=() phase

  mapfile -t phases < <(imagectl_auto_phase_list)
  for phase in "${phases[@]}"; do
    if ! imagectl_run_phase_remote "$os" "$phase" "$version"; then
      imagectl_log "phase failed: $phase (os=$os version=$version)"
      [[ "$fail_fast" == "yes" ]] && return 1
    fi
  done
}

# ── Interactive helpers ───────────────────────────────────────────────────────

imagectl_select_os_interactive() {
  local options=()
  mapfile -t options < <(imagectl_list_supported_oses)
  imagectl_select_from_list "Select OS (เลือก OS)" "${options[@]}"
}

imagectl_select_version_from_manifest_remote_interactive() {
  local os="$1"
  local versions=()
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  imagectl_select_from_list "Select version for $os" "${versions[@]}"
}

# ── Project selection ─────────────────────────────────────────────────────────

# Scan config/openstack/project-*.env and let user pick.
# Sets _IMAGECTL_CURRENT_PROJECT and returns the project name.
imagectl_select_project_interactive() {
  local dir="$IMAGECTL_REPO_ROOT/config/openstack"
  local -a names=()
  local f name

  if [[ -d "$dir" ]]; then
    for f in "$dir"/project-*.env; do
      [[ -f "$f" ]] || continue
      name="$(grep -m1 '^EXPECTED_PROJECT_NAME=' "$f" 2>/dev/null | cut -d= -f2- || true)"
      [[ -n "$name" ]] && names+=("$name")
    done
  fi

  if [[ "${#names[@]}" -eq 0 ]]; then
    _IMAGECTL_CURRENT_PROJECT="$(imagectl_runtime_effective_local_value "EXPECTED_PROJECT_NAME" 2>/dev/null || true)"
    _IMAGECTL_CURRENT_PROJECT="${_IMAGECTL_CURRENT_PROJECT:-(default)}"
    imagectl_log "no project-*.env found; using: $_IMAGECTL_CURRENT_PROJECT"
  elif [[ "${#names[@]}" -eq 1 ]]; then
    _IMAGECTL_CURRENT_PROJECT="${names[0]}"
    imagectl_log "auto-selected project: $_IMAGECTL_CURRENT_PROJECT"
  else
    _IMAGECTL_CURRENT_PROJECT="$(imagectl_select_from_list "Select project (เลือก project)" "${names[@]}")"
  fi

  printf '%s' "$_IMAGECTL_CURRENT_PROJECT"
}

# ── Manual mode ───────────────────────────────────────────────────────────────

imagectl_manual_menu_once() {
  local os="$1" version="$2" action="$3"

  case "$action" in
    preflight|import|create|configure|clean|publish)
      if imagectl_phase_requires_version "$action"; then
        [[ -n "$version" ]] || imagectl_die "version required for action '$action'"
        imagectl_assert_version_in_manifest_remote "$os" "$version"
      fi
      if imagectl_phase_is_mutating "$action"; then
        imagectl_runtime_prepare_for_action "$action"
      fi
      imagectl_run_phase_remote "$os" "$action" "$version"
      ;;
    download)
      imagectl_run_phase_remote "$os" download
      ;;
    status)
      imagectl_require_remote_repo_for_script
      imagectl_run_remote_repo_cmd "git status --short --branch"
      ;;
    logs)
      imagectl_require_remote_repo_for_script
      imagectl_run_remote_repo_cmd "ls -1 logs | tail -n 30"
      ;;
    *)
      imagectl_die "unknown manual action: $action"
      ;;
  esac
}

imagectl_manual_prepare_selection() {
  local os="$1"
  imagectl_run_discover_for_os "$os"
  imagectl_select_version_from_manifest_remote_interactive "$os"
}

imagectl_manual_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline manual
  scripts/control.sh manual
  scripts/control.sh manual --os <name> --version <x.yz> --action <action>
EOF
}

imagectl_manual() {
  local os="" version="" action=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os)      os="${2:-}";      shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --action)  action="${2:-}";  shift 2 ;;
      -h|--help) imagectl_manual_usage; return 0 ;;
      *) imagectl_die "unknown manual argument: $1" ;;
    esac
  done

  imagectl_prepare_remote_pipeline_context

  if [[ -n "$action" ]]; then
    os="$(imagectl_require_supported_os "${os:-ubuntu}")"
    imagectl_os_is_implemented "$os" || imagectl_die "os '$os' is not implemented yet"
    if imagectl_phase_requires_version "$action"; then
      [[ -n "$version" ]] || imagectl_die "--version required for action '$action'"
      imagectl_run_discover_for_os "$os"
      imagectl_assert_version_in_manifest_remote "$os" "$version"
    fi
    imagectl_manual_menu_once "$os" "$version" "$action"
    return 0
  fi

  os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  version="$(imagectl_manual_prepare_selection "$os")"

  while true; do
    local choice
    choice="$(imagectl_select_from_list "manual mode — os=$os version=$version" \
      "preflight" "import" "create" "configure" "clean" "publish" \
      "status" "logs" "change-version" "change-os" "back")"
    case "$choice" in
      change-version) version="$(imagectl_select_version_from_manifest_remote_interactive "$os")" ;;
      change-os)
        os="$(imagectl_select_os_interactive)"
        os="$(imagectl_require_supported_os "$os")"
        version="$(imagectl_manual_prepare_selection "$os")"
        ;;
      back) break ;;
      *)
        if imagectl_manual_menu_once "$os" "$version" "$choice"; then
          imagectl_log "action done: $choice  |  logs: $JUMP_HOST_REPO_PATH/logs"
        fi
        ;;
    esac
  done
}

# ── Auto modes (existing CLI-compatible) ──────────────────────────────────────

imagectl_auto_by_os_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline auto-by-os --os <name> [--fail-fast yes|no]
EOF
}

imagectl_auto_by_os() {
  local os="" fail_fast="yes" version
  local -a versions=() results=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os)        os="${2:-}";        shift 2 ;;
      --fail-fast) fail_fast="${2:-}"; shift 2 ;;
      -h|--help)   imagectl_auto_by_os_usage; return 0 ;;
      *) imagectl_die "unknown auto-by-os argument: $1" ;;
    esac
  done

  imagectl_prepare_remote_pipeline_context
  [[ -n "$os" ]] || os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  imagectl_os_is_implemented "$os" || imagectl_die "os '$os' is not implemented yet"

  imagectl_run_discover_for_os "$os"
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  if ! imagectl_runtime_prepare_for_full_pipeline; then
    imagectl_log "ERROR: runtime prepare failed — check settings/ files"
    return 1
  fi

  imagectl_log "auto-by-os start os=$os versions=${#versions[@]} fail_fast=$fail_fast"
  for version in "${versions[@]}"; do
    if imagectl_auto_run_phase_sequence "$os" "$version" "$fail_fast"; then
      results+=("$version:success")
    else
      results+=("$version:failed")
      [[ "$fail_fast" == "yes" ]] && break
    fi
  done

  imagectl_log "auto-by-os summary:"
  printf '%s\n' "${results[@]}" | sed 's/^/  /'
}

imagectl_auto_by_os_version_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline auto-by-os-version --os <name> [--version <x.yz>] [--fail-fast yes|no]
EOF
}

imagectl_auto_by_os_version() {
  local os="" version="" fail_fast="yes"
  local versions=() found="no" v

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os)        os="${2:-}";        shift 2 ;;
      --version)   version="${2:-}";   shift 2 ;;
      --fail-fast) fail_fast="${2:-}"; shift 2 ;;
      --stop-before|--resume-from|--cleanup-mode)
        shift 2  # kept for backward-compat; ignored
        ;;
      -h|--help) imagectl_auto_by_os_version_usage; return 0 ;;
      *) imagectl_die "unknown auto-by-os-version argument: $1" ;;
    esac
  done

  imagectl_prepare_remote_pipeline_context
  [[ -n "$os" ]] || os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  imagectl_os_is_implemented "$os" || imagectl_die "os '$os' is not implemented yet"

  imagectl_run_discover_for_os "$os"
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  if ! imagectl_runtime_prepare_for_full_pipeline; then
    imagectl_log "ERROR: runtime prepare failed — check settings/ files"
    return 1
  fi

  if [[ -z "$version" ]]; then
    version="$(imagectl_select_from_list "Select version (os=$os)" "${versions[@]}")"
  else
    for v in "${versions[@]}"; do
      [[ "$v" == "$version" ]] && found="yes" && break
    done
    [[ "$found" == "yes" ]] || imagectl_die "version '$version' not in manifest for os '$os'"
  fi

  imagectl_log "auto-by-os-version start os=$os version=$version fail_fast=$fail_fast"
  imagectl_auto_run_phase_sequence "$os" "$version" "$fail_fast"
  imagectl_log "auto-by-os-version done os=$os version=$version"
}

# ── Pipeline status / logs (existing) ────────────────────────────────────────

imagectl_pipeline_status() {
  imagectl_prepare_remote_pipeline_context
  imagectl_run_remote_repo_cmd "git status --short --branch && echo '--- logs ---' && ls -1 logs | tail -n 15"
}

imagectl_pipeline_logs() {
  imagectl_prepare_remote_pipeline_context
  imagectl_run_remote_repo_cmd "ls -1 logs | tail -n 30"
}

# ── NEW: Full Run ─────────────────────────────────────────────────────────────

imagectl_pipeline_full_run() {
  imagectl_prepare_remote_pipeline_context

  local oses=() os versions=() version
  local -a results=()
  mapfile -t oses < <(imagectl_list_supported_oses)

  for os in "${oses[@]}"; do
    imagectl_os_is_implemented "$os" || continue
    imagectl_log "full-run: discover os=$os"
    imagectl_run_discover_for_os "$os"
  done

  if ! imagectl_runtime_prepare_for_full_pipeline; then
    imagectl_log "ERROR: runtime prepare failed — check settings/ files"
    return 1
  fi

  for os in "${oses[@]}"; do
    imagectl_os_is_implemented "$os" || continue
    mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")

    for version in "${versions[@]}"; do
      imagectl_log "full-run: start os=$os version=$version"
      if imagectl_auto_run_phase_sequence "$os" "$version" "no"; then
        results+=("$os $version: SUCCESS")
      else
        results+=("$os $version: FAILED")
      fi
    done
  done

  imagectl_log "full-run summary:"
  printf '%s\n' "${results[@]}" | sed 's/^/  /'
}

# ── NEW: By Phase ─────────────────────────────────────────────────────────────

imagectl_pipeline_by_phase() {
  imagectl_prepare_remote_pipeline_context

  local os versions=() version phases=() phase

  os="$(imagectl_select_os_interactive)"
  os="$(imagectl_require_supported_os "$os")"
  imagectl_os_is_implemented "$os" || imagectl_die "os '$os' not fully implemented (only download available)"

  imagectl_run_discover_for_os "$os"
  mapfile -t versions < <(imagectl_require_versions_from_manifest_remote "$os")
  version="$(imagectl_select_from_list "Select version for $os" "${versions[@]}")"

  mapfile -t phases < <(imagectl_auto_phase_list)
  phase="$(imagectl_select_from_list "Select phase for $os $version" "${phases[@]}")"

  if imagectl_phase_is_mutating "$phase"; then
    if ! imagectl_runtime_prepare_for_action "$phase"; then
      imagectl_log "ERROR: runtime prepare failed for phase=$phase — check settings/ files"
      return 1
    fi
  fi

  imagectl_run_phase_remote "$os" "$phase" "$version"
}

# ── NEW: Resume ───────────────────────────────────────────────────────────────

# Resume a pipeline that has a failed phase.
# Reads _IMAGECTL_STATE_MAP (populated by imagectl_status_load).
imagectl_pipeline_resume() {
  imagectl_prepare_remote_pipeline_context

  # Load states if not already loaded
  if [[ "${#_IMAGECTL_STATE_MAP[@]}" -eq 0 ]]; then
    imagectl_log "loading state from remote…"
    imagectl_status_load
  fi

  if [[ "${#_IMAGECTL_STATE_MAP[@]}" -eq 0 ]]; then
    printf 'No state files found on remote. Nothing to resume.\n'
    return 0
  fi

  # Collect versions with at least one failed phase
  declare -A _failed_map=()
  local key val os version phase

  for key in "${!_IMAGECTL_STATE_MAP[@]}"; do
    val="${_IMAGECTL_STATE_MAP[$key]}"
    [[ "$val" == "failed" ]] || continue
    os="${key%%/*}"; local rest="${key#*/}"
    version="${rest%%/*}"; phase="${rest#*/}"
    local vk="$os/$version"
    if [[ -n "${_failed_map[$vk]:-}" ]]; then
      _failed_map["$vk"]="${_failed_map[$vk]}, $phase"
    else
      _failed_map["$vk"]="$phase"
    fi
  done

  if [[ "${#_failed_map[@]}" -eq 0 ]]; then
    printf 'No failed pipelines found.\n'
    return 0
  fi

  printf '\nพบ pipeline ที่ยังไม่เสร็จ (Found incomplete pipelines):\n'
  local k
  for k in "${!_failed_map[@]}"; do
    printf '  %s  →  failed at: %s\n' "$k" "${_failed_map[$k]}"
  done
  printf '\n'

  # Build selection list
  local -a options=()
  for k in "${!_failed_map[@]}"; do
    options+=("$k  (failed: ${_failed_map[$k]})")
  done
  options+=("Back (กลับ)")

  local choice
  choice="$(imagectl_select_from_list "Select pipeline to resume (เลือก pipeline)" "${options[@]}")"
  [[ "$choice" != "Back (กลับ)" ]] || return 0

  # Parse "os/version  (failed: ...)"
  local selected_key="${choice%%  (*}"
  local sel_os="${selected_key%%/*}"
  local sel_version="${selected_key#*/}"

  # Determine resume phase (first failed phase in order)
  local phases=() p resume_phase=""
  mapfile -t phases < <(imagectl_auto_phase_list)
  for p in "${phases[@]}"; do
    local st="${_IMAGECTL_STATE_MAP[$selected_key/$p]:-}"
    if [[ "$st" == "failed" ]]; then
      resume_phase="$p"
      break
    fi
  done

  if [[ -z "$resume_phase" ]]; then
    resume_phase="$(imagectl_select_from_list "Select phase to resume from" "${phases[@]}")"
  fi

  imagectl_log "resume: os=$sel_os version=$sel_version from=$resume_phase"

  # Run all phases from resume_phase onwards
  local start="no"
  for p in "${phases[@]}"; do
    [[ "$p" == "$resume_phase" ]] && start="yes"
    [[ "$start" == "yes" ]] || continue
    if imagectl_phase_is_mutating "$p"; then
      imagectl_runtime_prepare_for_action "$p"
    fi
    if ! imagectl_run_phase_remote "$sel_os" "$p" "$sel_version"; then
      imagectl_log "resume: phase $p failed — stopping"
      return 1
    fi
  done

  imagectl_log "resume done: os=$sel_os version=$sel_version"
}

# ── Menu handlers ─────────────────────────────────────────────────────────────

imagectl_menu_run() {
  # Select project once at the start of Run
  imagectl_select_project_interactive >/dev/null

  while true; do
    local label="Run (รัน pipeline)"
    [[ -z "$_IMAGECTL_CURRENT_PROJECT" ]] || label+=" — project: $_IMAGECTL_CURRENT_PROJECT"

    local choice
    choice="$(imagectl_select_from_list "$label" \
      "Full Run        (ทุก OS ทุก version)" \
      "By OS           (เลือก OS)" \
      "By Version      (เลือก OS + version)" \
      "By Phase        (เลือก OS + version + phase)" \
      "Change Project  (เปลี่ยน project)" \
      "Back            (กลับ)")"

    case "$choice" in
      "Full Run"*)      imagectl_pipeline_full_run    || imagectl_log "full-run ended with error" ;;
      "By OS"*)         imagectl_auto_by_os            || imagectl_log "by-os ended with error" ;;
      "By Version"*)    imagectl_auto_by_os_version    || imagectl_log "by-version ended with error" ;;
      "By Phase"*)      imagectl_pipeline_by_phase     || imagectl_log "by-phase ended with error" ;;
      "Change Project"*)
        imagectl_select_project_interactive >/dev/null
        ;;
      "Back"*) break ;;
    esac
  done
}

imagectl_menu_resume() {
  imagectl_pipeline_resume
}

# ── Dispatch (CLI-compatible) ─────────────────────────────────────────────────

imagectl_pipeline_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh pipeline <manual|auto-by-os|auto-by-os-version|status|logs> [args]

compatibility aliases:
  scripts/control.sh script <manual|auto|auto-by-os|auto-by-os-version|status|logs> [args]
  scripts/control.sh auto --os <name> --version <x.yz>
EOF
}

imagectl_pipeline_dispatch() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    manual)             imagectl_manual "$@" ;;
    auto-by-os)         imagectl_auto_by_os "$@" ;;
    auto-by-os-version) imagectl_auto_by_os_version "$@" ;;
    auto)               imagectl_auto_by_os_version "$@" ;;
    status)             imagectl_pipeline_status ;;
    logs)               imagectl_pipeline_logs ;;
    ""|-h|--help|help)  imagectl_pipeline_usage ;;
    *)                  imagectl_die "unknown pipeline subcommand: $sub" ;;
  esac
}

imagectl_script_usage() {
  cat <<'EOF'
usage:
  scripts/control.sh script <manual|auto|auto-by-os|auto-by-os-version|status|logs> [args]

note: 'script' is a compatibility alias for 'pipeline'.
EOF
}

imagectl_script_dispatch() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    manual|auto|auto-by-os|auto-by-os-version|status|logs)
      imagectl_pipeline_dispatch "$sub" "$@"
      ;;
    ""|-h|--help|help) imagectl_script_usage ;;
    *) imagectl_die "unknown script subcommand: $sub" ;;
  esac
}
