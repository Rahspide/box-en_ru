#!/usr/bin/env bats
# Тесты логики WiFi/SSID из ctr.utils

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # Настройка переменных по умолчанию, которые использует ctr.utils
  wifi_ssids_list=("HomeWiFi" "OfficeNet" "TestSSID")
  wifi_bssids_list=("aa:bb:cc:dd:ee:ff" "11:22:33:44:55:66")
  use_module_on_wifi="true"
  use_module_on_wifi_disconnect="true"
  use_ssid_matching="false"
  use_wifi_list_mode="blacklist"

  # Загружаем ctr.utils — только определения функций, без side effects
  source "${REPO_ROOT}/box/scripts/ctr.utils"
}

# ─── is_ssid_in_list ──────────────────────────────────────────────────────────

@test "is_ssid_in_list: первый элемент списка совпадает" {
  run is_ssid_in_list "HomeWiFi"
  [ "$status" -eq 0 ]
}

@test "is_ssid_in_list: средний элемент списка совпадает" {
  run is_ssid_in_list "OfficeNet"
  [ "$status" -eq 0 ]
}

@test "is_ssid_in_list: последний элемент списка совпадает" {
  run is_ssid_in_list "TestSSID"
  [ "$status" -eq 0 ]
}

@test "is_ssid_in_list: SSID не в списке — возвращает 1" {
  run is_ssid_in_list "UnknownWiFi"
  [ "$status" -eq 1 ]
}

@test "is_ssid_in_list: пустая строка не совпадает с элементами списка" {
  run is_ssid_in_list ""
  [ "$status" -eq 1 ]
}

@test "is_ssid_in_list: частичное совпадение не засчитывается" {
  run is_ssid_in_list "Home"
  [ "$status" -eq 1 ]
}

@test "is_ssid_in_list: проверка регистрозависимости" {
  run is_ssid_in_list "homewifi"
  [ "$status" -eq 1 ]
}

@test "is_ssid_in_list: пустой список — всегда возвращает 1" {
  wifi_ssids_list=()
  run is_ssid_in_list "HomeWiFi"
  [ "$status" -eq 1 ]
}

@test "is_ssid_in_list: единственный элемент в списке совпадает" {
  wifi_ssids_list=("OnlyNet")
  run is_ssid_in_list "OnlyNet"
  [ "$status" -eq 0 ]
}

@test "is_ssid_in_list: SSID с пробелами совпадает точно" {
  wifi_ssids_list=("My Home WiFi")
  run is_ssid_in_list "My Home WiFi"
  [ "$status" -eq 0 ]
}

# ─── is_bssid_in_list ─────────────────────────────────────────────────────────

@test "is_bssid_in_list: первый элемент списка совпадает" {
  run is_bssid_in_list "aa:bb:cc:dd:ee:ff"
  [ "$status" -eq 0 ]
}

@test "is_bssid_in_list: второй элемент списка совпадает" {
  run is_bssid_in_list "11:22:33:44:55:66"
  [ "$status" -eq 0 ]
}

@test "is_bssid_in_list: BSSID не в списке — возвращает 1" {
  run is_bssid_in_list "ff:ff:ff:ff:ff:ff"
  [ "$status" -eq 1 ]
}

@test "is_bssid_in_list: пустой список — возвращает 1" {
  wifi_bssids_list=()
  run is_bssid_in_list "aa:bb:cc:dd:ee:ff"
  [ "$status" -eq 1 ]
}

@test "is_bssid_in_list: единственный элемент совпадает" {
  wifi_bssids_list=("de:ad:be:ef:00:01")
  run is_bssid_in_list "de:ad:be:ef:00:01"
  [ "$status" -eq 0 ]
}

@test "is_bssid_in_list: регистр игнорируется (верхний регистр)" {
  wifi_bssids_list=("AA:BB:CC:DD:EE:FF")
  run is_bssid_in_list "AA:BB:CC:DD:EE:FF"
  [ "$status" -eq 0 ]
}

# ─── should_enable_service ────────────────────────────────────────────────────

@test "should_enable_service: не WiFi + disconnect=true → включить сервис" {
  use_module_on_wifi_disconnect="true"
  run should_enable_service "not_wifi" "" ""
  [ "$status" -eq 0 ]
}

@test "should_enable_service: не WiFi + disconnect=false → не включать" {
  use_module_on_wifi_disconnect="false"
  run should_enable_service "not_wifi" "" ""
  [ "$status" -eq 1 ]
}

@test "should_enable_service: WiFi + use_module_on_wifi=false → не включать" {
  use_module_on_wifi="false"
  run should_enable_service "wifi" "HomeWiFi" "aa:bb:cc:dd:ee:ff"
  [ "$status" -eq 1 ]
}

@test "should_enable_service: WiFi + ssid_matching=false → всегда включать" {
  use_module_on_wifi="true"
  use_ssid_matching="false"
  run should_enable_service "wifi" "AnySSID" "unknown"
  [ "$status" -eq 0 ]
}

@test "should_enable_service: WiFi + whitelist + SSID в списке → включить" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="whitelist"
  wifi_ssids_list=("HomeWiFi")
  wifi_bssids_list=()
  run should_enable_service "wifi" "HomeWiFi" "unknown"
  [ "$status" -eq 0 ]
}

@test "should_enable_service: WiFi + whitelist + SSID НЕ в списке → не включать" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="whitelist"
  wifi_ssids_list=("HomeWiFi")
  wifi_bssids_list=()
  run should_enable_service "wifi" "GuestWiFi" "unknown"
  [ "$status" -eq 1 ]
}

@test "should_enable_service: WiFi + blacklist + SSID в списке → не включать" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="blacklist"
  wifi_ssids_list=("BlockedNet")
  wifi_bssids_list=()
  run should_enable_service "wifi" "BlockedNet" "unknown"
  [ "$status" -eq 1 ]
}

@test "should_enable_service: WiFi + blacklist + SSID НЕ в списке → включить" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="blacklist"
  wifi_ssids_list=("BlockedNet")
  wifi_bssids_list=()
  run should_enable_service "wifi" "OtherNet" "unknown"
  [ "$status" -eq 0 ]
}

@test "should_enable_service: WiFi + whitelist + BSSID в списке → включить" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="whitelist"
  wifi_ssids_list=()
  wifi_bssids_list=("aa:bb:cc:dd:ee:ff")
  run should_enable_service "wifi" "unknown" "aa:bb:cc:dd:ee:ff"
  [ "$status" -eq 0 ]
}

@test "should_enable_service: WiFi + whitelist + BSSID НЕ в списке → не включать" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="whitelist"
  wifi_ssids_list=()
  wifi_bssids_list=("aa:bb:cc:dd:ee:ff")
  run should_enable_service "wifi" "unknown" "ff:ff:ff:ff:ff:ff"
  [ "$status" -eq 1 ]
}

@test "should_enable_service: WiFi + blacklist + BSSID в списке → не включать" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="blacklist"
  wifi_ssids_list=()
  wifi_bssids_list=("aa:bb:cc:dd:ee:ff")
  run should_enable_service "wifi" "unknown" "aa:bb:cc:dd:ee:ff"
  [ "$status" -eq 1 ]
}

@test "should_enable_service: WiFi + blacklist + BSSID НЕ в списке → включить" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="blacklist"
  wifi_ssids_list=()
  wifi_bssids_list=("aa:bb:cc:dd:ee:ff")
  run should_enable_service "wifi" "unknown" "11:22:33:44:55:66"
  [ "$status" -eq 0 ]
}

@test "should_enable_service: WiFi + ssid_matching=true + пустые списки + blacklist → включить" {
  use_module_on_wifi="true"
  use_ssid_matching="true"
  use_wifi_list_mode="blacklist"
  wifi_ssids_list=()
  wifi_bssids_list=()
  run should_enable_service "wifi" "AnyNet" "unknown"
  [ "$status" -eq 0 ]
}
