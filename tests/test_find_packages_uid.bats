#!/usr/bin/env bats
# Тесты функции find_packages_uid() из box.service

load "helpers/common"

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_file() {
  setup_mock_env "${BATS_FILE_TMPDIR}"
  create_mock_settings "${BATS_FILE_TMPDIR}"
  patch_script_settings \
    "${REPO_ROOT}/box/scripts/box.service" \
    "${BATS_FILE_TMPDIR}/box.service" \
    "${BATS_FILE_TMPDIR}"
}

setup() {
  # Загружаем функции box.service.
  # set -- "NOARG" чтобы case "$1" упал в *) и просто выдал Usage (не exit)
  getprop() { echo "10"; }
  set -- "NOARG"
  source "${BATS_FILE_TMPDIR}/box.service" 2>/dev/null || true
  set -- ""

  # Пути из mock settings.ini
  uid_list="${BATS_TEST_TMPDIR}/appuid.list"
  system_packages_file="${BATS_TEST_TMPDIR}/packages.list"
  pkg_config="${BATS_TEST_TMPDIR}/package.list.cfg"
  gid_config="${BATS_TEST_TMPDIR}/gid.list.cfg"
  box_run_state="${BATS_TEST_TMPDIR}"
  proxy_mode="core"
  packages_list=()
  gid_list=()

  # Сбрасываем файлы перед каждым тестом
  : > "${uid_list}"
  : > "${system_packages_file}"
  : > "${pkg_config}"
  : > "${gid_config}"
}

# ─── Режим core ───────────────────────────────────────────────────────────────

@test "find_packages_uid: proxy_mode=core — uid_list пуст, возвращает 0" {
  proxy_mode="core"
  packages_list=()
  gid_list=()

  run find_packages_uid
  [ "$status" -eq 0 ]
  [ ! -s "${uid_list}" ]
}

# ─── Поиск UID по имени пакета ────────────────────────────────────────────────

@test "find_packages_uid: корректный пакет → правильный UID записывается" {
  proxy_mode="whitelist"
  echo "com.example.app 10123" > "${system_packages_file}"
  packages_list=("0:com.example.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  grep -qx "10123" "${uid_list}"
}

@test "find_packages_uid: несколько пакетов → все UID записываются" {
  proxy_mode="whitelist"
  cat > "${system_packages_file}" << 'EOF'
com.first.app 10100
com.second.app 10200
com.third.app 10300
EOF
  packages_list=("0:com.first.app" "0:com.second.app" "0:com.third.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  grep -qx "10100" "${uid_list}"
  grep -qx "10200" "${uid_list}"
  grep -qx "10300" "${uid_list}"
}

@test "find_packages_uid: пакет не найден в packages.list — пропускается без ошибки" {
  proxy_mode="whitelist"
  : > "${system_packages_file}"
  packages_list=("0:com.missing.app")
  gid_list=()

  run find_packages_uid
  [ "$status" -eq 0 ]
  [ ! -s "${uid_list}" ]
}

@test "find_packages_uid: суффикс пользователя 1 → multiuser UID = base + 100000" {
  proxy_mode="whitelist"
  echo "com.example.app 10123" > "${system_packages_file}"
  packages_list=("1:com.example.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  # multiuser UID = 10123 + 1*100000 = 110123
  grep -qx "110123" "${uid_list}"
}

@test "find_packages_uid: суффикс пользователя 0 → обычный UID (без сдвига)" {
  proxy_mode="whitelist"
  echo "com.example.app 10050" > "${system_packages_file}"
  packages_list=("0:com.example.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  grep -qx "10050" "${uid_list}"
}

@test "find_packages_uid: некорректный префикс (буква) → откат к 0" {
  proxy_mode="whitelist"
  echo "com.example.app 10999" > "${system_packages_file}"
  # Некорректный префикс 'x'
  packages_list=("x:com.example.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  # Должен откатиться к prefix=0, UID = 10999
  grep -qx "10999" "${uid_list}"
}

@test "find_packages_uid: запись без разделителя ':' — корректно обрабатывается" {
  proxy_mode="whitelist"
  echo "com.example.app 10777" > "${system_packages_file}"
  packages_list=("com.example.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  grep -qx "10777" "${uid_list}"
}

# ─── GID ──────────────────────────────────────────────────────────────────────

@test "find_packages_uid: GID записываются в uid_list" {
  proxy_mode="whitelist"
  packages_list=()
  gid_list=("3001" "3002")

  find_packages_uid 2>/dev/null
  grep -qx "3001" "${uid_list}"
  grep -qx "3002" "${uid_list}"
}

@test "find_packages_uid: GID и UID объединяются в одном файле" {
  proxy_mode="whitelist"
  echo "com.example.app 10050" > "${system_packages_file}"
  packages_list=("0:com.example.app")
  gid_list=("3001")

  find_packages_uid 2>/dev/null
  grep -qx "10050" "${uid_list}"
  grep -qx "3001" "${uid_list}"
}

# ─── Дедупликация и сортировка ────────────────────────────────────────────────

@test "find_packages_uid: дублирующиеся UID удаляются" {
  proxy_mode="whitelist"
  cat > "${system_packages_file}" << 'EOF'
com.first.app 10100
com.second.app 10100
EOF
  packages_list=("0:com.first.app" "0:com.second.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  count=$(grep -cx "10100" "${uid_list}" || true)
  [ "$count" -eq 1 ]
}

@test "find_packages_uid: UID отсортированы в числовом порядке" {
  proxy_mode="whitelist"
  cat > "${system_packages_file}" << 'EOF'
com.z.app 10300
com.a.app 10100
com.m.app 10200
EOF
  packages_list=("0:com.z.app" "0:com.a.app" "0:com.m.app")
  gid_list=()

  find_packages_uid 2>/dev/null
  result=$(cat "${uid_list}")
  expected="10100
10200
10300"
  [ "$result" = "$expected" ]
}
