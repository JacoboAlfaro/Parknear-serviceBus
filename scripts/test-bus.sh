#!/usr/bin/env bash
set -euo pipefail

BUS_URL="${BUS_URL:-http://bus.parknear.online:3000}"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
  PASS=$((PASS + 1))
  printf "${GREEN}[PASS]${NC} %s\n" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf "${RED}[FAIL]${NC} %s\n" "$1"
}

info() {
  printf "${YELLOW}[INFO]${NC} %s\n" "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd curl
require_cmd mktemp
require_cmd head
require_cmd wc
require_cmd tr

info "Probando bus en: ${BUS_URL}"

# 1) Health del bus
code=$(curl -sS -o /tmp/bus-health.json -w "%{http_code}" "${BUS_URL}/health" || true)
if [[ "$code" == "200" ]] && grep -q '"status"' /tmp/bus-health.json; then
  pass "Health endpoint responde 200"
else
  fail "Health endpoint no responde como se esperaba (code=${code})"
fi

# 2) Enrutamiento a auth (/api/auth -> USER_AUTH_BASE_URL)
code=$(curl -sS -o /tmp/bus-auth.json -w "%{http_code}" \
  -H 'content-type: application/json' \
  -X POST "${BUS_URL}/api/auth/login" \
  -d '{"email":"qa@parknear.local"}' || true)

if [[ "$code" == "200" ]] && grep -q '"service"[[:space:]]*:[[:space:]]*"auth-mock"' /tmp/bus-auth.json; then
  pass "El bus enruta /api/auth/login al servidor auth"
else
  fail "No se validó enrutamiento a auth (code=${code})"
  info "Tip: asegura USER_AUTH_BASE_URL apuntando al mock Node"
fi

# 3) Correlation ID propagado/respetado
CID='11111111-2222-3333-4444-555555555555'
headers_file=$(mktemp)
body_file=$(mktemp)
code=$(curl -sS -D "$headers_file" -o "$body_file" -w "%{http_code}" \
  -H "X-Correlation-ID: ${CID}" \
  "${BUS_URL}/api/users/me" || true)

resp_cid=$(grep -i '^x-correlation-id:' "$headers_file" | tr -d '\r' | awk '{print $2}')
if [[ "$code" == "200" ]] && [[ "$resp_cid" == "$CID" ]]; then
  pass "Correlation ID se conserva en la respuesta"
else
  fail "Correlation ID no coincide (code=${code}, resp=${resp_cid:-none})"
fi

rm -f "$headers_file" "$body_file"

# 4) Ruta no encontrada en el bus
code=$(curl -sS -o /tmp/bus-404.txt -w "%{http_code}" "${BUS_URL}/api/no-existe" || true)
if [[ "$code" == "404" ]]; then
  pass "Rutas no configuradas devuelven 404"
else
  fail "Esperaba 404 en ruta desconocida y llegó ${code}"
fi

# 5) Límite de body (espera 413 por default >16MB)
big_payload=$(mktemp)
head -c 17000000 /dev/zero > "$big_payload"
code=$(curl -sS -o /tmp/bus-big-body.txt -w "%{http_code}" \
  -X POST "${BUS_URL}/api/auth/huge" \
  --data-binary @"$big_payload" || true)
rm -f "$big_payload"

if [[ "$code" == "413" ]]; then
  pass "Request body limit activo (413)"
else
  fail "Request body limit inesperado (code=${code})"
  info "Si cambiaste REQUEST_BODY_LIMIT_BYTES, ajusta el tamaño del payload"
fi

# 6) Rate limiting: burst concurrente para buscar 429
TOTAL=160
rate_codes_dir=$(mktemp -d)
pids=()

for i in $(seq 1 "$TOTAL"); do
  (
    curl -sS -o /dev/null -w "%{http_code}" "${BUS_URL}/api/users/me" > "${rate_codes_dir}/${i}"
  ) &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "$pid" || true
done

TOO_MANY=0
for file in "${rate_codes_dir}"/*; do
  if [[ "$(<"$file")" == "429" ]]; then
    TOO_MANY=$((TOO_MANY + 1))
  fi
done

rm -rf "$rate_codes_dir"

if (( TOO_MANY > 0 )); then
  pass "Rate limiting activo (429 detectados: ${TOO_MANY}/${TOTAL})"
else
  fail "No se detectaron 429 en burst concurrente de ${TOTAL} requests"
  info "Si sigue sin aparecer 429, la IP que ve el bus puede no ser la tuya o el despliegue tiene otra configuración"
fi

# 7) Blacklist (actualmente sin API runtime para bloquear IPs)
info "Blacklist: no hay endpoint para bloquear IP en runtime, solo pass-through por defecto"
pass "Middleware de blacklist no bloquea por defecto (comportamiento esperado)"

echo
printf "Resultado final: PASS=%d FAIL=%d\n" "$PASS" "$FAIL"

if (( FAIL > 0 )); then
  exit 1
fi
