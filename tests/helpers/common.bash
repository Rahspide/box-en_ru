#!/usr/bin/env bash
# Общие утилиты для тестовой среды box-en_ru

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/box/scripts"

# Создаёт минимальную mock-среду в указанной директории (по умолчанию BATS_TEST_TMPDIR)
setup_mock_env() {
  local d="${1:-${BATS_TEST_TMPDIR}}"
  mkdir -p "${d}/run/state"
  mkdir -p "${d}/run/locks"
  mkdir -p "${d}/bin"
  touch "${d}/ap.list.cfg"
  touch "${d}/package.list.cfg"
  touch "${d}/gid.list.cfg"
  touch "${d}/packages.list"
  touch "${d}/run/runs.log"
}

# Создаёт минимальный mock settings.ini в указанной директории
# Аргумент: директория (по умолчанию BATS_TEST_TMPDIR)
create_mock_settings() {
  local box_dir="${1:-${BATS_TEST_TMPDIR}}"
  local mock_settings="${box_dir}/settings.ini"

  # Создаём пустые файлы конфигов ядер, чтобы awk не читал stdin
  touch "${box_dir}/mihomo_config.yaml"
  touch "${box_dir}/sing_config.json"

  cat > "${mock_settings}" << EOF
box_dir="${box_dir}"
box_run="${box_dir}/run"
box_run_state="${box_dir}/run/state"
box_run_locks="${box_dir}/run/locks"
box_log="${box_dir}/run/runs.log"
box_pid="${box_dir}/run/box.pid"
bin_dir="${box_dir}/bin"
uid_list="${box_dir}/run/state/appuid.list"
system_packages_file="${box_dir}/packages.list"
write_listap="${box_dir}/ap.list.cfg"
pkg_config="${box_dir}/package.list.cfg"
gid_config="${box_dir}/gid.list.cfg"
mihomo_config="${box_dir}/mihomo_config.yaml"
sing_config="${box_dir}/sing_config.json"
settings="${box_dir}/settings.ini"
bin_name="mihomo"
bin_list=("mihomo" "sing-box" "xray" "v2fly" "hysteria")
bin_path="${box_dir}/bin/mihomo"
bin_log="${box_dir}/run/mihomo.log"
proxy_mode="core"
packages_list=()
gid_list=()
prefixed_list=()
unprefixed_list_converted=()
ap_list=()
ignore_ap_list=()
network_mode="tun"
tproxy_port="9898"
redir_port="9797"
ipv6="true"
current_time="00:00"
box_user_group="root:net_admin"
getprop() { echo "10"; }
log() { echo "[\$1]: \$2"; }
EOF
}

# Создаёт патч-копию скрипта, заменяя путь к settings.ini на mock
# Аргументы: исходный скрипт, целевой скрипт, директория с mock (по умолчанию BATS_FILE_TMPDIR)
patch_script_settings() {
  local src="$1"
  local dst="$2"
  local mock_dir="${3:-${BATS_FILE_TMPDIR}}"
  local mock_settings="${mock_dir}/settings.ini"

  # tr -d '\r' убирает Windows-окончания строк (CRLF) если они есть
  sed \
    -e "s|source /data/adb/box/settings.ini|source \"${mock_settings}\"|g" \
    -e "s|\. /data/adb/box/settings.ini|\. \"${mock_settings}\"|g" \
    "$src" | tr -d '\r' > "$dst"
  chmod +x "$dst"
}
