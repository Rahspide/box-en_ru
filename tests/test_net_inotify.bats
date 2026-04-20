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
