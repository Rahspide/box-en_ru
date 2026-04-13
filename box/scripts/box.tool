#!/system/bin/sh

scripts_dir="${0%/*}"

user_agent="box_for_root"
source /data/adb/box/settings.ini

# Use the log() provided in settings.ini
TOOL_LOG="${box_run}/tool.log"
busybox mkdir -p "$(dirname "$TOOL_LOG")"
box_log="$TOOL_LOG"

# Configure GitHub API access settings
setup_github_api() {
  rev1="busybox wget --no-check-certificate -qO-"
  if which curl >/dev/null; then
    rev1="curl --insecure -sL"
  fi
  if [ -n "$githubtoken" ]; then
    if which curl >/dev/null; then
      rev1="curl --insecure -sL -H \"Authorization: token ${githubtoken}\""
    else
      rev1="busybox wget --no-check-certificate -qO- --header=\"Authorization: token ${githubtoken}\""
    fi
    log Debug "GitHub Token configured, will use authenticated access to GitHub API"
  else
    log Debug "GitHub Token not configured, will use anonymous access to GitHub API"
  fi
}

mask_url() {
  local u="$1"
  echo "$u" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://)?([^/]+).*$#\1\2/***#'
}

# Startup notice
divider() {
  local line="----------------------------------------"
  [ -n "$box_log" ] && echo "$line" >> "$box_log"
}
trap divider EXIT
log Info "Executing command: $0 $@"

# Update file
upfile() {
  local file="$1"
  local update_url="$2"
  local custom_ua="$3" # Receive custom User-Agent
  local current_ua

  # If a custom UA is provided, use it; otherwise use the global default
  if [ -n "${custom_ua}" ]; then
    current_ua="${custom_ua}"
  else
    current_ua="${user_agent}"
  fi

  local file_bak="${file}.bak"
  [ -f "${file}" ] && mv "${file}" "${file_bak}"

  # Use ghproxy
  if [ "${use_ghproxy}" = "true" ] && [[ "${update_url}" == @(https://github.com/*|https://raw.githubusercontent.com/*|https://gist.github.com/*|https://gist.githubusercontent.com/*) ]]; then
    update_url="${url_ghproxy}/${update_url}"
  fi
  
  log_url="${update_url}"
  if [ "${LOG_MASK_URL}" = "mask" ]; then
    log_url="$(mask_url "${update_url}")"
  fi
  log Info "Starting download: ${log_url}"
  log Debug "Saving to: ${file}"
  log Debug "Using User-Agent: ${current_ua}"

  if which curl >/dev/null; then
    http_code=$(curl -L -s --insecure --http1.1 --compressed --user-agent "${current_ua}" -o "${file}" -w "%{http_code}" "${update_url}")
    curl_exit_code=$?

    if [ ${curl_exit_code} -ne 0 ]; then
      log Error "Download with curl failed (exit code: ${curl_exit_code})"
      [ -f "${file_bak}" ] && mv "${file_bak}" "${file}"
      return 1
    fi

    if [ "${http_code}" -ne 200 ]; then
      log Error "Download failed: server returned HTTP status code ${http_code}"
      [ -f "${file_bak}" ] && mv "${file_bak}" "${file}"
      return 1
    fi
  else
    if ! busybox wget --no-check-certificate -q -U "${current_ua}" -O "${file}" "${update_url}"; then
      log Error "Download with wget failed"
      [ -f "${file_bak}" ] && mv "${file_bak}" "${file}"
      return 1
    fi
  fi

  if [ ! -s "${file}" ]; then
    log Error "Download failed: file is empty"
    [ -f "${file_bak}" ] && mv "${file_bak}" "${file}"
    return 1
  fi
  
  log Info "Download successful"
  rm -f "${file_bak}" 2>/dev/null
  return 0
}

# CN IPv4/IPv6 list update
upcnip() {
  local did_any=false
  # IPv4
  if [ "${bypass_cn_ip}" = "true" ] && [ "${bypass_cn_ip_v4}" = "true" ]; then
    if [ -z "${cn_ip_url}" ] || [ -z "${cn_ip_file}" ]; then
      log Warning "cn_ip_url or cn_ip_file not configured, skipping IPv4"
    else
      log Info "Downloading CN IPv4 list → ${cn_ip_file}"
      if upfile "${cn_ip_file}" "${cn_ip_url}"; then
        log Info "CN IPv4 list update complete"
        did_any=true
      else
        log Error "CN IPv4 list update failed"
      fi
    fi
  else
    log Debug "IPv4 CN bypass not enabled (bypass_cn_ip/bypass_cn_ip_v4=false), skipping download"
  fi

  # IPv6
  if [ "${bypass_cn_ip}" = "true" ] && [ "${ipv6}" = "true" ] && [ "${bypass_cn_ip_v6}" = "true" ]; then
    if [ -z "${cn_ipv6_url}" ] || [ -z "${cn_ipv6_file}" ]; then
      log Warning "cn_ipv6_url or cn_ipv6_file not configured, skipping IPv6"
    else
      log Info "Downloading CN IPv6 list → ${cn_ipv6_file}"
      if upfile "${cn_ipv6_file}" "${cn_ipv6_url}"; then
        log Info "CN IPv6 list update complete"
        did_any=true
      else
        log Error "CN IPv6 list update failed"
      fi
    fi
  else
    log Debug "IPv6 CN bypass not enabled or IPv6 disabled, skipping download"
  fi

  $did_any && return 0 || return 1
}

# Restart core process
restart_box() {
  local core_to_restart=${1:-$bin_name}
  if [ -z "$core_to_restart" ]; then
    log Error "restart_box: no core specified for restart"
    return 1
  fi
  
  "${scripts_dir}/box.service" restart "$core_to_restart"
  
  local pid
  pid=$(busybox pidof "$core_to_restart")

  if [ -n "$pid" ]; then
    log Info "$core_to_restart restart complete [$(date +"%F %R")]"
  else
    log Error "Failed to restart $core_to_restart."
    "${scripts_dir}/box.iptables" disable >/dev/null 2>&1
  fi
}

# Check configuration
check() {
  case "${bin_name}" in
    sing-box)
      if ${bin_path} check -c "${sing_config}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "${sing_config} check passed"
      else
        log Debug "${sing_config}"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    mihomo)
      if ${bin_path} -t -d "${box_dir}/mihomo" -f "${mihomo_config}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "${mihomo_config} check passed"
      else
        log Debug "${mihomo_config}"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    xray)
      export XRAY_LOCATION_ASSET="${box_dir}/xray"
      if ${bin_path} -test -confdir "${box_dir}/${bin_name}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "Configuration check passed"
      else
        log Debug "$(ls ${box_dir}/${bin_name})"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    v2fly)
      export V2RAY_LOCATION_ASSET="${box_dir}/v2fly"
      if ${bin_path} test -d "${box_dir}/${bin_name}" > "${box_run}/${bin_name}_report.log" 2>&1; then
        log Info "Configuration check passed"
      else
        log Debug "$(ls ${box_dir}/${bin_name})"
        log Error "$(<"${box_run}/${bin_name}_report.log")" >&2
      fi
      ;;
    hysteria)
      true
      ;;
    *)
      log Error "<${bin_name}> Unknown binary file."
      exit 1
      ;;
  esac
}

# Reload base configuration
reload() {
  ip_port=$(if [ "${bin_name}" = "mihomo" ]; then busybox awk '/external-controller:/ {print $2}' "${mihomo_config}" | sed "s/'//g"; else busybox awk -F'[:,]' '/"external_controller"/ {print $2":"$3}' "${sing_config}" | sed 's/^[ \t]*//;s/"//g'; fi;)
  secret=$(if [ "${bin_name}" = "mihomo" ]; then busybox awk '/^secret:/ {print $2}' "${mihomo_config}" | sed 's/"//g'; else busybox awk -F'"' '/"secret"/ {print $4}' "${sing_config}" | head -n 1; fi;)

  curl_command="curl"
  if ! command -v curl >/dev/null; then
    if [ ! -e "${bin_dir}/curl" ]; then
      log Debug "$bin_dir/curl file not found, cannot reload configuration"
      log Debug "Starting download from GitHub"
      upcurl || exit 1
    fi
    curl_command="${bin_dir}/curl"
  fi

  check

  case "${bin_name}" in
    "mihomo")
      endpoint="http://${ip_port}/configs?force=true"

      if ${curl_command} -X PUT -H "Authorization: Bearer ${secret}" "${endpoint}" -d '{"path": "", "payload": ""}' 2>&1; then
        log Info "${bin_name} configuration reloaded successfully"
        return 0
      else
        log Error "${bin_name} configuration reload failed!"
        return 1
      fi
      ;;
    "sing-box")
      endpoint="http://${ip_port}/configs?force=true"
      if ${curl_command} -X PUT -H "Authorization: Bearer ${secret}" "${endpoint}" -d '{"path": "", "payload": ""}' 2>&1; then
        log Info "${bin_name} configuration reloaded successfully."
        return 0
      else
        log Error "${bin_name} configuration reload failed!"
        return 1
      fi
      ;;
    "xray"|"v2fly"|"hysteria")
      if [ -f "${box_pid}" ]; then
        if kill -0 "$(<"${box_pid}" 2>/dev/null)"; then
          restart_box
        fi
      fi
      ;;
    *)
      log Warning "${bin_name} does not support configuration reload via API."
      return 1
      ;;
  esac
}

# Get the latest curl
upcurl() {
  setup_github_api
  
  local arch
  case $(uname -m) in
    "aarch64") arch="aarch64" ;;
    "armv7l"|"armv8l") arch="armv7" ;;
    "i686") arch="i686" ;;
    "x86_64") arch="amd64" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac

  mkdir -p "${bin_dir}/backup"
  [ -f "${bin_dir}/curl" ] && cp "${bin_dir}/curl" "${bin_dir}/backup/curl.bak" >/dev/null 2>&1

  local latest_version=$($rev1 "https://api.github.com/repos/stunnel/static-curl/releases" | grep "tag_name" | busybox grep -oE "[0-9.]*" | head -1)
  local download_link="https://github.com/stunnel/static-curl/releases/download/${latest_version}/curl-linux-${arch}-glibc-${latest_version}.tar.xz"
  local temp_archive="${box_dir}/curl.tar.xz"
  local temp_extract_dir="${box_dir}/curl_temp"

  log Debug "Downloading ${download_link}"
  if ! upfile "${temp_archive}" "${download_link}"; then
    log Error "curl download failed"
    return 1
  fi
  
  rm -rf "${temp_extract_dir}"
  mkdir -p "${temp_extract_dir}"

  if ! busybox tar -xJf "${temp_archive}" -C "${temp_extract_dir}" >&2; then
    log Error "Failed to extract ${temp_archive}" >&2
    cp "${bin_dir}/backup/curl.bak" "${bin_dir}/curl" >/dev/null 2>&1 && log Info "curl restored"
    rm -f "${temp_archive}"
    rm -rf "${temp_extract_dir}"
    return 1
  fi

  local curl_binary=$(find "${temp_extract_dir}" -type f -name "curl")
  if [ -n "${curl_binary}" ]; then
    mv "${curl_binary}" "${bin_dir}/curl"
    log Info "curl successfully updated to ${bin_dir}/curl"
  else
    log Error "curl binary not found in the extracted archive"
    rm -f "${temp_archive}"
    rm -rf "${temp_extract_dir}"
    return 1
  fi
  
  chown "${box_user_group}" "${box_dir}/bin/curl"
  chmod 0755 "${bin_dir}/curl"

  rm -f "${temp_archive}"
  rm -rf "${temp_extract_dir}"
}

# Get the latest yq
upyq() {
  local arch platform
  case $(uname -m) in
    "aarch64") arch="arm64"; platform="android" ;;
    "armv7l"|"armv8l") arch="arm"; platform="android" ;;
    "i686") arch="386"; platform="android" ;;
    "x86_64") arch="amd64"; platform="android" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac

  local download_link="https://github.com/taamarin/yq/releases/download/prerelease/yq_${platform}_${arch}"

  log Debug "Downloading ${download_link}"
  upfile "${box_dir}/bin/yq" "${download_link}"

  chown "${box_user_group}" "${box_dir}/bin/yq"
  chmod 0755 "${box_dir}/bin/yq"
}

# Check and update geoip and geosite
upgeox() {
  geodata_mode=$(busybox awk '!/^ *#/ && /geodata-mode:*./{print $2}' "${mihomo_config}")
  [ -z "${geodata_mode}" ] && geodata_mode=false
  case "${bin_name}" in
    mihomo)
      geoip_file="${box_dir}/mihomo/Country.mmdb"
      geoip_url="https://github.com/MetaCubeX/meta-rules-dat/raw/release/country-lite.mmdb"
      geosite_file="${box_dir}/mihomo/GeoSite.dat"
      geosite_url="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat"
      ;;
    sing-box)
      geoip_file="${box_dir}/sing-box/geoip.db"
      geoip_url="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geoip-lite.db"
      geosite_file="${box_dir}/sing-box/geosite.db"
      geosite_url="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.db"
      ;;
    *)
      geoip_file="${box_dir}/${bin_name}/geoip.dat"
      geoip_url="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geoip-lite.dat"
      geosite_file="${box_dir}/${bin_name}/geosite.dat"
      geosite_url="https://github.com/MetaCubeX/meta-rules-dat/raw/release/geosite.dat"
      ;;
  esac
  if [ "${update_geo}" = "true" ] && { log Info "Daily GeoX update" && log Debug "Downloading ${geoip_url}"; } && upfile "${geoip_file}" "${geoip_url}" && { log Debug "Downloading ${geosite_url}" && upfile "${geosite_file}" "${geosite_url}"; }; then

    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.db.bak" -delete
    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.dat.bak" -delete
    find "${box_dir}/${bin_name}" -maxdepth 1 -type f -name "*.mmdb.bak" -delete

    log Debug "GeoX updated at $(date "+%F %R")"
    return 0
  else
   return 1
  fi
}

upgeox_all() {
  local original_bin_name=$bin_name
  for core in mihomo sing-box xray v2fly; do
      bin_name=$core
      upgeox
  done
  bin_name=$original_bin_name
}

# Update mihomo configuration proxy-providers
update_mihomo_providers() {
  yq="yq"
  if ! command -v yq &>/dev/null; then
    if [ ! -e "${box_dir}/bin/yq" ]; then
      log Debug "yq file not found, starting download from GitHub"
      ${scripts_dir}/box.tool upyq
    fi
    yq="${box_dir}/bin/yq"
  fi

  if [ ! -f "${mihomo_config}" ]; then
    log Error "Configuration file does not exist: ${mihomo_config}"
    return 1
  fi
  cp "${mihomo_config}" "${mihomo_config}.bak" 2>/dev/null
  local file_count=${#name_provide_mihomo_config[@]}
  if [ "$file_count" -eq 0 ]; then
    log Warning "No subscription files configured"
    return 1
  fi

  log Debug "Starting update of proxy-providers configuration items..."
  local config_dir="$(dirname "${mihomo_config}")"  
  
  local temp_providers="${mihomo_config}.providers.tmp"
  echo "proxy-providers:" > "${temp_providers}"
  
  for i in $(seq 0 $((file_count - 1))); do
    local file_name="${name_provide_mihomo_config[$i]}"
    local provider_file="${mihomo_provide_path}/${file_name}"
    local provider_name="${file_name%.yaml}"
    local provider_url="${subscription_url_mihomo[$i]}"
    local escaped_url

    if [ -z "${provider_url}" ]; then
      log Warning "Subscription URL is empty, skipping: ${provider_name}"
      continue
    fi
    escaped_url="$(echo "${provider_url}" | busybox sed 's/\\/\\\\/g; s/\"/\\"/g')"
    
    local relative_path
    if command -v realpath >/dev/null 2>&1 && [ -e "${provider_file}" ]; then
      relative_path="$(realpath --relative-to="${config_dir}" "${provider_file}")"
      [ -z "${relative_path}" ] && relative_path="./$(basename "${mihomo_provide_path}")/${file_name}"
    else
      relative_path="./$(basename "${mihomo_provide_path}")/${file_name}"
    fi

    log Debug "Adding provider: ${provider_name} -> ${relative_path} (http)"
    
    cat >> "${temp_providers}" <<EOF
  ${provider_name}:
    type: http
    url: "${escaped_url}"
    path: ${relative_path}
    interval: 86400
    health-check:
      enable: true
      url: https://cp.cloudflare.com
      interval: 300
      timeout: 1000
      tolerance: 100
EOF
  done
  
  local temp_output="${mihomo_config}.output.tmp"
  
  awk -v new_providers="${temp_providers}" '
    BEGIN {
      in_providers = 0
      providers_done = 0
    }
    /^proxy-providers:/ {
      in_providers = 1
      if (providers_done == 0) {
        while ((getline line < new_providers) > 0) {
          print line
        }
        close(new_providers)
        providers_done = 1
      }
      next
    }
    in_providers == 1 && /^[a-zA-Z-]+:/ {
      in_providers = 0
      print
      next
    }
    in_providers == 1 {
      next
    }
    {
      print
    }
    END {
      if (providers_done == 0) {
        while ((getline line < new_providers) > 0) {
          print line
        }
        close(new_providers)
      }
    }
  ' "${mihomo_config}" > "${temp_output}"
  
  mv "${temp_output}" "${mihomo_config}"
  
  rm -f "${temp_providers}"
  
  log Debug "proxy-providers configuration build complete"
  return 0
}

# Check and update subscriptions
upsubs() {
  if [ "${update_subscription}" != "true" ]; then
    log Warning "Subscription update disabled: update_subscription=\"${update_subscription}\""
    return 1
  fi

  yq="yq"
  if ! command -v yq &>/dev/null; then
    if [ ! -e "${box_dir}/bin/yq" ]; then
      log Debug "yq file not found, starting download from GitHub"
      ${scripts_dir}/box.tool upyq
    fi
    yq="${box_dir}/bin/yq"
  fi
  case "${bin_name}" in
    "mihomo")
      local url_count=${#subscription_url_mihomo[@]}
      local file_count=${#name_provide_mihomo_config[@]}

      if [ "$url_count" -eq 0 ]; then
        log Warning "${bin_name} subscription URL is empty"
        return 1
      fi

      if [ "$url_count" -ne "$file_count" ]; then
        log Error "Number of subscription URLs (${url_count}) does not match number of filenames (${file_count})!"
        return 1
      fi

      log Info "${bin_name} starting update of ${url_count} subscription(s) → $(date)"
      
      if [ -z "${mihomo_provide_path}" ] || ! mkdir -p "${mihomo_provide_path}"; then
          log Error "mihomo_provide_path is undefined or directory cannot be created!"
          return 1
      fi

      local success_count=0
      local update_failed=false
      local rules_extracted=false

      for i in $(seq 0 $((url_count - 1))); do
        local url="${subscription_url_mihomo[$i]}"
        local file_name="${name_provide_mihomo_config[$i]}"
        local provider_file="${mihomo_provide_path}/${file_name}"
        
        log Info "--> Processing subscription #${i}: ${file_name}"

        if [ "${renew}" = "true" ] && [ "$i" -eq 0 ]; then
          log Info "Detected renew=true, updating using only the first subscription URL"
          if LOG_MASK_URL=mask upfile "${mihomo_config}" "${url}" "ClashMeta"; then
            log Info "${mihomo_config} updated successfully"
            if [ -f "${box_pid}" ]; then
              kill -0 "$(<"${box_pid}" 2>/dev/null)" && \
              $scripts_dir/box.service restart 2>/dev/null
            fi
            log Info "${bin_name} subscription update complete → $(date)"
            exit 0
          else
            log Error "${mihomo_config} update failed"
            exit 1
          fi
        fi
        
        if LOG_MASK_URL=mask upfile "${provider_file}" "${url}" "ClashMeta"; then
          log Debug "File size: $(wc -c < "${provider_file}" 2>/dev/null || echo "unknown") bytes"
          log Debug "File path: ${provider_file}"
          
          local decoded_content
          decoded_content=$(base64 -d "${provider_file}" 2>/dev/null)

          if [ $? -eq 0 ] && echo "${decoded_content}" | grep -qE "vless://|vmess://|ss://|hysteria://|hysteria2://|anytls://|trojan://"; then
            log Info "Detected Base64 encoded subscription, decoding..."
            echo "${decoded_content}" > "${provider_file}"
            local proxy_count=$(echo "${decoded_content}" | grep -cE "vless://|vmess://|ss://|hysteria://|hysteria2://|anytls://|trojan://")
            log Debug "Extracted ${proxy_count} proxy node(s)"
            log Info "Subscription #${i} (Base64 decoded/raw URL) saved"
            success_count=$((success_count + 1))
          elif ${yq} 'has("proxies")' "${provider_file}" 2>/dev/null; then
            if [ "${custom_rules_subs}" = "true" ] && [ "$rules_extracted" = "false" ]; then
              if ${yq} 'has("rules")' "${provider_file}" &>/dev/null; then
                log Info "Rules found in ${file_name}, extracting..."
                ${yq} '.rules' "${provider_file}" > "${mihomo_provide_rules}"
                ${yq} -i '{"rules": .}' "${mihomo_provide_rules}"
                log Info "Rules extracted to ${mihomo_provide_rules}"
                rules_extracted=true
              fi
            fi

            log Debug "Standard subscription format, extracting proxies and overwriting original file..."
            local temp_proxies_file
            temp_proxies_file=$(mktemp)
            
            # Extract and validate proxies array
            log Debug "Attempting to extract proxies field..."     
            if ${yq} '.proxies' "${provider_file}" > "${temp_proxies_file}" 2>/dev/null; then
              if [ -s "${temp_proxies_file}" ]; then
                local proxy_count=$(${yq} 'length' "${temp_proxies_file}" 2>/dev/null || echo "0")
                log Debug "Extracted ${proxy_count} proxy node(s)"
                ${yq} -i '{"proxies": .}' "${temp_proxies_file}"
                mv "${temp_proxies_file}" "${provider_file}"
                log Info "Subscription #${i} (standard format) processed and saved"
                success_count=$((success_count + 1))
              else
                log Error "Subscription #${i} (${file_name}) proxies field is empty"
                rm -f "${temp_proxies_file}" "${provider_file}"
                update_failed=true
              fi
            else
              log Error "Subscription #${i} (${file_name}) yq extraction of proxies failed"
              rm -f "${temp_proxies_file}" "${provider_file}"
              update_failed=true
            fi

          elif ${yq} '.. | select(tag == "!!str")' "${provider_file}" 2>/dev/null | grep -qE "vless://|vmess://|ss://|hysteria://|hysteria2://|anytls://|trojan://"; then
            local proxy_count=$(${yq} '.. | select(tag == "!!str")' "${provider_file}" 2>/dev/null | grep -cE "vless://|vmess://|ss://|hysteria://|hysteria2://|anytls://|trojan://")
            log Debug "Extracted ${proxy_count} proxy node(s)"
            log Info "Subscription #${i} (raw URL) saved"
            success_count=$((success_count + 1))
          else
            log Error "Subscription #${i} (${file_name}) format unrecognized or content is empty, deleted"
            rm -f "${provider_file}"
            update_failed=true
          fi
        else
          log Error "Subscription #${i} (${file_name}) download failed"
          update_failed=true
        fi
      done

      log Info "Successfully updated ${success_count} / ${url_count} subscription(s)"
      
      if [ "${renew}" != "true" ] && [ "${success_count}" -gt 0 ]; then
        if [ "${auto_modify_config}" = "true" ]; then
          log Info "Updating proxy-providers configuration for ${name_mihomo_config}..."
          if update_mihomo_providers; then
            log Info "proxy-providers configuration updated successfully"
          else
            log Warning "proxy-providers configuration update failed, please check the configuration file manually"
          fi
        else
          log Info "auto_modify_config not enabled, skipping proxy-providers configuration update"
        fi
      fi
      
      if [ "${update_failed}" = "true" ]; then
        log Error "Some subscription URLs failed to update"
        return 1
      else
        log Info "Subscription updated at $(date +"%F %R")"
        return 0
      fi
      ;;
    "sing-box")
      update_file_name="${sing_config}"
      if [ -n "${subscription_url_singbox}" ]; then
        log Info "${bin_name} daily subscription update → $(date)"
        log Debug "Downloading ${update_file_name}"
        if upfile "${update_file_name}" "${subscription_url_singbox}" "sing-box"; then
          log Info "${update_file_name} saved"
          log Info "Subscription updated at $(date +"%F %R")"
          if [ -f "${box_pid}" ]; then
            kill -0 "$(<"${box_pid}" 2>/dev/null)" && \
            $scripts_dir/box.service restart 2>/dev/null
          fi
          return 0
        else
          log Error "Subscription update failed"
          return 1
        fi
      else
        log Warning "${bin_name} subscription URL is empty..."
        return 1
      fi
      ;;
    "xray"|"v2fly"|"hysteria")
      log Warning "${bin_name} does not support subscription feature.."
      return 1
      ;;
    *)
      log Error "<${bin_name}> Unknown binary file."
      return 1
      ;;
  esac
}

upkernel() {
  setup_github_api
  
  local core_to_update="$1"
  if [ -z "$core_to_update" ]; then
    log Error "upkernel: core name not provided"
    return 1
  fi

  mkdir -p "${bin_dir}/backup"
  if [ -f "${bin_dir}/${core_to_update}" ]; then
    cp "${bin_dir}/${core_to_update}" "${bin_dir}/backup/${core_to_update}.bak" >/dev/null 2>&1
  fi
  case $(uname -m) in
    "aarch64") 
      if [ "$core_to_update" = "mihomo" ]; then 
        arch="arm64-v8"
      else 
        arch="arm64"
      fi
      platform="android"
      ;;
    "armv7l"|"armv8l") arch="armv7"; platform="linux" ;;
    "i686") arch="386"; platform="linux" ;;
    "x86_64") arch="amd64"; platform="linux" ;;
    *) log Warning "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac
  
  local file_kernel="${core_to_update}-${arch}"
  case "${core_to_update}" in
    "mihomo_smart")
      log Info "Updating mihomo-smart core (from vernesong/mihomo)"
      local arch_smart
      case $(uname -m) in
        "aarch64") arch_smart="arm64-v8" ;;
        *) log Error "mihomo-smart currently only supports aarch64 architecture"; return 1 ;;
      esac

      local release_page_url="https://github.com/vernesong/mihomo/releases/expanded_assets/Prerelease-Alpha"
      [ "${use_ghproxy}" = "true" ] && release_page_url="${url_ghproxy}/${release_page_url}"
      
      local smart_version_tag=$($rev1 "${release_page_url}" | busybox grep -oE "smart-[a-f0-9]+" | head -1)

      if [ -z "$smart_version_tag" ]; then
        log Error "Failed to get latest version tag for mihomo-smart"
        return 1
      fi

      local download_link="https://github.com/vernesong/mihomo/releases/download/Prerelease-Alpha/mihomo-android-${arch_smart}-alpha-${smart_version_tag}.gz"
      local file_kernel="${core_to_update}-${arch_smart}"
      
      log Debug "Downloading ${download_link}"
      upfile "${box_dir}/${file_kernel}.gz" "${download_link}" && xkernel "$core_to_update" "" "" "" "$file_kernel"
      ;;
    "sing-box")
      api_url="https://api.github.com/repos/SagerNet/sing-box/releases"
      url_down="https://github.com/SagerNet/sing-box/releases"

      if [ "${singbox_stable}" = "disable" ]; then
        log Debug "Downloading ${core_to_update} pre-release"
        latest_version=$($rev1 "${api_url}" | grep "tag_name" | busybox grep -oE "v[0-9].*" | head -1 | cut -d'"' -f1)
      else
        log Debug "Downloading ${core_to_update} latest stable version"
        latest_version=$($rev1 "${api_url}/latest" | grep "tag_name" | busybox grep -oE "v[0-9.]*" | head -1)
      fi

      if [ -z "$latest_version" ]; then
        log Error "Failed to get sing-box latest stable/beta/alpha version"
        return 1
      fi

      download_link="${url_down}/download/${latest_version}/sing-box-${latest_version#v}-${platform}-${arch}.tar.gz"
      log Debug "Downloading ${download_link}"
      upfile "${box_dir}/${file_kernel}.tar.gz" "${download_link}" && xkernel "$core_to_update" "$platform" "$arch" "$latest_version" "$file_kernel"
      ;;
    "mihomo")
      download_link="https://github.com/MetaCubeX/mihomo/releases"

      if [ "${mihomo_stable}" = "enable" ]; then
        latest_version=$($rev1 "https://api.github.com/repos/MetaCubeX/mihomo/releases" | grep "tag_name" | busybox grep -oE "v[0-9.]*" | head -1)
        tag="$latest_version"
      else
        if [ "$use_ghproxy" == true ]; then
          download_link="${url_ghproxy}/${download_link}"
        fi
        tag="Prerelease-Alpha"
        latest_version=$($rev1 "${download_link}/expanded_assets/${tag}" | busybox grep -oE "alpha-[0-9a-z]+" | head -1)
      fi

      if [ -z "$latest_version" ]; then
        log Error "Failed to get mihomo latest stable/pre-release version"
        return 1
      fi

      local extension="gz"
      if [ "${platform}" = "android" ]; then
        extension="zip"
      fi

      filename="mihomo-${platform}-${arch}-${latest_version}"
      log Debug "Downloading ${download_link}/download/${tag}/${filename}.gz"
      upfile "${box_dir}/${file_kernel}.gz" "${download_link}/download/${tag}/${filename}.gz" && xkernel "$core_to_update" "" "" "" "$file_kernel"
      ;;
    "xray"|"v2fly")
      [ "${core_to_update}" = "xray" ] && bin='Xray' || bin='v2ray'
      api_url="https://api.github.com/repos/$(if [ "${core_to_update}" = "xray" ]; then echo "XTLS/Xray-core/releases"; else echo "v2fly/v2ray-core/releases"; fi)"
      latest_version=$($rev1 ${api_url} | grep "tag_name" | busybox grep -oE "v[0-9.]*" | head -1)

      if [ -z "$latest_version" ]; then
        log Error "Failed to get latest version number for ${core_to_update}"
        return 1
      fi

      case $(uname -m) in
        "i386") download_file="$bin-linux-32.zip" ;;
        "x86_64") download_file="$bin-linux-64.zip" ;;
        "armv7l"|"armv8l") download_file="$bin-linux-arm32-v7a.zip" ;;
        "aarch64") download_file="$bin-android-arm64-v8a.zip" ;;
        *) log Error "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
      esac
      download_link="https://github.com/$(if [ "${core_to_update}" = "xray" ]; then echo "XTLS/Xray-core/releases"; else echo "v2fly/v2ray-core/releases"; fi)"
      log Debug "Downloading ${download_link}/download/${latest_version}/${download_file}"
      upfile "${box_dir}/${file_kernel}.zip" "${download_link}/download/${latest_version}/${download_file}" && xkernel "$core_to_update" "" "" "" "$file_kernel"
      ;;
    "hysteria")
      local arch
      case $(uname -m) in
        "aarch64") arch="arm64" ;;
        "armv7l" | "armv8l") arch="armv7" ;;
        "i686") arch="386" ;;
        "x86_64") arch="amd64" ;;
        *)
          log Warning "Unsupported architecture: $(uname -m)"
          return 1
          ;;
      esac
      mkdir -p "${bin_dir}/backup"
      if [ -f "${bin_dir}/hysteria" ]; then
        cp "${bin_dir}/hysteria" "${bin_dir}/backup/hysteria.bak" >/dev/null 2>&1
      fi
      local latest_version=$($rev1 "https://api.github.com/repos/apernet/hysteria/releases" | grep "tag_name" | grep -oE "[0-9.].*" | head -1 | sed 's/,//g' | cut -d '"' -f 1)

      if [ -z "$latest_version" ]; then
        log Error "Failed to get latest version number for hysteria"
        return 1
      fi

      local download_link="https://github.com/apernet/hysteria/releases/download/app%2Fv${latest_version}/hysteria-android-${arch}"

      log Debug "Downloading ${download_link}"
      upfile "${bin_dir}/hysteria" "${download_link}" && xkernel "$core_to_update"
      ;;
    *)
      log Error "<${core_to_update}> Unknown binary file."
      return 1
      ;;
  esac
}

upkernels() {
  for core in "$@"; do
    upkernel "$core"
  done
}

xkernel() {
  local core_to_process="$1"
  local platform="$2"
  local arch="$3"
  local latest_version="$4"
  local file_kernel="$5"
  
  local original_bin_name=$bin_name
  local target_bin_name="$core_to_process"
  if [ "$core_to_process" = "mihomo_smart" ]; then
    target_bin_name="mihomo"
  fi
  
  bin_name=$core_to_process

  case "${core_to_process}" in
    "mihomo"|"mihomo_smart")
      gunzip_command="gunzip"
      if ! command -v gunzip >/dev/null; then
        gunzip_command="busybox gunzip"
      fi

      if ${gunzip_command} -f "${box_dir}/${file_kernel}.gz" >&2 && mv "${box_dir}/${file_kernel}" "${bin_dir}/${target_bin_name}"; then
        log Info "${target_bin_name} successfully updated (from: ${core_to_process})"
      else
        log Error "Failed to extract or move ${target_bin_name} core."
        bin_name=$original_bin_name
        return 1
      fi
      ;;
    "sing-box")
      tar_command="tar"
      if ! command -v tar >/dev/null; then
        tar_command="busybox tar"
      fi
      log Info "Extracting Sing-Box core..."
      if ${tar_command} -xf "${box_dir}/${file_kernel}.tar.gz" -C "${bin_dir}" >/dev/null; then
        mv "${bin_dir}/sing-box-${latest_version#v}-${platform}-${arch}/sing-box" "${bin_dir}/${core_to_process}"
        if [ -f "${box_pid}" ]; then
          rm -rf /data/adb/box/sing-box/cache.db
          restart_box "$core_to_process"
        else
          log Debug "${core_to_process} does not need to restart."
        fi
      else
        log Error "Failed to extract ${box_dir}/${file_kernel}.tar.gz."
      fi
      [ -d "${bin_dir}/sing-box-${latest_version#v}-${platform}-${arch}" ] && \
        rm -r "${bin_dir}/sing-box-${latest_version#v}-${platform}-${arch}"
      ;;
    "v2fly"|"xray")
      bin="xray"
      if [ "${core_to_process}" != "xray" ]; then
        bin="v2ray"
      fi
      unzip_command="unzip"
      if ! command -v unzip >/dev/null; then
        unzip_command="busybox unzip"
      fi

      mkdir -p "${bin_dir}/update"
      log Info "Extracting ${bin} core..."
      if ${unzip_command} -oq "${box_dir}/${file_kernel}.zip" "${bin}" -d "${bin_dir}/update"; then
        if mv "${bin_dir}/update/${bin}" "${bin_dir}/${core_to_process}"; then
          true # Success
        else
          log Error "Failed to move core."
          rm -rf "${bin_dir}/update"
          return 1
        fi
      else
        log Error "Failed to extract ${box_dir}/${file_kernel}.zip."
        rm -rf "${bin_dir}/update"
        return 1
      fi
      rm -rf "${bin_dir}/update"
      ;;
    "hysteria")
      true
      ;;
    *)
      log Error "<${core_to_process}> Unknown binary file."
      bin_name=$original_bin_name
      return 1
      ;;
  esac

  find "${box_dir}" -maxdepth 1 -type f -name "${file_kernel}.*" -delete

  chown ${box_user_group} "${bin_dir}/${target_bin_name}"
  chmod 0755 "${bin_dir}/${target_bin_name}"
  
  if [ -f "${box_pid}" ]; then
    if [ "$original_bin_name" = "$target_bin_name" ]; then
      log Info "Detected that the running core has been updated, automatically restarting service..."
      restart_box "$target_bin_name"
    else
      log Info "${target_bin_name} has been updated, but the currently running core is ${original_bin_name}, no restart needed."
    fi
  else
    log Info "Service is not running, no restart needed."
  fi
  
  bin_name=$original_bin_name
}
upxui() {
  if [[ "${bin_name}" == @(mihomo|sing-box) ]]; then
    local ui_path
    local ui_url
    if [ "${bin_name}" = "mihomo" ]; then
      ui_path=$(busybox awk '!/^ *#/ && /^external-ui:/ {print $2; exit}' "${mihomo_config}" | sed "s/[\"']//g")
      ui_url=$(busybox awk '!/^ *#/ && /^external-ui-url:/ {print $2; exit}' "${mihomo_config}" 2>/dev/null | sed "s/[\"']//g")
    else
      ui_path=$(busybox awk -F '"' '/"external_ui"/ {print $4}' "${sing_config}" | head -n 1)
      ui_url=$(busybox awk -F '"' '/"external_ui_download_url"/ {print $4; exit}' "${sing_config}" 2>/dev/null)
    fi
    
    if [ -z "${ui_path}" ]; then
      ui_path="./dashboard"
      log Warning "external-ui/external_ui field not found in configuration file, using default path: ${ui_path}"
    fi
    log Debug "UI path from configuration file: ${ui_path}"
    
    local dashboard_dir
    if [[ "${ui_path}" == ./* ]]; then
      dashboard_dir="${box_dir}/${bin_name}/${ui_path#./}"
    elif [[ "${ui_path}" == /* ]]; then
      dashboard_dir="${ui_path}"
    else
      dashboard_dir="${box_dir}/${bin_name}/${ui_path}"
    fi
    log Info "Dashboard target directory: ${dashboard_dir}"
    
    file_dashboard="${box_dir}/${bin_name}_dashboard.zip"
    if [ -n "${ui_url}" ]; then
      url="${ui_url}"
    else
      url="https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"
    fi
    
    if upfile "${file_dashboard}" "${url}"; then
      if [ ! -d "${dashboard_dir}" ]; then
        log Info "Dashboard folder does not exist, creating: ${dashboard_dir}"
        mkdir -p "${dashboard_dir}"
      else
        log Debug "Cleaning existing dashboard files: ${dashboard_dir}"
        rm -rf "${dashboard_dir}/"*
      fi
      
      if command -v unzip >/dev/null; then
        unzip_command="unzip"
      else
        unzip_command="busybox unzip"
      fi
      
      log Info "Extracting Dashboard..."
      local temp_extract_dir="${box_dir}/${bin_name}_dashboard_temp"
      rm -rf "${temp_extract_dir}"
      mkdir -p "${temp_extract_dir}"
      
      if "${unzip_command}" -oq "${file_dashboard}" -d "${temp_extract_dir}"; then
        local html_path
        html_path=$(busybox find "${temp_extract_dir}" -maxdepth 3 -type f -name index.html | head -n 1)
        if [ -n "${html_path}" ]; then
          local html_dir
          html_dir="${html_path%/*}"
          mv -f "${html_dir}"/* "${dashboard_dir}/"
        else
          local top_dir
          top_dir=$(find "${temp_extract_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)
          if [ -n "${top_dir}" ] && [ -z "$(find "${temp_extract_dir}" -mindepth 1 -maxdepth 1 -type d | sed -n '2p')" ]; then
            mv -f "${top_dir}"/* "${dashboard_dir}/"
          else
            mv -f "${temp_extract_dir}"/* "${dashboard_dir}/"
          fi
        fi
      else
        log Error "Failed to extract Dashboard"
        rm -f "${file_dashboard}"
        rm -rf "${temp_extract_dir}"
        return 1
      fi

      if [ -z "$(find "${dashboard_dir}" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
        log Error "Dashboard directory is empty, update failed"
        rm -f "${file_dashboard}"
        rm -rf "${temp_extract_dir}"
        return 1
      fi
      rm -f "${file_dashboard}"
      rm -rf "${temp_extract_dir}"
      log Info "Dashboard updated successfully → ${dashboard_dir}"
    else
      log Error "Failed to download Dashboard"
      return 1
    fi
    return 0
  else
    log Debug "${bin_name} does not support dashboard"
    return 1
  fi
}

cgroup_blkio() {
  local pid_file="$1"
  local fallback_weight="${2:-900}"

  if [ -z "$pid_file" ] || [ ! -f "$pid_file" ]; then
    log Warning "PID file missing or invalid: $pid_file"
    return 1
  fi

  local PID=$(<"$pid_file" 2>/dev/null)
  if [ -z "$PID" ] || ! kill -0 "$PID" >/dev/null 2>&1; then
    log Warning "PID $PID from ${pid_file} is invalid or not running"
    return 1
  fi

  if [ -z "$blkio_path" ]; then
    blkio_path=$(mount | grep cgroup | busybox awk '/blkio/{print $3}' | head -1)
    if [ -z "$blkio_path" ] || [ ! -d "$blkio_path" ]; then
      log Warning "blkio cgroup path not found"
      return 1
    fi
  fi

  local target="${blkio_path}/box"
  
  if [ ! -d "$target" ]; then
    mkdir -p "$target" 2>/dev/null
    if [ ! -d "$target" ]; then
      log Warning "Unable to create box blkio directory: $target"
      if [ -d "${blkio_path}/foreground" ]; then
        target="${blkio_path}/foreground"
        log Info "Falling back to existing blkio directory: foreground"
      elif [ -d "${blkio_path}/top-app" ]; then
        target="${blkio_path}/top-app"
        log Info "Falling back to existing blkio directory: top-app"
      else
        log Warning "blkio target not found, unable to set IO weight"
        return 1
      fi
    else
      log Info "Successfully created dedicated box blkio directory: $target"
      echo "$fallback_weight" > "${target}/blkio.weight" 2>/dev/null
      if [ $? -ne 0 ]; then
        log Warning "Unable to set blkio weight to ${target}/blkio.weight"
      else
        log Info "blkio weight set: $fallback_weight"
      fi
    fi
  fi

  echo "$PID" > "${target}/cgroup.procs" 2>/dev/null
  if [ $? -eq 0 ]; then
    log Info "PID $PID assigned to ${target}, IO weight [$fallback_weight]"
    return 0
  else
    log Warning "Unable to assign PID $PID to ${target}"
    return 1
  fi
}

cgroup_memcg() {
  local pid_file="$1"
  local raw_limit="$2"

  if [ -z "$pid_file" ] || [ ! -f "$pid_file" ]; then
    log Warning "PID file missing or invalid: $pid_file"
    return 1
  fi

  if [ -z "$raw_limit" ]; then
    log Warning "memcg limit not specified"
    return 1
  fi

  local limit
  case "$raw_limit" in
    *[Mm])
      limit=$(( ${raw_limit%[Mm]} * 1024 * 1024 ))
      ;;
    *[Gg])
      limit=$(( ${raw_limit%[Gg]} * 1024 * 1024 * 1024 ))
      ;;
    *[Kk])
      limit=$(( ${raw_limit%[Kk]} * 1024 ))
      ;;
    *[0-9])
      limit=$raw_limit
      ;;
    *)
      log Warning "Invalid memcg limit format: $raw_limit"
      return 1
      ;;
  esac

  local PID
  PID=$(<"$pid_file" 2>/dev/null)
  if [ -z "$PID" ] || ! kill -0 "$PID" >/dev/null 2>&1; then
    log Warning "PID $PID from ${pid_file} is invalid or not running"
    return 1
  fi

  if [ -z "$memcg_path" ]; then
    memcg_path=$(mount | grep cgroup | busybox awk '/memory/{print $3}' | head -1)
    if [ -z "$memcg_path" ] || [ ! -d "$memcg_path" ]; then
      log Warning "memory cgroup path not found"
      return 1
    fi
  fi

  local target="${memcg_path}/box"
  
  if [ ! -d "$target" ]; then
    mkdir -p "$target" 2>/dev/null
    if [ ! -d "$target" ]; then
      log Warning "Unable to create box memory directory: $target"
      local name="${bin_name:-app}"
      target="${memcg_path}/${name}"
      mkdir -p "$target" 2>/dev/null
      if [ ! -d "$target" ]; then
        log Warning "Unable to create memory directory: $target"
        return 1
      fi
      log Info "Falling back to memory directory: $target"
    else
      log Info "Successfully created dedicated box memory directory: $target"
    fi
  fi

  local hr_limit="$limit B"
  if [ "$limit" -ge 1073741824 ]; then
    hr_limit="$(busybox awk -v b=$limit 'BEGIN{printf "%.2f GiB", b/1073741824}')"
  elif [ "$limit" -ge 1048576 ]; then
    hr_limit="$(busybox awk -v b=$limit 'BEGIN{printf "%.2f MiB", b/1048576}')"
  elif [ "$limit" -ge 1024 ]; then
    hr_limit="$(busybox awk -v b=$limit 'BEGIN{printf "%.2f KiB", b/1024}')"
  fi

  echo "$limit" > "${target}/memory.limit_in_bytes" 2>/dev/null
  if [ $? -ne 0 ]; then
    log Warning "Unable to set memory limit to ${target}/memory.limit_in_bytes"
    return 1
  fi
  log Info "Memory limit set: ${hr_limit} (${limit} bytes)"

  echo "$PID" > "${target}/cgroup.procs" 2>/dev/null
  if [ $? -eq 0 ]; then
    log Info "PID $PID assigned to ${target}, memory limit [$hr_limit]"
    return 0
  else
    log Warning "Unable to assign PID $PID to ${target}"
    return 1
  fi
}

cgroup_cpuset() {
  local pid_file="${1}"
  local cores="${2}"

  if [ -z "${pid_file}" ] || [ ! -f "${pid_file}" ]; then
    log Warning "PID file missing or invalid: ${pid_file}"
    return 1
  fi

  local PID
  PID=$(<"${pid_file}" 2>/dev/null)
  if [ -z "$PID" ] || ! kill -0 "$PID" >/dev/null; then
    log Warning "PID $PID from ${pid_file} is invalid or not running"
    return 1
  fi

  if [ -z "${cores}" ]; then
    local total_core
    total_core=$(nproc --all 2>/dev/null)
    if [ -z "$total_core" ] || [ "$total_core" -le 0 ]; then
      log Warning "Failed to detect CPU cores"
      return 1
    fi
    cores="0-$((total_core - 1))"
  fi

  if [ -z "${cpuset_path}" ]; then
    cpuset_path=$(mount | grep cgroup | busybox awk '/cpuset/{print $3}' | head -1)
    if [ -z "${cpuset_path}" ] || [ ! -d "${cpuset_path}" ]; then
      log Warning "cpuset_path not found"
      return 1
    fi
  fi

  local cpuset_target="${cpuset_path}/box"
  
  if [ ! -d "${cpuset_target}" ]; then
    mkdir -p "${cpuset_target}" 2>/dev/null
    if [ ! -d "${cpuset_target}" ]; then
      log Warning "Unable to create box cpuset directory: ${cpuset_target}"
      cpuset_target="${cpuset_path}/foreground"
      if [ ! -d "${cpuset_target}" ]; then
        cpuset_target="${cpuset_path}/top-app"
      fi
      if [ ! -d "${cpuset_target}" ]; then
        cpuset_target="${cpuset_path}/apps"
        if [ ! -d "${cpuset_target}" ]; then
          log Warning "cpuset target not found, unable to set CPU cores"
          return 1
        fi
      fi
      log Info "Falling back to existing cpuset directory: ${cpuset_target}"
    else
      log Info "Successfully created dedicated box cpuset directory: ${cpuset_target}"
      if [ -f "${cpuset_path}/cpus" ]; then
        cat "${cpuset_path}/cpus" > "${cpuset_target}/cpus" 2>/dev/null
      fi
      if [ -f "${cpuset_path}/mems" ]; then
        cat "${cpuset_path}/mems" > "${cpuset_target}/mems" 2>/dev/null
      fi
    fi
  fi

  echo "${cores}" > "${cpuset_target}/cpus" 2>/dev/null
  if [ $? -ne 0 ]; then
    log Warning "Unable to set CPU cores to ${cpuset_target}/cpus"
    return 1
  fi
  
  echo "0" > "${cpuset_target}/mems" 2>/dev/null
  if [ $? -ne 0 ]; then
    log Warning "Unable to set memory nodes to ${cpuset_target}/mems"
    return 1
  fi

  echo "${PID}" > "${cpuset_target}/cgroup.procs" 2>/dev/null
  if [ $? -eq 0 ]; then
    log Info "PID $PID assigned to ${cpuset_target}, CPU cores [$cores]"
    return 0
  else
    log Warning "Unable to assign PID $PID to ${cpuset_target}"
    return 1
  fi
}

webroot() {
  ip_port=$(if [ "${bin_name}" = "mihomo" ]; then busybox awk '/external-controller:/ {print $2}' "${mihomo_config}"; else busybox awk -F'[:,]' '/"external_controller"/ {print $2":"$3}' "${sing_config}" | sed 's/^[ \t]*//;s/"//g'; fi;)
  secret=$(if [ "${bin_name}" = "mihomo" ]; then busybox awk '/^secret:/ {print $2}' "${mihomo_config}" | sed 's/"//g'; else busybox awk -F'"' '/"secret"/ {print $4}' "${sing_config}" | head -n 1; fi;)
  path_webroot="/data/adb/modules/box_for_root/webroot/index.html"
  touch "$path_webroot"
  if [[ "${bin_name}" = @(mihomo|sing-box) ]]; then
    echo -e '
  <!DOCTYPE html>
  <script>
      document.location = 'http://127.0.0.1:9090/ui/'
  </script>
  </html>
  ' > $path_webroot
    sed -i "s#document\.location =.*#document.location = 'http://$ip_port/ui/'#" $path_webroot
  else
   echo -e '
  <!DOCTYPE html>
  <html lang="zh-CN">
  <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>WebUI not supported</title>
      <style>
          body {
              font-family: Arial, sans-serif;
              text-align: center;
              padding: 50px;
          }
          h1 {
              color: red;
          }
      </style>
  </head>
  <body>
      <h1>WebUI not supported</h1>
      <p>Sorry, xray/v2ray does not support the required WebUI functionality.</p>
  </body>
  </html>' > $path_webroot
  fi
  log Info "WebUI page generated/updated: ${path_webroot} → http://${ip_port}/ui/ (core: ${bin_name})"
}

bond0() {
  sysctl -w net.ipv4.tcp_low_latency=0 >/dev/null 2>&1
  log Debug "tcp low latency: 0"

  for dev in /sys/class/net/wlan*; do ip link set dev $(basename $dev) txqueuelen 3000; done
  log Debug "wlan* transmit queue length: 3000"

  for txqueuelen in /sys/class/net/rmnet_data*; do txqueuelen_name=$(basename $txqueuelen); ip link set dev $txqueuelen_name txqueuelen 1000; done
  log Debug "rmnet_data* transmit queue length: 1000"

  for mtu in /sys/class/net/rmnet_data*; do mtu_name=$(basename $mtu); ip link set dev $mtu_name mtu 1500; done
  log Debug "rmnet_data* MTU: 1500"
}

bond1() {
  sysctl -w net.ipv4.tcp_low_latency=1 >/dev/null 2>&1
  log Debug "tcp low latency: 1"

  for dev in /sys/class/net/wlan*; do ip link set dev $(basename $dev) txqueuelen 4000; done
  log Debug "wlan* transmit queue length: 4000"

  for txqueuelen in /sys/class/net/rmnet_data*; do txqueuelen_name=$(basename $txqueuelen); ip link set dev $txqueuelen_name txqueuelen 2000; done
  log Debug "rmnet_data* transmit queue length: 2000"

  for mtu in /sys/class/net/rmnet_data*; do mtu_name=$(basename $mtu); ip link set dev $mtu_name mtu 9000; done
  log Debug "rmnet_data* MTU: 9000"
}

case "$1" in
  check)
    check
    ;;
  memcg|cpuset|blkio)
    case "$1" in
      memcg)
        memcg_path=""
        cgroup_memcg "${box_pid}" ${memcg_limit}
        ;;
      cpuset)
        cpuset_path=""
        cgroup_cpuset "${box_pid}" ${allow_cpu}
        ;;
      blkio)
        blkio_path=""
        cgroup_blkio "${box_pid}" "${weight}"
        ;;
    esac
    ;;
  bond0|bond1)
    $1
    ;;
  geosub)
    upsubs || exit 1
    upgeox
    if [ -f "${box_pid}" ]; then
      kill -0 "$(<"${box_pid}" 2>/dev/null)" && reload
    fi
    ;;
  geox|subs)
    if [ "$1" = "geox" ]; then
      upgeox
    else
      upsubs || exit 1
    fi
    if [ -f "${box_pid}" ]; then
      kill -0 "$(<"${box_pid}" 2>/dev/null)" && reload
    fi
    ;;
  upkernel)
    upkernel "$2"
    ;;  
  upkernels)
    shift
    upkernels "$@"
    ;;
  upgeox_all)
    upgeox_all
    ;;
  upxui)
    upxui
    ;;
  upcnip)
    upcnip
    ;;
  upyq|upcurl)
    $1
    ;;
  reload)
    reload
    ;;
  webroot)
    webroot
    ;;
  all)
    upyq
    upcurl
    upgeox_all
    upkernels sing-box mihomo xray v2fly hysteria
    for bin_name in "${bin_list[@]}"; do
      upsubs
      upxui
    done
    ;;
  *)
    log Error "$0 $1 not found"
    log Info "Usage: $0 {check|memcg|cpuset|blkio|geosub|geox|subs|upkernel [name]|upkernels [name...]|upgeox_all|upxui|upyq|upcurl|upcnip|reload|webroot|bond0|bond1|all}"
    log Info "upkernel supported cores: sing-box, mihomo, mihomo_smart, xray, v2fly, hysteria"
    ;;
esac
