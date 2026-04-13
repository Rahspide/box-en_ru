
#!/system/bin/sh

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

if [ "$BOOTMODE" != true ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Пожалуйста, установите этот модуль в Magisk/KernelSU/APatch Manager"
  ui_print "! Установка из Recovery не поддерживается"
  abort "-----------------------------------------------------------"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Пожалуйста, обновите KernelSU и его менеджер"
  abort "-----------------------------------------------------------"
fi

service_dir="/data/adb/service.d"
if [ "$KSU" = "true" ]; then
  ui_print "- Обнаружена версия KernelSU: $KSU_VER ($KSU_VER_CODE)"
  [ "$KSU_VER_CODE" -lt 10683 ] && service_dir="/data/adb/ksu/service.d"
elif [ "$APATCH" = "true" ]; then
  APATCH_VER=$(cat "/data/adb/ap/version")
  ui_print "- Обнаружена версия APatch: $APATCH_VER"
else
  ui_print "- Обнаружена версия Magisk: $MAGISK_VER ($MAGISK_VER_CODE)"
fi

mkdir -p "${service_dir}"
if [ -d "/data/adb/modules/box_for_magisk" ]; then
  rm -rf "/data/adb/modules/box_for_magisk"
  ui_print "- Старый модуль удалён."
fi

ui_print "- Устанавливается Box для Magisk/KernelSU/APatch"
unzip -o "$ZIPFILE" -x 'META-INF/*' -x 'webroot/*' -d "$MODPATH" >&2
if [ -d "/data/adb/box" ]; then
  ui_print "- Резервное копирование существующих данных Box"
  temp_bak=$(mktemp -d -p "/data/adb/box" box.XXXXXXXXXX)
  temp_dir="${temp_bak}"
  mv /data/adb/box/* "${temp_dir}/"
  mv "$MODPATH/box/"* /data/adb/box/
  backup_box="true"
else
  mv "$MODPATH/box" /data/adb/
fi

ui_print "- Создать каталог"
mkdir -p /data/adb/box/ /data/adb/box/run/ /data/adb/box/bin/

ui_print "- Извлечь файлы uninstall.sh и box_service.sh"
unzip -j -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >&2
unzip -j -o "$ZIPFILE" 'box_service.sh' -d "${service_dir}" >&2

ui_print "- Настройка разрешений"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive /data/adb/box/ 0 3005 0755 0644
set_perm_recursive /data/adb/box/scripts/ 0 3005 0755 0700
set_perm ${service_dir}/box_service.sh 0 0 0755
set_perm $MODPATH/uninstall.sh 0 0 0755
chmod ugo+x ${service_dir}/box_service.sh $MODPATH/uninstall.sh /data/adb/box/scripts/*

KEY_LISTENER_PID=""
KEY_FIFO=""

start_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ] && kill -0 "$KEY_LISTENER_PID" 2>/dev/null; then
        return
    fi
    KEY_FIFO=$(mktemp -u -p /dev/tmp)
    mkfifo "$KEY_FIFO" || exit 1
    getevent -ql > "$KEY_FIFO" &
    KEY_LISTENER_PID=$!
}

stop_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ]; then
        kill "$KEY_LISTENER_PID" >/dev/null 2>&1
        KEY_LISTENER_PID=""
    fi
    if [ -n "$KEY_FIFO" ]; then
        rm -f "$KEY_FIFO"
        KEY_FIFO=""
    fi
}

volume_key_detection() {
    local timeout_seconds="${1:-0}"
    local detection_result_file=$(mktemp -u -p /dev/tmp)
    
    (
        while read -r line; do
            if echo "$line" | grep -Eiq "(KEY_)?VOLUME ?UP|KEYCODE_VOLUME_UP" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "0" > "$detection_result_file"
                exit 0
            elif echo "$line" | grep -Eiq "(KEY_)?VOLUME ?DOWN|KEYCODE_VOLUME_DOWN" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "1" > "$detection_result_file"
                exit 0
            fi
        done < "$KEY_FIFO"
    ) &
    local detection_pid=$!
    
    if [ "$timeout_seconds" -gt 0 ]; then
        (
            sleep "$timeout_seconds"
            if kill -0 "$detection_pid" 2>/dev/null; then
                kill "$detection_pid" 2>/dev/null
                echo "2" > "$detection_result_file"
            fi
        ) &
        local timeout_pid=$!
        
        wait "$detection_pid" 2>/dev/null
        kill "$timeout_pid" 2>/dev/null
        wait "$timeout_pid" 2>/dev/null
    else
        wait "$detection_pid" 2>/dev/null
    fi
    
    if [ -f "$detection_result_file" ]; then
        local result=$(cat "$detection_result_file")
        rm -f "$detection_result_file"
        return "$result"
    fi
    
    rm -f "$detection_result_file"
    return 2
}

handle_choice() {
    local question="$1"
    local choice_yes="${2:-Да}"
    local choice_no="${3:-Нет}"
    local timeout_seconds="${4:-10}"

    ui_print " "
    ui_print "-----------------------------------------------------------"
    ui_print "- ${question}"
    ui_print "- [ Громкость+ ]: ${choice_yes}"
    ui_print "- [ Громкость- ]: ${choice_no}"
    ui_print "- [ Если в течение ${timeout_seconds}с выбор не будет сделан, по умолчанию будет выбрано: ${choice_yes} ]"

    timeout 0.1 getevent -c 1 >/dev/null 2>&1

    start_key_listener
    volume_key_detection "$timeout_seconds"
    local result=$?
    stop_key_listener
    
    if [ "$result" -eq 0 ]; then
        ui_print "  => Вы выбрали: ${choice_yes}"
        return 0
    elif [ "$result" -eq 1 ]; then
        ui_print "  => Вы выбрали: ${choice_no}"
        return 1
    else
        ui_print "  => По истечении времени выбор не сделан, выбор по умолчанию: ${choice_yes}"
        return 0
    fi
}

ui_print " "
ui_print "==========================================================="
ui_print "==         Программа установки Box for Magisk/KernelSU/APatch         =="
ui_print "==========================================================="


if handle_choice "Требуется ли загрузить ядро или файлы данных?" "Да, выполнить загрузку" "Нет, пропустить всё"; then

    if handle_choice "Использовать ли зеркало для ускорения последующей загрузки?" "Использовать ускорение" "Скачать напрямую"; then
        ui_print "- Ускорение загрузки через зеркала включено."
        sed -i 's/use_ghproxy=.*/use_ghproxy="true"/' /data/adb/box/settings.ini
    else
        ui_print "- Ускорение загрузки через зеркала отключено."
        sed -i 's/use_ghproxy=.*/use_ghproxy="false"/' /data/adb/box/settings.ini
    fi

    COMPONENTS_TO_DOWNLOAD=""

    if handle_choice "Хотите настроить содержимое загрузки?" "Настроить" "Загрузить все компоненты одним нажатием"; then
        ui_print "- Перейти к пользовательской загрузке..."
        if handle_choice "Загрузить файлы данных GeoX (geoip/geosite)?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD geox"
        fi
        if handle_choice "Загрузить утилиты (yq, curl)?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD utils"
        fi
        
        ui_print " "
        ui_print "-----------------------------------------------------------"
        ui_print "- Пожалуйста, выберите ядро, которое вам нужно скачать:"
        if handle_choice "  - Загрузить ядро sing-box?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD sing-box"
        fi
        if handle_choice "  - Загрузить ядро mihomo?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD mihomo"
        fi
        if handle_choice "  - Загрузить ядро mihomo_smart (с группой политик Smart)? (Конфликтует с mihomo; пожалуйста, не загружайте их одновременно)" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD mihomo_smart"
        fi
        if handle_choice "  - Загрузить ядро xray?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD xray"
        fi
        if handle_choice "  - Загрузить ядро v2fly?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD v2fly"
        fi
        if handle_choice "  - Загрузить ядро hysteria?" "Загрузить" "Пропустить"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD hysteria"
        fi
    else
        ui_print "- Выбрана опция однокнопочной загрузки всех компонентов."
        COMPONENTS_TO_DOWNLOAD="geox utils sing-box mihomo xray v2fly hysteria"
    fi

    ui_print " "
    ui_print "==========================================================="
    ui_print "- Предварительный просмотр задач загрузки"
    ui_print "-----------------------------------------------------------"
    
    if [ -z "$COMPONENTS_TO_DOWNLOAD" ]; then
        ui_print "  - Нет задач загрузки."
    else
        COMPONENTS_TO_DOWNLOAD=$(echo "$COMPONENTS_TO_DOWNLOAD" | sed 's/^ *//')
        ui_print "  - Будет загружено: ${COMPONENTS_TO_DOWNLOAD}"
    fi
    ui_print "==========================================================="

    if [ -n "$COMPONENTS_TO_DOWNLOAD" ]; then
        if handle_choice "Начать выполнение вышеуказанных задач по загрузке?" "Начать загрузку" "Отменить все"; then
            ui_print "- Начинаем выполнение загрузки..."
            for component in $COMPONENTS_TO_DOWNLOAD; do
              case "$component" in
                geox)
                  ui_print "  -> Загрузка GeoX..."
                  /data/adb/box/scripts/box.tool upgeox_all
                  ;;
                utils)
                  ui_print "  -> Загрузка yq..."
                  /data/adb/box/scripts/box.tool upyq
                  ui_print "  -> Загрузка curl..."
                  /data/adb/box/scripts/box.tool upcurl
                  ;;
                *)
                  ui_print "  -> Загрузка ядра: $component..."
                  /data/adb/box/scripts/box.tool upkernel "$component"
                  ;;
              esac
            done
            ui_print "- Все задачи загрузки выполнены!"
        else
            ui_print "- Все задачи загрузки отменены."
        fi
    fi
else
    ui_print "- Все этапы загрузки пропущены."
fi


if [ "${backup_box}" = "true" ]; then
  ui_print " "
  ui_print "- Восстановление пользовательских настроек и данных..."

  if [ -f "${temp_dir}/settings.ini" ]; then
    if [ -f "/data/adb/box/settings.ini" ]; then
      if handle_choice "Обнаружен старый файл settings.ini. Как с ним поступить?" "Перезапись (заменить старую версию новой)" "Инкрементное объединение (запись старых значений только в существующие ключи в новой версии)"; then
        ui_print "  - Выбрано использование новой версии settings.ini (настройки из старой версии не применяются)"
      else
        mv /data/adb/box/settings.ini /data/adb/box/settings.ini.new
        grep -E '^[a-zA-Z0-9_]+=' "${temp_dir}/settings.ini" | while IFS='=' read -r key value; do
          [ -z "${key}" ] && continue
          echo "${key}" | grep -qE '^[a-zA-Z0-9_]+' || continue
          if grep -q -E "^${key}=" "/data/adb/box/settings.ini.new"; then
            escaped_value=$(printf '%s' "${value}" | sed -e 's/[&\\#]/\\&/g')
            sed -i "s#^${key}=.*#${key}=${escaped_value}#" "/data/adb/box/settings.ini.new"
          fi
        done
        mv /data/adb/box/settings.ini.new /data/adb/box/settings.ini
        ui_print "  - Пользовательские настройки инкрементно объединены с новой версией файла settings.ini"
      fi
    else
      cp -f "${temp_dir}/settings.ini" "/data/adb/box/settings.ini"
      ui_print "  - Файл settings.ini восстановлен"
    fi
  fi

  restore_config_dir() {
    config_dir="$1"
    if [ -d "${temp_dir}/${config_dir}" ]; then
        ui_print "  - Восстановление конфигурации каталога ${config_dir}"
        cp -af "${temp_dir}/${config_dir}/." "/data/adb/box/${config_dir}/"
    fi
  }
  for dir in mihomo xray v2fly sing-box hysteria; do
    restore_config_dir "$dir"
  done

  ui_print "  - Восстановить конфигурационный файл корневого каталога"
  for conf_file in ap.list.cfg package.list.cfg gid.list.cfg crontab.cfg; do
    if [ -f "${temp_dir}/${conf_file}" ]; then
      cp -f "${temp_dir}/${conf_file}" "/data/adb/box/${conf_file}"
    fi
  done

  restore_binary() {
    local bin_path_fragment="$1"
    local target_path="/data/adb/box/bin/${bin_path_fragment}"
    local backup_path="${temp_dir}/bin/${bin_path_fragment}"

    if [ ! -f "${target_path}" ] && [ -f "${backup_path}" ]; then
      ui_print "  - Восстановление бинарного файла: ${bin_path_fragment}"
      mkdir -p "$(dirname "${target_path}")"
      cp -f "${backup_path}" "${target_path}"
      chmod 755 "${target_path}"
    fi
  }
  for bin_item in curl yq xray sing-box v2fly hysteria mihomo; do
    restore_binary "$bin_item"
  done

  if [ -d "${temp_dir}/run" ]; then
    ui_print "  - Восстановить файлы времени выполнения, такие как журналы и pid"
    cp -af "${temp_dir}/run/." "/data/adb/box/run/"
  fi
fi

[ -z "$(find /data/adb/box/bin -type f -name '*' ! -name '*.bak')" ] && sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ 😱 Модуль установлен, но необходимо вручную скачать ядро ] /g' $MODPATH/module.prop

if [ "$KSU" = "true" ]; then
  sed -i "s/name=.*/name=Box for KernelSU/g" $MODPATH/module.prop
elif [ "$APATCH" = "true" ]; then
  sed -i "s/name=.*/name=Box for APatch/g" $MODPATH/module.prop
else
  sed -i "s/name=.*/name=Box for Magisk/g" $MODPATH/module.prop
fi
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >&2

ui_print "- Очистка оставшихся файлов"
rm -rf /data/adb/box/bin/.bin $MODPATH/box $MODPATH/box_service.sh

if [ "$backup_box" = "true" ] && [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
  ui_print " "
  if handle_choice "Обнаружены остаточные файлы резервных копий обновлений. Удалить их?" "Удалить резервную копию" "Сохранить резервную копию"; then
    ui_print "- Удаление резервной копии: ${temp_dir}"
    rm -rf "${temp_dir}"
    ui_print "- Резервная копия удалена"
  else
    ui_print "- Резервная копия сохранена: ${temp_dir}"
  fi
fi

ui_print "- Установка завершена. Пожалуйста, перезагрузите устройство."
