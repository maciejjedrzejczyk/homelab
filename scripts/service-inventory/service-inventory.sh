#!/bin/bash

# Service Inventory Script
# Collects information about Docker containers, non-container services, nginx proxies, and DNS entries
# Compatible with bash 3.2+

set -e

# Configuration
COLLECT_CONTAINERS=true
COLLECT_NON_CONTAINERS=true
COLLECT_NGINX=true
COLLECT_PIHOLE=true
NGINX_CONTAINER="nginx-proxy-manager"
PIHOLE_CONTAINER="pihole-unbound"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/reports"
OUTPUT_FILE=""
FORMAT="markdown"
DIFF_MODE=false
DIFF_AGAINST=""
# Regex pattern for non-container services to detect (extend as needed)
SERVICE_FILTER="(jellyfin|synergy|ollama|transmission|plex|radarr|sonarr|prowlarr)"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-containers) COLLECT_CONTAINERS=false; shift ;;
    --no-non-containers) COLLECT_NON_CONTAINERS=false; shift ;;
    --no-nginx) COLLECT_NGINX=false; shift ;;
    --no-pihole) COLLECT_PIHOLE=false; shift ;;
    --nginx-container) NGINX_CONTAINER="$2"; shift 2 ;;
    --pihole-container) PIHOLE_CONTAINER="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --filter) SERVICE_FILTER="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --diff) DIFF_MODE=true; DIFF_AGAINST="${2:-}"; shift; [ -n "$DIFF_AGAINST" ] && shift ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --no-containers        Skip Docker container collection"
      echo "  --no-non-containers    Skip non-container service collection"
      echo "  --no-nginx             Skip nginx proxy configuration"
      echo "  --no-pihole            Skip Pi-hole DNS entries"
      echo "  --nginx-container NAME Nginx proxy manager container name (default: nginx-proxy-manager)"
      echo "  --pihole-container NAME Pi-hole container name (default: pihole-unbound)"
      echo "  --output FILE          Output file path (default: reports/service-inventory-TIMESTAMP.{md|json})"
      echo "  --filter REGEX         Extended regex for non-container service names to detect"
      echo "  --format FORMAT        Output format: markdown (default) or json"
      echo "  --diff [FILE]          Compare against previous report and show changes."
      echo "                         If FILE not specified, uses the most recent report."
      echo "  --help                 Show this help message"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Set default output file based on format
EXT="md"
[ "$FORMAT" = "json" ] && EXT="json"
[ -z "$OUTPUT_FILE" ] && OUTPUT_FILE="${OUTPUT_DIR}/service-inventory-$(date +%Y%m%d-%H%M%S).${EXT}"

# JSON data collector (parallel to markdown output)
JSON_CONTAINERS="[]"
JSON_SERVICES="[]"
JSON_NGINX="[]"
JSON_DNS="[]"

# Temporary files for data storage
NGINX_DATA=$(mktemp)
PIHOLE_DATA=$(mktemp)
JSON_TMP=$(mktemp)
trap "rm -f $NGINX_DATA $PIHOLE_DATA $JSON_TMP" EXIT

# Function to map truncated service names to full names (extend as needed)
map_service_name() {
  local name="$1"
  echo "$name"
}

# Initialize report
mkdir -p "$(dirname "$OUTPUT_FILE")"
cat > "$OUTPUT_FILE" << EOF
# Service Inventory Report

Generated: $(date '+%Y-%m-%d %H:%M:%S')

EOF

# Collect nginx proxy data
if [ "$COLLECT_NGINX" = true ]; then
  echo "Collecting nginx proxy configurations..."
  if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
    for conf in $(docker exec "$NGINX_CONTAINER" find /data/nginx/proxy_host -name "*.conf" -type f 2>/dev/null | sort -V); do
      name=$(docker exec "$NGINX_CONTAINER" grep "server_name" "$conf" 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';' | xargs)
      server=$(docker exec "$NGINX_CONTAINER" grep 'set $server' "$conf" 2>/dev/null | awk -F'"' '{print $2}')
      port=$(docker exec "$NGINX_CONTAINER" grep 'set $port' "$conf" 2>/dev/null | awk '{print $3}' | tr -d ';')
      scheme=$(docker exec "$NGINX_CONTAINER" grep 'set $forward_scheme' "$conf" 2>/dev/null | awk '{print $3}' | tr -d ';')
      ssl=$(docker exec "$NGINX_CONTAINER" grep -q "listen 443 ssl" "$conf" 2>/dev/null && echo "Yes" || echo "No")
      
      if [ -n "$name" ] && [ -n "$server" ] && [ -n "$port" ]; then
        target="${scheme}://${server}:${port}"
        echo "$name|$target|$ssl|$port" >> "$NGINX_DATA"
      fi
    done
  fi
fi

# Collect Pi-hole DNS data
if [ "$COLLECT_PIHOLE" = true ]; then
  echo "Collecting Pi-hole DNS entries..."
  if docker ps --format '{{.Names}}' | grep -q "^${PIHOLE_CONTAINER}$"; then
    docker exec "$PIHOLE_CONTAINER" cat /etc/pihole/custom.list 2>/dev/null | \
      grep -v "^#" | grep -v "^$" | \
      awk '{print $2"|"$1}' >> "$PIHOLE_DATA"
  fi
fi

# Function to find nginx config by port or name
find_nginx_config() {
  local search="$1"
  local search_type="$2"  # "port" or "name"
  local result=""
  local domains=""
  local targets=""
  local ssls=""
  
  while IFS='|' read -r domain target ssl port; do
    if [ "$search_type" = "port" ] && [ "$port" = "$search" ]; then
      [ -z "$domains" ] && domains="$domain" || domains="$domains, $domain"
      [ -z "$targets" ] && targets="$target" || targets="$targets, $target"
      [ -z "$ssls" ] && ssls="$ssl" || ssls="$ssls, $ssl"
    elif [ "$search_type" = "name" ] && [[ "$domain" == *"$search"* ]]; then
      [ -z "$domains" ] && domains="$domain" || domains="$domains, $domain"
      [ -z "$targets" ] && targets="$target" || targets="$targets, $target"
      [ -z "$ssls" ] && ssls="$ssl" || ssls="$ssls, $ssl"
    fi
  done < "$NGINX_DATA"
  
  [ -z "$domains" ] && echo "-|-|-" || echo "$domains|$targets|$ssls"
}

# Function to find DNS entries
find_dns_entries() {
  local name="$1"
  local result=""
  
  while IFS='|' read -r hostname ip; do
    if [[ "$hostname" == "$name" ]] || [[ "$hostname" == "${name}.local" ]] || [[ "$name" == *"$hostname"* ]]; then
      [ -z "$result" ] && result="$hostname → $ip" || result="$result<br>$hostname → $ip"
    fi
  done < "$PIHOLE_DATA"
  
  [ -z "$result" ] && echo "-" || echo "$result"
}

# Collect Docker containers
if [ "$COLLECT_CONTAINERS" = true ]; then
  echo "Collecting Docker container information..."
  
  cat >> "$OUTPUT_FILE" << 'EOF'
## Docker Containers

| Container Name | External Port | Internal Port | Domain/Hostname | Backend Target | SSL | DNS (Pi-hole) |
|----------------|---------------|---------------|-----------------|----------------|-----|---------------|
EOF

  docker ps --format '{{.Names}}\t{{.Ports}}' | while IFS=$'\t' read -r name ports; do
    # Parse ports - remove duplicates
    ext_ports=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | sort -u | tr '\n' ', ' | sed 's/,$//')
    int_ports=$(echo "$ports" | grep -oE '[0-9]+/tcp' | cut -d/ -f1 | sort -u | tr '\n' ', ' | sed 's/,$//')
    [ -z "$ext_ports" ] && ext_ports="-"
    [ -z "$int_ports" ] && int_ports="-"
    
    # Find nginx config by port first (only if container has ports)
    domain="-"
    target="-"
    ssl="-"
    
    if [ "$ext_ports" != "-" ]; then
      for port in $(echo "$ext_ports" | tr ',' ' '); do
        result=$(find_nginx_config "$port" "port")
        if [ "$result" != "-|-|-" ]; then
          IFS='|' read -r d t s <<< "$result"
          domain="$d"
          target="$t"
          ssl="$s"
          break
        fi
      done
    fi
    
    # Check by exact container name match only if not found by port
    # Use exact match to avoid false positives (e.g., DDNS service matching all wildcard domains)
    if [ "$domain" = "-" ]; then
      while IFS='|' read -r nginx_domain nginx_target nginx_ssl nginx_port; do
        # Check if domain contains container name as a subdomain (e.g., nginx.local for nginx-proxy-manager)
        if [[ "$nginx_domain" == "$name.local" ]] || [[ "$nginx_domain" == "${name/-/}.local" ]]; then
          domain="$nginx_domain"
          target="$nginx_target"
          ssl="$nginx_ssl"
          break
        fi
      done < "$NGINX_DATA"
    fi
    
    # Find DNS entries
    dns=$(find_dns_entries "$name")
    
    echo "| $name | $ext_ports | $int_ports | $domain | $target | $ssl | $dns |" >> "$OUTPUT_FILE"
  done
  
  echo "" >> "$OUTPUT_FILE"
fi

# Collect non-container services
if [ "$COLLECT_NON_CONTAINERS" = true ]; then
  echo "Collecting non-container service information..."
  
  cat >> "$OUTPUT_FILE" << 'EOF'
## Non-Container Services

| Service Name | Port(s) | Binding | Domain/Hostname | Backend Target | SSL | DNS (Pi-hole) |
|--------------|---------|---------|-----------------|----------------|-----|---------------|
EOF

  # Get listening ports excluding Docker/OrbStack
  # Group by service name and aggregate unique ports
  sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | \
    grep -v "docker\|OrbStack" | \
    awk 'NR>1 {
      # Reconstruct full command name
      cmd=$1
      # Handle escaped spaces in command names
      gsub(/\\x20/, " ", cmd)
      port=$9
      key=cmd
      if (!seen[key,port]) {
        if (ports[key]) {
          ports[key]=ports[key] "," port
        } else {
          ports[key]=port
          order[++count]=key
        }
        seen[key,port]=1
      }
    }
    END {
      for(i=1; i<=count; i++) {
        key=order[i]
        print key "|" ports[key]
      }
    }' | \
    grep -E "$SERVICE_FILTER" | \
    while IFS='|' read -r service all_ports; do
      # Map truncated service names to full names
      service=$(map_service_name "$service")
      
      # Remove duplicate ports
      all_ports=$(echo "$all_ports" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
      
      # Determine binding from first port
      first_port=$(echo "$all_ports" | cut -d',' -f1)
      binding="All interfaces"
      [[ "$first_port" == "127.0.0.1:"* ]] || [[ "$first_port" == "[::1]:"* ]] && binding="Localhost"
      
      # Extract port number from first port for nginx lookup
      port_num=$(echo "$first_port" | grep -oE '[0-9]+$')
      
      # Find nginx config
      result=$(find_nginx_config "$port_num" "port")
      IFS='|' read -r domain target ssl <<< "$result"
      
      # Find DNS entries
      service_lower=$(echo "$service" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      dns=$(find_dns_entries "$service_lower")
      
      # Format ports with spaces after commas
      all_ports=$(echo "$all_ports" | sed 's/,/, /g')
      
      echo "| $service | $all_ports | $binding | $domain | $target | $ssl | $dns |" >> "$OUTPUT_FILE"
    done
  
  echo "" >> "$OUTPUT_FILE"
fi

# Add summary section
cat >> "$OUTPUT_FILE" << 'EOF'

## Summary

**Configuration:**
EOF

echo "- Docker Containers: $COLLECT_CONTAINERS" >> "$OUTPUT_FILE"
echo "- Non-Container Services: $COLLECT_NON_CONTAINERS" >> "$OUTPUT_FILE"
echo "- Nginx Proxy Manager: $COLLECT_NGINX" >> "$OUTPUT_FILE"
echo "- Pi-hole DNS: $COLLECT_PIHOLE" >> "$OUTPUT_FILE"

if [ "$COLLECT_NGINX" = true ] && [ -f "$NGINX_DATA" ]; then
  nginx_count=$(wc -l < "$NGINX_DATA" | tr -d ' ')
  echo "- Total Nginx Proxy Configs: $nginx_count" >> "$OUTPUT_FILE"
fi

if [ "$COLLECT_PIHOLE" = true ] && [ -f "$PIHOLE_DATA" ]; then
  pihole_count=$(wc -l < "$PIHOLE_DATA" | tr -d ' ')
  echo "- Total Pi-hole DNS Entries: $pihole_count" >> "$OUTPUT_FILE"
fi

# --- JSON Output ---
if [ "$FORMAT" = "json" ]; then
  # Collect container data as JSON
  json_containers="[]"
  if [ "$COLLECT_CONTAINERS" = true ]; then
    json_containers=$(docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | while IFS=$'\t' read -r name image status ports; do
      ext=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
      int=$(echo "$ports" | grep -oE '[0-9]+/tcp' | cut -d/ -f1 | sort -u | tr '\n' ',' | sed 's/,$//')
      printf '{"name":"%s","image":"%s","status":"%s","external_ports":"%s","internal_ports":"%s"}\n' \
        "$name" "$image" "$status" "$ext" "$int"
    done | awk '{printf "%s%s", (NR>1?",":""), $0}')
    json_containers="[${json_containers}]"
  fi

  # Collect nginx data as JSON
  json_nginx="[]"
  if [ "$COLLECT_NGINX" = true ] && [ -s "$NGINX_DATA" ]; then
    json_nginx=$(while IFS='|' read -r domain target ssl port; do
      printf '{"domain":"%s","target":"%s","ssl":"%s","port":"%s"}\n' "$domain" "$target" "$ssl" "$port"
    done < "$NGINX_DATA" | awk '{printf "%s%s", (NR>1?",":""), $0}')
    json_nginx="[${json_nginx}]"
  fi

  # Collect DNS data as JSON
  json_dns="[]"
  if [ "$COLLECT_PIHOLE" = true ] && [ -s "$PIHOLE_DATA" ]; then
    json_dns=$(while IFS='|' read -r hostname ip; do
      printf '{"hostname":"%s","ip":"%s"}\n' "$hostname" "$ip"
    done < "$PIHOLE_DATA" | awk '{printf "%s%s", (NR>1?",":""), $0}')
    json_dns="[${json_dns}]"
  fi

  # Write JSON report
  cat > "$OUTPUT_FILE" << JSONEOF
{
  "generated": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "containers": ${json_containers},
  "proxy_hosts": ${json_nginx},
  "dns_entries": ${json_dns}
}
JSONEOF
fi

# --- Diff Mode ---
if [ "$DIFF_MODE" = true ]; then
  # Find the previous report to diff against
  if [ -z "$DIFF_AGAINST" ]; then
    DIFF_AGAINST=$(find "$OUTPUT_DIR" -name "service-inventory-*.$EXT" -not -name "$(basename "$OUTPUT_FILE")" | sort | tail -1)
  fi

  if [ -z "$DIFF_AGAINST" ] || [ ! -f "$DIFF_AGAINST" ]; then
    echo ""
    echo "⚠ No previous report found for diff. This is the first report."
  else
    echo ""
    echo "━━━ Changes since $(basename "$DIFF_AGAINST") ━━━"

    if [ "$FORMAT" = "json" ]; then
      # JSON diff: compare container names
      prev_containers=$(grep -oE '"name":"[^"]+"' "$DIFF_AGAINST" | sort)
      curr_containers=$(grep -oE '"name":"[^"]+"' "$OUTPUT_FILE" | sort)
      added=$(comm -13 <(echo "$prev_containers") <(echo "$curr_containers") | sed 's/"name":"//;s/"//')
      removed=$(comm -23 <(echo "$prev_containers") <(echo "$curr_containers") | sed 's/"name":"//;s/"//')
    else
      # Markdown diff: compare container name column
      prev_containers=$(grep -E '^\|[^|]+\|' "$DIFF_AGAINST" | grep -v '^\| Container\|^\|---' | awk -F'|' '{print $2}' | xargs -I{} echo "{}" | sort)
      curr_containers=$(grep -E '^\|[^|]+\|' "$OUTPUT_FILE" | grep -v '^\| Container\|^\|---' | awk -F'|' '{print $2}' | xargs -I{} echo "{}" | sort)
      added=$(comm -13 <(echo "$prev_containers") <(echo "$curr_containers"))
      removed=$(comm -23 <(echo "$prev_containers") <(echo "$curr_containers"))
    fi

    if [ -n "$added" ]; then
      echo ""
      echo "  ✚ Added:"
      echo "$added" | while read -r svc; do
        [ -n "$svc" ] && echo "    + $svc"
      done
    fi

    if [ -n "$removed" ]; then
      echo ""
      echo "  ✖ Removed:"
      echo "$removed" | while read -r svc; do
        [ -n "$svc" ] && echo "    - $svc"
      done
    fi

    if [ -z "$added" ] && [ -z "$removed" ]; then
      echo "  No changes detected."
    fi
    echo ""
  fi
fi

echo ""
echo "✓ Report generated successfully: $OUTPUT_FILE"