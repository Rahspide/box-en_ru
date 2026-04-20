#!/usr/bin/env bats
# Тесты вспомогательных функций из net.inotify:
#   - with_lock_or_skip() — mutex-блокировка через mkdir
#   - chain_exists()       — проверка существования iptables-цепочки
#   - ensure_chain_and_flush() — создание/очистка цепочки
#   - ensure_rule_append() — добавление правила без дублирования

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # Устанавливаем переменные, которые использует with_lock_or_skip
  logs="${BATS_TEST_TMPDIR}/run"
  mkdir -p "${logs}/locks"
  lock_dir="${logs}/locks/net_inotify.lock"

  # Определяем функции напрямую из исходника net.inotify
  # чтобы избежать side effects при sourcing Android-скрипта

  with_lock_or_skip() {
    mkdir -p "${logs}" "${logs}/locks" >/dev/null 2>&1 || true
    if ! mkdir "${lock_dir}" >/dev/null 2>&1; then
      return 1
    fi
    trap "rmdir \"${lock_dir}\" >/dev/null 2>&1 || true" EXIT INT TERM
    return 0
  }

  chain_exists() {
    local ipt_cmd="$1"
    local table_name="$2"
    local chain_name="$3"
    ${ipt_cmd} -t "${table_name}" -L "${chain_name}" >/dev/null 2>&1
  }

  ensure_chain_and_flush() {
    local ipt_cmd="$1"
    local table_name="$2"
    local chain_name="$3"
    ${ipt_cmd} -t "${table_name}" -N "${chain_name}" >/dev/null 2>&1 || true
    ${ipt_cmd} -t "${table_name}" -F "${chain_name}" >/dev/null 2>&1 || true
  }

  ensure_rule_append() {
    local ipt_cmd="$1"
    local table_name="$2"
    local chain_name="$3"
    shift 3
    if ${ipt_cmd} -t "${table_name}" -C "${chain_name}" "$@" >/dev/null 2>&1; then
      return 0
    fi
    ${ipt_cmd} -t "${table_name}" -A "${chain_name}" "$@" >/dev/null 2>&1
  }
}

teardown() {
  rmdir "${lock_dir}" 2>/dev/null || true
}

# ─── with_lock_or_skip ────────────────────────────────────────────────────────

@test "with_lock_or_skip: первый вызов — блокировка создаётся (возвращает 0)" {
  run with_lock_or_skip
  [ "$status" -eq 0 ]
}

@test "with_lock_or_skip: создаёт директорию-блокировку" {
  (
    with_lock_or_skip
    [ -d "${lock_dir}" ]
  )
  [ "$?" -eq 0 ]
}

@test "with_lock_or_skip: повторный вызов при занятой блокировке — возвращает 1" {
  mkdir -p "${lock_dir}"
  run with_lock_or_skip
  [ "$status" -eq 1 ]
}

@test "with_lock_or_skip: блокировка снимается при выходе из подоболочки (trap EXIT)" {
  (
    with_lock_or_skip
    [ -d "${lock_dir}" ]
  )
  # После выхода из подоболочки блокировка должна быть снята
  [ ! -d "${lock_dir}" ]
}

# ─── chain_exists ─────────────────────────────────────────────────────────────

@test "chain_exists: возвращает 0, если mock iptables находит цепочку" {
  mock_iptables() { return 0; }
  run chain_exists "mock_iptables" "mangle" "BOX_EXTERNAL"
  [ "$status" -eq 0 ]
}

@test "chain_exists: возвращает 1, если mock iptables не находит цепочку" {
  mock_iptables() { return 1; }
  run chain_exists "mock_iptables" "mangle" "NONEXISTENT"
  [ "$status" -eq 1 ]
}

# ─── ensure_chain_and_flush ───────────────────────────────────────────────────

@test "ensure_chain_and_flush: вызывает -N и -F для указанной цепочки" {
  local calls_file="${BATS_TEST_TMPDIR}/calls.txt"
  : > "${calls_file}"
  mock_ipt() { echo "$*" >> "${calls_file}"; return 0; }

  ensure_chain_and_flush "mock_ipt" "mangle" "TEST_CHAIN"
  grep -q "\-N TEST_CHAIN" "${calls_file}"
  grep -q "\-F TEST_CHAIN" "${calls_file}"
}

@test "ensure_chain_and_flush: не падает, если цепочка уже существует (-N ошибка игнорируется)" {
  mock_ipt() {
    if [[ "$*" == *"-N"* ]]; then return 1; fi
    return 0
  }
  run ensure_chain_and_flush "mock_ipt" "nat" "EXISTING_CHAIN"
  [ "$status" -eq 0 ]
}

# ─── ensure_rule_append ───────────────────────────────────────────────────────

@test "ensure_rule_append: добавляет правило, если оно ещё не существует" {
  local calls_file="${BATS_TEST_TMPDIR}/append_calls.txt"
  : > "${calls_file}"
  mock_ipt() {
    echo "$*" >> "${calls_file}"
    if [[ "$*" == *"-C"* ]]; then return 1; fi
    return 0
  }
  ensure_rule_append "mock_ipt" "mangle" "LOCAL_IP_V4" -d "192.168.1.1/32" -j ACCEPT
  grep -q "\-A LOCAL_IP_V4" "${calls_file}"
}

@test "ensure_rule_append: не дублирует правило, если оно уже существует" {
  local calls_file="${BATS_TEST_TMPDIR}/nodup_calls.txt"
  : > "${calls_file}"
  mock_ipt() {
    echo "$*" >> "${calls_file}"
    if [[ "$*" == *"-C"* ]]; then return 0; fi
    return 0
  }
  ensure_rule_append "mock_ipt" "mangle" "LOCAL_IP_V4" -d "10.0.0.1/32" -j ACCEPT
  ! grep -q "\-A LOCAL_IP_V4" "${calls_file}"
}

# ─── rules_add: корректность логирования ─────────────────────────────────────

@test "rules_add: логирует предупреждение, если второе правило iptables не добавлено" {
  local log_out="${BATS_TEST_TMPDIR}/net.log"
  : > "${log_out}"

  # Sourcing net.inotify определяет rules_add; events="" блокирует side-effect
  getprop() { echo "12"; }
  events=""
  source "${REPO_ROOT}/box/scripts/net.inotify"

  # Переопределяем переменные после sourcing
  logs="${BATS_TEST_TMPDIR}/run"
  log_file="${log_out}"
  mkdir -p "${logs}"

  # Мок: ip -4 a возвращает один адрес; ip -6 a — ничего
  ip() {
    case "$1" in
      -4) echo "    inet 192.168.1.100/24 scope global wlan0" ;;
      *)  return 0 ;;
    esac
  }

  # Мок: записываем вызовы log_info / log_warn в файл
  log_info() { echo "info: $*" >> "${log_file}"; }
  log_warn() { echo "warn: $*" >> "${log_file}"; }

  # Мок: ensure_chain_and_flush — ничего не делает
  ensure_chain_and_flush() { return 0; }

  # Мок: правило для mangle добавляется успешно, для nat — нет
  ensure_rule_append() {
    local table="$2"
    [ "$table" = "mangle" ] && return 0 || return 1
  }

  # set +e нужен, чтобы возврат 1 из мока ensure_rule_append не прерывал
  # подпроцесс пайпа раньше, чем будет вызван log_warn (bats использует set -e)
  set +e
  rules_add
  set -e

  # После исправления (|| → &&): при частичном сбое вызывается log_warn, а не log_info
  grep -q "warn:" "${log_out}"
  ! grep -q "info:" "${log_out}"
}
