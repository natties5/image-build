#!/usr/bin/env bash
set -Eeuo pipefail

imagectl_normalize_os() {
  local os_raw="${1:-}"
  local os="${os_raw,,}"
  case "$os" in
    ubuntu|debian|centos|almalinux|rocky)
      printf '%s' "$os"
      ;;
    *)
      printf ''
      ;;
  esac
}

imagectl_os_is_implemented() {
  local os="${1:-}"
  [[ "$os" == "ubuntu" ]]
}

imagectl_list_supported_oses() {
  printf '%s\n' ubuntu debian centos almalinux rocky
}

imagectl_require_supported_os() {
  local os
  os="$(imagectl_normalize_os "${1:-}")"
  [[ -n "$os" ]] || imagectl_die "unsupported os: ${1:-<empty>} (supported: ubuntu,debian,centos,almalinux,rocky)"
  printf '%s' "$os"
}

imagectl_version_list_for_os() {
  local os="$1"
  local summary_file="$IMAGECTL_REPO_ROOT/manifests/ubuntu/ubuntu-auto-discover-summary.tsv"
  if [[ "$os" != "ubuntu" ]]; then
    return 0
  fi
  if [[ -f "$summary_file" ]]; then
    awk -F '\t' 'NR>1 && $1 != "" && !seen[$1]++ {print $1}' "$summary_file"
  fi
}

imagectl_phase_command_for_ubuntu() {
  local phase="$1"
  local version="$2"
  case "$phase" in
    preflight) printf '%s' "bash bin/imagectl.sh preflight" ;;
    download) printf '%s' "bash bin/imagectl.sh download" ;;
    import) printf '%s' "bash bin/imagectl.sh import $(printf '%q' "$version")" ;;
    create) printf '%s' "bash bin/imagectl.sh create $(printf '%q' "$version")" ;;
    configure) printf '%s' "bash bin/imagectl.sh configure $(printf '%q' "$version")" ;;
    clean) printf '%s' "bash bin/imagectl.sh clean $(printf '%q' "$version")" ;;
    publish) printf '%s' "bash bin/imagectl.sh publish $(printf '%q' "$version")" ;;
    status) printf '%s' "git -C . status --short --branch" ;;
    logs) printf '%s' "ls -1 logs | tail -n 20" ;;
    *)
      return 1
      ;;
  esac
}

imagectl_phase_command() {
  local os="$1"
  local phase="$2"
  local version="${3:-}"

  if [[ "$os" != "ubuntu" ]]; then
    return 1
  fi
  imagectl_phase_command_for_ubuntu "$phase" "$version"
}
