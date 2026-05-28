#!/usr/bin/env bash
#
# proxy-manager.sh — map running containers to NPM proxy hosts,
# check certificate expiry, offer renewal or new host creation.
#
# Usage:
#   proxy-manager.sh              Interactive mode.
#   proxy-manager.sh --check      Report only, no changes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.env not found. Copy config.env.example to config.env and fill in values." >&2
  exit 1
fi
source "$CONFIG_FILE"

MODE="interactive"
[ "${1:-}" = "--check" ] && MODE="check"

# --- NPM API Helpers ---
npm_token=""

npm_login() {
  npm_token=$(curl -s "${NPM_API_URL}/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"identity\":\"${NPM_EMAIL}\",\"secret\":\"${NPM_PASSWORD}\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
  [ -z "$npm_token" ] && { echo "ERROR: Failed to authenticate with NPM API" >&2; exit 1; }
}

npm_get() {
  curl -s "${NPM_API_URL}${1}" -H "Authorization: Bearer ${npm_token}"
}

npm_post() {
  curl -s "${NPM_API_URL}${1}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${npm_token}" \
    -d "$2"
}

# --- Pi-hole API Helpers ---
pihole_sid=""

pihole_login() {
  pihole_sid=$(curl -s "${PIHOLE_API_URL}/api/auth" -X POST \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${PIHOLE_PASSWORD}\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['session']['sid'])" 2>/dev/null)
  [ -z "$pihole_sid" ] && { echo "WARNING: Failed to authenticate with Pi-hole API" >&2; }
}

pihole_add_dns() {
  local ip="$1" hostname="$2"
  local encoded="${ip}%20${hostname}"
  curl -s "${PIHOLE_API_URL}/api/config/dns/hosts/${encoded}" \
    -X PUT -H "sid: ${pihole_sid}" > /dev/null 2>&1
}

# --- Main Logic ---
npm_login
pihole_login

# Get all proxy hosts and certificates from NPM
PROXY_HOSTS=$(npm_get "/api/nginx/proxy-hosts")
CERTIFICATES=$(npm_get "/api/nginx/certificates")

# Get running containers with exposed ports
CONTAINERS=$(docker ps --format '{{.Names}}\t{{.Ports}}\t{{.ID}}' | while IFS=$'\t' read -r name ports id; do
  ext_port=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+' | head -1 | cut -d: -f2)
  [ -z "$ext_port" ] && continue
  project=$(docker inspect "$id" --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null)
  echo "${name}|${ext_port}|${project}"
done)

echo "━━━ Proxy Manager ━━━"
echo

matched=0
unmatched=0
expiring=0

while IFS='|' read -r container port project; do
  [ -z "$container" ] && continue

  host_info=$(echo "$PROXY_HOSTS" | python3 -c "
import json,sys
hosts = json.load(sys.stdin)
for h in hosts:
    domains = ' '.join(h.get('domain_names',[]))
    if h.get('forward_port') == ${port} or '${project}' in domains or '${container}' in domains:
        cert_id = h.get('certificate_id', 0)
        print(f\"{h['id']}|{domains}|{cert_id}\")
        break
" 2>/dev/null)

  if [ -n "$host_info" ]; then
    matched=$((matched + 1))
    IFS='|' read -r host_id domains cert_id <<< "$host_info"

    if [ "$cert_id" != "0" ] && [ -n "$cert_id" ]; then
      cert_expiry=$(echo "$CERTIFICATES" | python3 -c "
import json,sys,datetime
certs = json.load(sys.stdin)
for c in certs:
    if c['id'] == ${cert_id}:
        exp = c.get('expires_on','')
        if exp:
            d = datetime.datetime.strptime(exp, '%Y-%m-%d %H:%M:%S')
            days = (d - datetime.datetime.now()).days
            print(f'{days}|{exp}')
        break
" 2>/dev/null)

      if [ -n "$cert_expiry" ]; then
        IFS='|' read -r days_left exp_date <<< "$cert_expiry"
        if [ "$days_left" -le "$CERT_WARN_DAYS" ]; then
          expiring=$((expiring + 1))
          printf "  ⚠ %-40s → %-40s cert expires in %s days (%s)\n" "$container" "$domains" "$days_left" "$exp_date"
          if [ "$MODE" = "interactive" ]; then
            printf "    Renew certificate #%s? [y/N] " "$cert_id"
            read -r ans < /dev/tty
            if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
              result=$(npm_post "/api/nginx/certificates/${cert_id}/renew" "{}")
              if echo "$result" | grep -q "expires_on"; then
                new_exp=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('expires_on',''))" 2>/dev/null)
                echo "    ✓ Renewed. New expiry: $new_exp"
              else
                echo "    ✗ Renewal failed. Check NPM logs."
              fi
            fi
          fi
        else
          printf "  ✓ %-40s → %-40s cert OK (%s days)\n" "$container" "$domains" "$days_left"
        fi
      else
        printf "  ✓ %-40s → %-40s (no cert)\n" "$container" "$domains"
      fi
    else
      printf "  ✓ %-40s → %-40s (no cert)\n" "$container" "$domains"
    fi
  else
    unmatched=$((unmatched + 1))
    printf "  ✚ %-40s :%-5s no proxy host found\n" "$container" "$port"

    if [ "$MODE" = "interactive" ]; then
      printf "    Create proxy host? (e)xternal / (i)nternal / (s)kip [s]: "
      read -r choice < /dev/tty

      case "$choice" in
        e|E)
          # --- External host: HTTPS + Let's Encrypt ---
          default_domain="${project}.${EXTERNAL_DOMAIN_SUFFIX}"
          printf "    Domain [%s]: " "$default_domain"
          read -r domain < /dev/tty
          [ -z "$domain" ] && domain="$default_domain"

          printf "    Forward host [%s]: " "$LOCAL_DNS_IP"
          read -r fwd_host < /dev/tty
          [ -z "$fwd_host" ] && fwd_host="$LOCAL_DNS_IP"

          echo "    Creating SSL certificate for ${domain}..."
          cert_result=$(npm_post "/api/nginx/certificates" "{
            \"nice_name\": \"${domain}\",
            \"domain_names\": [\"${domain}\"],
            \"meta\": {
              \"dns_challenge\": true,
              \"dns_provider\": \"${DNS_PROVIDER}\",
              \"dns_provider_credentials\": \"${DNS_CREDENTIALS}\"
            },
            \"provider\": \"letsencrypt\"
          }")

          new_cert_id=$(echo "$cert_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
          if [ -z "$new_cert_id" ]; then
            echo "    ✗ Certificate creation failed."
            continue
          fi
          echo "    ✓ Certificate #${new_cert_id} created."

          echo "    Creating proxy host..."
          host_result=$(npm_post "/api/nginx/proxy-hosts" "{
            \"domain_names\": [\"${domain}\"],
            \"forward_scheme\": \"${DEFAULT_SCHEME}\",
            \"forward_host\": \"${fwd_host}\",
            \"forward_port\": ${port},
            \"access_list_id\": 0,
            \"certificate_id\": ${new_cert_id},
            \"ssl_forced\": ${SSL_FORCED},
            \"http2_support\": ${HTTP2_SUPPORT},
            \"block_exploits\": ${BLOCK_EXPLOITS},
            \"allow_websocket_upgrade\": ${ALLOW_WEBSOCKET},
            \"meta\": {\"letsencrypt_agree\": false, \"dns_challenge\": false},
            \"locations\": []
          }")

          new_host_id=$(echo "$host_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
          if [ -n "$new_host_id" ]; then
            echo "    ✓ Proxy host #${new_host_id}: https://${domain} → ${DEFAULT_SCHEME}://${fwd_host}:${port}"
          else
            echo "    ✗ Proxy host creation failed."
          fi
          ;;

        i|I)
          # --- Internal host: .local domain, no SSL, + Pi-hole DNS ---
          default_domain="${project}.${INTERNAL_DOMAIN_SUFFIX:-lan}"
          printf "    Domain [%s]: " "$default_domain"
          read -r domain < /dev/tty
          [ -z "$domain" ] && domain="$default_domain"

          printf "    Forward host [%s]: " "$LOCAL_DNS_IP"
          read -r fwd_host < /dev/tty
          [ -z "$fwd_host" ] && fwd_host="$LOCAL_DNS_IP"

          echo "    Creating proxy host (no SSL)..."
          host_result=$(npm_post "/api/nginx/proxy-hosts" "{
            \"domain_names\": [\"${domain}\"],
            \"forward_scheme\": \"${DEFAULT_SCHEME}\",
            \"forward_host\": \"${fwd_host}\",
            \"forward_port\": ${port},
            \"access_list_id\": 0,
            \"certificate_id\": 0,
            \"ssl_forced\": false,
            \"http2_support\": false,
            \"block_exploits\": ${BLOCK_EXPLOITS},
            \"allow_websocket_upgrade\": ${ALLOW_WEBSOCKET},
            \"meta\": {\"letsencrypt_agree\": false, \"dns_challenge\": false},
            \"locations\": []
          }")

          new_host_id=$(echo "$host_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
          if [ -n "$new_host_id" ]; then
            echo "    ✓ Proxy host #${new_host_id}: http://${domain} → ${DEFAULT_SCHEME}://${fwd_host}:${port}"
          else
            echo "    ✗ Proxy host creation failed."
            continue
          fi

          # Add DNS record to Pi-hole
          if [ -n "$pihole_sid" ]; then
            echo "    Adding ${domain} → ${LOCAL_DNS_IP} to Pi-hole..."
            pihole_add_dns "$LOCAL_DNS_IP" "$domain"
            echo "    ✓ DNS record added."
          else
            echo "    ⚠ Pi-hole not available. Add manually: ${domain} → ${LOCAL_DNS_IP}"
          fi
          ;;

        *)
          echo "    Skipped."
          ;;
      esac
    fi
  fi
done <<< "$CONTAINERS"

echo
echo "━━━ Summary ━━━"
echo "  Matched:    $matched"
echo "  Unmatched:  $unmatched"
echo "  Expiring:   $expiring (within ${CERT_WARN_DAYS} days)"
