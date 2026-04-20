#!/usr/bin/env bats
# Тесты вспомогательных функций из box.iptables:
#   - is_box_custom_chain()  — определение кастомных цепочек
#   - chain_exists()         — проверка существования цепочки
#   - ensure_chain()         — создание/очистка цепочки
#   - ensure_jump()          — добавление jump-правила без дублирования
#   - del_jump_if_exists()   — удаление jump-правила если существует
#   - cleanup_chain()        — удаление цепочки вместе с содержимым
#   - ensure_rule_append()   — добавление правила к кастомной и обычной цепочке
#   - del_rule_if_exists()   — удаление правила если существует

load "helpers/common"

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_file() {
  setup_mock_env "${BATS_FILE_TMPDIR}"
  create_mock_settings "${BATS_FILE_TMPDIR}"
  patch_script_settings \
    "${REPO_ROOT}/box/scripts/box.iptables" \
    "${BATS_FILE_TMPDIR}/box.iptables" \
    "${BATS_FILE_TMPDIR}"
}

setup() {
  # Директория для mock-бинарников iptables
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # По умолчанию mock iptables просто успешен
  printf '#!/bin/bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/iptables"
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"

  # Загружаем box.iptables
  getprop() { echo "10"; }
  set -- ""
  source "${BATS_FILE_TMPDIR}/box.iptables" 2>/dev/null || true

  # Перенаправляем переменную iptables на наш mock-бинарник
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  ip6tables="${BATS_TEST_TMPDIR}/bin/iptables"
}

# ─── Вспомогательная функция: создать mock iptables с заданным кодом возврата
mock_ipt_exitcode() {
  local code="$1"
  printf '#!/bin/bash\nexit %d\n' "$code" > "${BATS_TEST_TMPDIR}/bin/iptables"
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
}

# ─── Вспомогательная функция: создать mock iptables, записывающий вызовы в файл
mock_ipt_track() {
  local calls_file="${BATS_TEST_TMPDIR}/ipt_calls.txt"
  : > "${calls_file}"
  # Скрипт: записать аргументы и завершиться с кодом $MOCK_IPT_EXIT (по умолчанию 0)
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << MOCK
#!/bin/bash
echo "\$*" >> "${calls_file}"
exit \${MOCK_IPT_EXIT:-0}
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  echo "$calls_file"
}

# ─── is_box_custom_chain ──────────────────────────────────────────────────────

@test "is_box_custom_chain: BOX_EXTERNAL — кастомная" {
  run is_box_custom_chain "BOX_EXTERNAL"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: BOX_TCP — кастомная" {
  run is_box_custom_chain "BOX_TCP"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: DIVERT — кастомная" {
  run is_box_custom_chain "DIVERT"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: LOCAL_IP_V4 — кастомная" {
  run is_box_custom_chain "LOCAL_IP_V4"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: LOCAL_IP_V6 — кастомная" {
  run is_box_custom_chain "LOCAL_IP_V6"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: NAT_DNS_HIJACK — кастомная" {
  run is_box_custom_chain "NAT_DNS_HIJACK"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: NAT_DNS_HIJACK6 — кастомная" {
  run is_box_custom_chain "NAT_DNS_HIJACK6"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: MIHOMO_DNS_EXTERNAL — кастомная" {
  run is_box_custom_chain "MIHOMO_DNS_EXTERNAL"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: MIHOMO_DNS_LOCAL — кастомная" {
  run is_box_custom_chain "MIHOMO_DNS_LOCAL"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: AP_WLAN0 — кастомная (по шаблону AP_*)" {
  run is_box_custom_chain "AP_WLAN0"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: AP_ETH0 — кастомная (по шаблону AP_*)" {
  run is_box_custom_chain "AP_ETH0"
  [ "$status" -eq 0 ]
}

@test "is_box_custom_chain: OUTPUT — встроенная (не кастомная)" {
  run is_box_custom_chain "OUTPUT"
  [ "$status" -eq 1 ]
}

@test "is_box_custom_chain: INPUT — встроенная (не кастомная)" {
  run is_box_custom_chain "INPUT"
  [ "$status" -eq 1 ]
}

@test "is_box_custom_chain: PREROUTING — встроенная (не кастомная)" {
  run is_box_custom_chain "PREROUTING"
  [ "$status" -eq 1 ]
}

@test "is_box_custom_chain: FORWARD — встроенная (не кастомная)" {
  run is_box_custom_chain "FORWARD"
  [ "$status" -eq 1 ]
}

@test "is_box_custom_chain: POSTROUTING — встроенная (не кастомная)" {
  run is_box_custom_chain "POSTROUTING"
  [ "$status" -eq 1 ]
}

@test "is_box_custom_chain: пустая строка — не кастомная" {
  run is_box_custom_chain ""
  [ "$status" -eq 1 ]
}

# ─── chain_exists ─────────────────────────────────────────────────────────────

@test "chain_exists: возвращает 0, если iptables -L успешен" {
  mock_ipt_exitcode 0
  chain_exists "mangle" "BOX_EXTERNAL"
  [ "$?" -eq 0 ]
}

@test "chain_exists: возвращает 1, если iptables -L возвращает ошибку" {
  mock_ipt_exitcode 1
  ! chain_exists "mangle" "NONEXISTENT_CHAIN"
}

@test "chain_exists: передаёт правильную таблицу и имя цепочки" {
  local calls_file
  calls_file=$(mock_ipt_track)
  chain_exists "nat" "MY_CHAIN" || true
  grep -q "\-t nat -L MY_CHAIN" "${calls_file}"
}

# ─── ensure_chain ─────────────────────────────────────────────────────────────

@test "ensure_chain: вызывает -N и -F для указанной цепочки" {
  local calls_file
  calls_file=$(mock_ipt_track)
  ensure_chain "mangle" "TEST_CHAIN"
  grep -q "\-N TEST_CHAIN" "${calls_file}"
  grep -q "\-F TEST_CHAIN" "${calls_file}"
}

@test "ensure_chain: не падает, если цепочка уже существует (-N возвращает 1)" {
  # -N провалится (цепочка уже есть), но ensure_chain должна продолжить
  export MOCK_IPT_EXIT=1
  local calls_file
  calls_file=$(mock_ipt_track)
  # || true потому что ensure_chain использует || true внутри
  ensure_chain "nat" "EXISTING_CHAIN"
  # Проверяем что -F всё равно вызывается (после || true для -N)
  grep -q "\-F EXISTING_CHAIN" "${calls_file}"
}

# ─── ensure_jump ──────────────────────────────────────────────────────────────

@test "ensure_jump: вставляет jump если его нет (-C возвращает 1)" {
  # -C должна вернуть 1 (правила нет), тогда -I вставит его
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << 'MOCK'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR_CALLS}"
if [[ "$*" == *"-C"* ]]; then exit 1; fi
exit 0
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  export BATS_TEST_TMPDIR_CALLS="${BATS_TEST_TMPDIR}/calls.txt"
  : > "${BATS_TEST_TMPDIR_CALLS}"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  ensure_jump "mangle" "PREROUTING" "BOX_EXTERNAL"
  grep -q "\-I PREROUTING" "${BATS_TEST_TMPDIR_CALLS}"
}

@test "ensure_jump: не вставляет jump если он уже есть (-C возвращает 0)" {
  # -C возвращает 0 (правило есть), -I не должен вызываться
  local calls_file
  calls_file=$(mock_ipt_track)  # exitcode 0 для всех вызовов
  ensure_jump "mangle" "PREROUTING" "BOX_EXTERNAL"
  ! grep -q "\-I PREROUTING" "${calls_file}"
}

# ─── del_jump_if_exists ───────────────────────────────────────────────────────

@test "del_jump_if_exists: удаляет jump если он есть (-C возвращает 0)" {
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << 'MOCK'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR_CALLS}"
exit 0
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  export BATS_TEST_TMPDIR_CALLS="${BATS_TEST_TMPDIR}/del_calls.txt"
  : > "${BATS_TEST_TMPDIR_CALLS}"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  del_jump_if_exists "mangle" "PREROUTING" "BOX_EXTERNAL"
  grep -q "\-D PREROUTING" "${BATS_TEST_TMPDIR_CALLS}"
}

@test "del_jump_if_exists: не удаляет jump если его нет (-C возвращает 1)" {
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << 'MOCK'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR_CALLS}"
if [[ "$*" == *"-C"* ]]; then exit 1; fi
exit 0
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  export BATS_TEST_TMPDIR_CALLS="${BATS_TEST_TMPDIR}/nodel_calls.txt"
  : > "${BATS_TEST_TMPDIR_CALLS}"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  del_jump_if_exists "mangle" "PREROUTING" "BOX_EXTERNAL"
  ! grep -q "\-D PREROUTING" "${BATS_TEST_TMPDIR_CALLS}"
}

# ─── cleanup_chain ────────────────────────────────────────────────────────────

@test "cleanup_chain: вызывает -F и -X если цепочка существует" {
  local calls_file
  calls_file=$(mock_ipt_track)  # -L (chain_exists) и всё остальное — успех
  cleanup_chain "mangle" "BOX_EXTERNAL"
  grep -q "\-F BOX_EXTERNAL" "${calls_file}"
  grep -q "\-X BOX_EXTERNAL" "${calls_file}"
}

@test "cleanup_chain: ничего не делает если цепочки нет (-L возвращает 1)" {
  mock_ipt_exitcode 1
  local calls_file="${BATS_TEST_TMPDIR}/cleanup_calls.txt"
  : > "${calls_file}"
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << 'MOCK'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR_CALLS}"
exit 1
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  export BATS_TEST_TMPDIR_CALLS="${calls_file}"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  cleanup_chain "mangle" "NONEXISTENT"
  ! grep -q "\-F NONEXISTENT" "${calls_file}"
}

# ─── ensure_rule_append ───────────────────────────────────────────────────────

@test "ensure_rule_append: кастомная цепочка — всегда добавляет без проверки -C" {
  # Для кастомной цепочки не должно быть -C (они очищаются при старте)
  local calls_file
  calls_file=$(mock_ipt_track)
  ensure_rule_append "mangle" "BOX_EXTERNAL" -p tcp -j MARK --set-xmark "0x1000000"
  ! grep -q "\-C BOX_EXTERNAL" "${calls_file}"
  grep -q "\-A BOX_EXTERNAL" "${calls_file}"
}

@test "ensure_rule_append: обычная цепочка — сначала проверяет -C, добавляет если нет" {
  # OUTPUT — обычная цепочка; -C вернёт 1 (нет правила) → должен быть -A
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << 'MOCK'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR_CALLS}"
if [[ "$*" == *"-C"* ]]; then exit 1; fi
exit 0
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  export BATS_TEST_TMPDIR_CALLS="${BATS_TEST_TMPDIR}/rule_calls.txt"
  : > "${BATS_TEST_TMPDIR_CALLS}"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  ensure_rule_append "filter" "OUTPUT" -j BOX_EXTERNAL
  grep -q "\-C OUTPUT" "${BATS_TEST_TMPDIR_CALLS}"
  grep -q "\-A OUTPUT" "${BATS_TEST_TMPDIR_CALLS}"
}

@test "ensure_rule_append: обычная цепочка — не дублирует если правило есть (-C=0)" {
  local calls_file
  calls_file=$(mock_ipt_track)  # всё успешно, -C возвращает 0
  ensure_rule_append "filter" "OUTPUT" -j BOX_EXTERNAL
  ! grep -q "\-A OUTPUT" "${calls_file}"
}

# ─── del_rule_if_exists ───────────────────────────────────────────────────────

@test "del_rule_if_exists: удаляет правило если оно есть" {
  local calls_file
  calls_file=$(mock_ipt_track)  # все вызовы успешны
  del_rule_if_exists "mangle" "OUTPUT" -j BOX_EXTERNAL
  grep -q "\-D OUTPUT" "${calls_file}"
}

@test "del_rule_if_exists: ничего не делает если правила нет (-C=1)" {
  cat > "${BATS_TEST_TMPDIR}/bin/iptables" << 'MOCK'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR_CALLS}"
if [[ "$*" == *"-C"* ]]; then exit 1; fi
exit 0
MOCK
  chmod +x "${BATS_TEST_TMPDIR}/bin/iptables"
  export BATS_TEST_TMPDIR_CALLS="${BATS_TEST_TMPDIR}/delrule_calls.txt"
  : > "${BATS_TEST_TMPDIR_CALLS}"
  iptables="${BATS_TEST_TMPDIR}/bin/iptables"
  del_rule_if_exists "mangle" "OUTPUT" -j BOX_EXTERNAL
  ! grep -q "\-D OUTPUT" "${BATS_TEST_TMPDIR_CALLS}"
}
