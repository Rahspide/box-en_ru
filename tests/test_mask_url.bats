#!/usr/bin/env bats
# Тесты функции mask_url() из box.tool

load "helpers/common"

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_file() {
  # Используем BATS_FILE_TMPDIR — доступен в setup_file
  setup_mock_env "${BATS_FILE_TMPDIR}"
  create_mock_settings "${BATS_FILE_TMPDIR}"
  patch_script_settings \
    "${REPO_ROOT}/box/scripts/box.tool" \
    "${BATS_FILE_TMPDIR}/box.tool" \
    "${BATS_FILE_TMPDIR}"
}

setup() {
  set -- ""
  source "${BATS_FILE_TMPDIR}/box.tool" 2>/dev/null || true
}

# ─── mask_url ─────────────────────────────────────────────────────────────────

@test "mask_url: маскирует HTTPS URL с путём" {
  run mask_url "https://github.com/owner/repo/releases/download/v1.0/file.zip"
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/***" ]
}

@test "mask_url: маскирует HTTP URL" {
  run mask_url "http://example.com/path/to/resource"
  [ "$status" -eq 0 ]
  [ "$output" = "http://example.com/***" ]
}

@test "mask_url: маскирует URL без пути" {
  run mask_url "https://example.com"
  [ "$status" -eq 0 ]
  [ "$output" = "https://example.com/***" ]
}

@test "mask_url: маскирует URL с корневым слешем" {
  run mask_url "https://example.com/"
  [ "$status" -eq 0 ]
  [ "$output" = "https://example.com/***" ]
}

@test "mask_url: маскирует raw.githubusercontent.com" {
  run mask_url "https://raw.githubusercontent.com/user/repo/main/file.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "https://raw.githubusercontent.com/***" ]
}

@test "mask_url: маскирует URL с токеном авторизации в query string" {
  run mask_url "https://api.github.com/repos/owner/repo?token=secret123"
  [ "$status" -eq 0 ]
  [ "$output" = "https://api.github.com/***" ]
}

@test "mask_url: обрабатывает URL без схемы" {
  run mask_url "example.com/path/file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/***" ]]
}

@test "mask_url: маскирует URL ghproxy-зеркала" {
  run mask_url "https://ghfast.top/https://github.com/owner/repo/file"
  [ "$status" -eq 0 ]
  [ "$output" = "https://ghfast.top/***" ]
}
