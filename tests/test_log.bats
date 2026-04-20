#!/usr/bin/env bats
# Тесты функции log() из settings.ini

load "helpers/common"

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_file() {
  # Создаём patched settings.ini в BATS_FILE_TMPDIR
  mkdir -p "${BATS_FILE_TMPDIR}/run/state" "${BATS_FILE_TMPDIR}/run/locks"
  touch "${BATS_FILE_TMPDIR}/ap.list.cfg" \
        "${BATS_FILE_TMPDIR}/package.list.cfg" \
        "${BATS_FILE_TMPDIR}/gid.list.cfg"
  sed -e "s|box_dir=\"/data/adb/box\"|box_dir=\"${BATS_FILE_TMPDIR}\"|" \
    "${REPO_ROOT}/box/settings.ini" > "${BATS_FILE_TMPDIR}/settings.ini"
}

setup() {
  LOG_FILE="${BATS_TEST_TMPDIR}/test.log"
  touch "${LOG_FILE}"
  source "${BATS_FILE_TMPDIR}/settings.ini"
  # Переопределяем box_log на per-test файл
  box_log="${LOG_FILE}"
  : > "${LOG_FILE}"
}

# ─── Формат вывода ────────────────────────────────────────────────────────────

@test "log Info: вывод содержит метку [Info]" {
  run log Info "тестовое сообщение"
  [[ "$output" == *"[Info]: тестовое сообщение"* ]]
}

@test "log Error: вывод содержит метку [Error]" {
  run log Error "ошибка подключения"
  [[ "$output" == *"[Error]: ошибка подключения"* ]]
}

@test "log Warning: вывод содержит метку [Warning]" {
  run log Warning "предупреждение о версии"
  [[ "$output" == *"[Warning]: предупреждение о версии"* ]]
}

@test "log Debug: вывод содержит метку [Debug]" {
  run log Debug "отладочная информация"
  [[ "$output" == *"[Debug]: отладочная информация"* ]]
}

@test "log: вывод содержит время в формате HH:MM" {
  run log Info "проверка времени"
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2} ]]
}

@test "log: вывод имеет правильный формат HH:MM [Level]: message" {
  run log Info "проверка формата"
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2}\ \[Info\]:\ проверка\ формата$ ]]
}

@test "log: пустое сообщение не вызывает ошибку" {
  run log Info ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Info]: "* ]]
}

@test "log: сообщение с пробелами передаётся полностью" {
  run log Warning "это сообщение с пробелами и несколькими словами"
  [[ "$output" == *"это сообщение с пробелами и несколькими словами"* ]]
}

# ─── Запись в файл (non-TTY контекст) ────────────────────────────────────────

@test "log: в non-TTY режиме пишет в файл box_log" {
  # run создаёт non-TTY контекст
  run log Info "запись в файл"
  # Проверяем, что файл создан и содержит сообщение
  [ -f "${LOG_FILE}" ]
  grep -q "\[Info\]: запись в файл" "${LOG_FILE}"
}

@test "log: несколько вызовов дописывают строки в файл" {
  log Info "первое" 2>/dev/null
  log Error "второе" 2>/dev/null
  log Warning "третье" 2>/dev/null
  line_count=$(wc -l < "${LOG_FILE}")
  [ "$line_count" -eq 3 ]
}

@test "log: файл содержит все уровни при последовательных вызовах" {
  log Info "info msg" 2>/dev/null
  log Error "error msg" 2>/dev/null
  grep -q "\[Info\]: info msg" "${LOG_FILE}"
  grep -q "\[Error\]: error msg" "${LOG_FILE}"
}
