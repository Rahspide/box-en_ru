
#!/system/bin/sh

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

if [ "$BOOTMODE" != true ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Please install this module in Magisk/KernelSU/APatch Manager"
  ui_print "! Installation from Recovery is not supported"
  abort "-----------------------------------------------------------"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Please upgrade your KernelSU and its manager"
  abort "-----------------------------------------------------------"
fi

service_dir="/data/adb/service.d"
if [ "$KSU" = "true" ]; then
  ui_print "- KernelSU version detected: $KSU_VER ($KSU_VER_CODE)"
  [ "$KSU_VER_CODE" -lt 10683 ] && service_dir="/data/adb/ksu/service.d"
elif [ "$APATCH" = "true" ]; then
  APATCH_VER=$(cat "/data/adb/ap/version")
  ui_print "- APatch version detected: $APATCH_VER"
else
  ui_print "- Magisk version detected: $MAGISK_VER ($MAGISK_VER_CODE)"
fi

mkdir -p "${service_dir}"
if [ -d "/data/adb/modules/box_for_magisk" ]; then
  rm -rf "/data/adb/modules/box_for_magisk"
  ui_print "- Old module has been deleted."
fi

ui_print "- Installing Box for Magisk/KernelSU/APatch"
unzip -o "$ZIPFILE" -x 'META-INF/*' -x 'webroot/*' -d "$MODPATH" >&2
if [ -d "/data/adb/box" ]; then
  ui_print "- Back up existing Box data"
  temp_bak=$(mktemp -d -p "/data/adb/box" box.XXXXXXXXXX)
  temp_dir="${temp_bak}"
  mv /data/adb/box/* "${temp_dir}/"
  mv "$MODPATH/box/"* /data/adb/box/
  backup_box="true"
else
  mv "$MODPATH/box" /data/adb/
fi

ui_print "- Create directory"
mkdir -p /data/adb/box/ /data/adb/box/run/ /data/adb/box/bin/

ui_print "- Extract uninstall.sh and box_service.sh"
unzip -j -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >&2
unzip -j -o "$ZIPFILE" 'box_service.sh' -d "${service_dir}" >&2

ui_print "- Set permissions"
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
    local choice_yes="${2:-Yes}"
    local choice_no="${3:-No}"
    local timeout_seconds="${4:-10}"

    ui_print " "
    ui_print "-----------------------------------------------------------"
    ui_print "- ${question}"
    ui_print "- [ Vol+ ]: ${choice_yes}"
    ui_print "- [ Vol- ]: ${choice_no}"
    ui_print "- [ No selection within ${timeout_seconds}s, defaulting to: ${choice_yes} ]"

    timeout 0.1 getevent -c 1 >/dev/null 2>&1

    start_key_listener
    volume_key_detection "$timeout_seconds"
    local result=$?
    stop_key_listener
    
    if [ "$result" -eq 0 ]; then
        ui_print "  => You selected: ${choice_yes}"
        return 0
    elif [ "$result" -eq 1 ]; then
        ui_print "  => You selected: ${choice_no}"
        return 1
    else
        ui_print "  => Timed out, defaulting to: ${choice_yes}"
        return 0
    fi
}

ui_print " "
ui_print "==========================================================="
ui_print "==         Box for Magisk/KernelSU/APatch Installer         =="
ui_print "==========================================================="


if handle_choice "Do you need to download the kernel or data files?" "Yes, download" "No, skip all"; then

    if handle_choice "Would you like to use mirror acceleration for the remaining downloads?" "Use mirror acceleration" "Download directly"; then
        ui_print "- Mirror acceleration enabled."
        sed -i 's/use_ghproxy=.*/use_ghproxy="true"/' /data/adb/box/settings.ini
    else
        ui_print "- Mirror acceleration has been disabled."
        sed -i 's/use_ghproxy=.*/use_ghproxy="false"/' /data/adb/box/settings.ini
    fi

    COMPONENTS_TO_DOWNLOAD=""

    if handle_choice "Do you need to customize the download contents?" "Customize" "Download all components with one click"; then
        ui_print "- Go to custom download..."
        if handle_choice "Do you want to download the GeoX data files (geoip/geosite)?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD geox"
        fi
        if handle_choice "Do you want to download the utility tools (yq, curl)?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD utils"
        fi
        
        ui_print " "
        ui_print "-----------------------------------------------------------"
        ui_print "- Please select the kernel you need to download:"
        if handle_choice "  - Download the sing-box kernel?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD sing-box"
        fi
        if handle_choice "  - Download the mihomo kernel?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD mihomo"
        fi
        if handle_choice "  - Download the mihomo_smart kernel (with the Smart policy group)? (Conflicts with mihomo; please do not download both at the same time)" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD mihomo_smart"
        fi
        if handle_choice "  - Download the xray kernel?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD xray"
        fi
        if handle_choice "  - Download the v2fly kernel?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD v2fly"
        fi
        if handle_choice "  - Download the hysteria kernel?" "Download" "Skip"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD hysteria"
        fi
    else
        ui_print "- One-click download of all components selected."
        COMPONENTS_TO_DOWNLOAD="geox utils sing-box mihomo xray v2fly hysteria"
    fi

    ui_print " "
    ui_print "==========================================================="
    ui_print "- Download task preview"
    ui_print "-----------------------------------------------------------"
    
    if [ -z "$COMPONENTS_TO_DOWNLOAD" ]; then
        ui_print "  - No download tasks."
    else
        COMPONENTS_TO_DOWNLOAD=$(echo "$COMPONENTS_TO_DOWNLOAD" | sed 's/^ *//')
        ui_print "  - Will download: ${COMPONENTS_TO_DOWNLOAD}"
    fi
    ui_print "==========================================================="

    if [ -n "$COMPONENTS_TO_DOWNLOAD" ]; then
        if handle_choice "Would you like to start the above download tasks?" "Start download" "Cancel all"; then
            ui_print "- Starting downloads..."
            for component in $COMPONENTS_TO_DOWNLOAD; do
              case "$component" in
                geox)
                  ui_print "  -> Downloading GeoX..."
                  /data/adb/box/scripts/box.tool upgeox_all
                  ;;
                utils)
                  ui_print "  -> Downloading yq..."
                  /data/adb/box/scripts/box.tool upyq
                  ui_print "  -> Downloading curl..."
                  /data/adb/box/scripts/box.tool upcurl
                  ;;
                *)
                  ui_print "  -> Downloading kernel: $component..."
                  /data/adb/box/scripts/box.tool upkernel "$component"
                  ;;
              esac
            done
            ui_print "- All download tasks have been completed!"
        else
            ui_print "- All download tasks have been canceled."
        fi
    fi
else
    ui_print "- All download steps have been skipped."
fi


if [ "${backup_box}" = "true" ]; then
  ui_print " "
  ui_print "- Restoring user configuration and data..."

  if [ -f "${temp_dir}/settings.ini" ]; then
    if [ -f "/data/adb/box/settings.ini" ]; then
      if handle_choice "Old settings.ini detected. How would you like to proceed?" "Overwrite (use the new version to overwrite the old version)" "Incremental merge (write old values only to existing keys in the new version)"; then
        ui_print "  - Selected to use the new settings.ini (old settings will not be applied)"
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
        ui_print "  - User customizations have been incrementally merged into the new settings.ini file"
      fi
    else
      cp -f "${temp_dir}/settings.ini" "/data/adb/box/settings.ini"
      ui_print "  - settings.ini has been restored"
    fi
  fi

  restore_config_dir() {
    config_dir="$1"
    if [ -d "${temp_dir}/${config_dir}" ]; then
        ui_print "  - Restoring ${config_dir} directory config"
        cp -af "${temp_dir}/${config_dir}/." "/data/adb/box/${config_dir}/"
    fi
  }
  for dir in mihomo xray v2fly sing-box hysteria; do
    restore_config_dir "$dir"
  done

  ui_print "  - Restore root directory configuration file"
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
      ui_print "  - Restoring binary: ${bin_path_fragment}"
      mkdir -p "$(dirname "${target_path}")"
      cp -f "${backup_path}" "${target_path}"
      chmod 755 "${target_path}"
    fi
  }
  for bin_item in curl yq xray sing-box v2fly hysteria mihomo; do
    restore_binary "$bin_item"
  done

  if [ -d "${temp_dir}/run" ]; then
    ui_print "  - Restore runtime files, including logs and PIDs"
    cp -af "${temp_dir}/run/." "/data/adb/box/run/"
  fi
fi

[ -z "$(find /data/adb/box/bin -type f -name '*' ! -name '*.bak')" ] && sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ 😱 Module installed, but kernel must be downloaded manually ] /g' $MODPATH/module.prop

if [ "$KSU" = "true" ]; then
  sed -i "s/name=.*/name=Box for KernelSU/g" $MODPATH/module.prop
elif [ "$APATCH" = "true" ]; then
  sed -i "s/name=.*/name=Box for APatch/g" $MODPATH/module.prop
else
  sed -i "s/name=.*/name=Box for Magisk/g" $MODPATH/module.prop
fi
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >&2

ui_print "- Clean up residual files"
rm -rf /data/adb/box/bin/.bin $MODPATH/box $MODPATH/box_service.sh

if [ "$backup_box" = "true" ] && [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
  ui_print " "
  if handle_choice "Residual backup files from the update have been detected. Do you want to delete them?" "Delete backup" "Keep backup"; then
    ui_print "- Deleting backup: ${temp_dir}"
    rm -rf "${temp_dir}"
    ui_print "- Backup deleted"
  else
    ui_print "- Backup retained at: ${temp_dir}"
  fi
fi

ui_print "- Installation complete. Please restart the device."
