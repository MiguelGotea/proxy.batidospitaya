#!/bin/bash
# =============================================================================
# setup.sh — Configura Nginx reverse proxy para proxy.batidospitaya.com
# Idempotente: se puede correr múltiples veces sin romper nada.
#
# Fase 1 (primera vez): HTTP temporal → certbot obtiene cert → SSL completo
# Fase 2 (siguientes): SSL completo directamente → certbot renew
# =============================================================================
set -euo pipefail

# ─── Variables ───────────────────────────────────────────────────────────────
DOMINIO="proxy.batidospitaya.com"
EMAIL="miguelgotea.1@gmail.com"
NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMINIO"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMINIO"
REPO_NGINX="$(cd "$(dirname "$0")/.." && pwd)/nginx/$DOMINIO.conf"
CERT_DIR="/etc/letsencrypt/live/$DOMINIO"

# ─── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Setup: $DOMINIO${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ─── Paso 0) Nginx ────────────────────────────────────────────────────────────
echo "[0/7] Verificando Nginx..."
if ! command -v nginx &>/dev/null; then
    echo "      nginx no encontrado — instalando..."
    apt-get update -qq
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "      ✓ nginx instalado y arrancado"
else
    echo "      ✓ nginx ya instalado ($(nginx -v 2>&1 | tr -d '\n'))"
fi
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# ─── Paso 0.5) Abrir puertos en el firewall ──────────────────────────────────
echo "[0.5/7] Abriendo puertos 80 y 443 en UFW..."
if command -v ufw &>/dev/null; then
    ufw allow 80/tcp  >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    echo "      ✓ Puertos 80 y 443 abiertos en UFW"
else
    echo "      UFW no encontrado — asumiendo que los puertos ya están abiertos"
fi

# ─── Paso 1) Configuración Nginx según fase ───────────────────────────────────
echo "[1/7] Copiando configuración Nginx..."

if [ ! -f "$REPO_NGINX" ]; then
    echo -e "${RED}❌ No se encontró: $REPO_NGINX${NC}"
    exit 1
fi

if [ ! -d "$CERT_DIR" ]; then
    # ── FASE 1: aún no hay certificado ──────────────────────────────────────
    # Desplegamos config HTTP-only temporaria para que nginx -t pase sin SSL.
    # Certbot necesita que nginx esté activo en el puerto 80 para el challenge.
    echo "      [FASE 1] Sin certificado aún — usando config HTTP temporal..."
    cat > "$NGINX_AVAILABLE" << HTTPEOF
server {
    listen 80;
    server_name $DOMINIO;

    # Permite que certbot valide el dominio via HTTP
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Proxy funcional en HTTP mientras no hay cert
    location / {
        proxy_pass https://api.batidospitaya.com;
        proxy_set_header Host api.batidospitaya.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_ssl_server_name on;
        proxy_ssl_verify off;
        proxy_connect_timeout 30s;
        proxy_read_timeout    120s;
        proxy_send_timeout    120s;
    }
}
HTTPEOF
    echo "      ✓ Config HTTP temporal escrita"
else
    # ── FASE 2: certificado ya existe ────────────────────────────────────────
    echo "      [FASE 2] Certificado existe — usando config SSL completa..."
    cp "$REPO_NGINX" "$NGINX_AVAILABLE"
    echo "      ✓ Copiado a $NGINX_AVAILABLE"
fi

# ─── Paso 2) Symlink ──────────────────────────────────────────────────────────
echo "[2/7] Verificando symlink en sites-enabled..."
if [ ! -L "$NGINX_ENABLED" ]; then
    ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
    echo "      ✓ Symlink creado"
else
    echo "      ✓ Symlink ya existe"
fi

# ─── Paso 3) Validar config ───────────────────────────────────────────────────
echo "[3/7] Validando configuración Nginx..."
if ! nginx -t 2>&1; then
    echo -e "${RED}❌ nginx -t falló. Abortando.${NC}"
    exit 1
fi
echo "      ✓ Configuración válida"

# ─── Paso 4) Recargar Nginx ───────────────────────────────────────────────────
echo "[4/7] Recargando Nginx..."
systemctl reload nginx
echo "      ✓ Nginx recargado"

# ─── Paso 5) Certbot ──────────────────────────────────────────────────────────
echo "[5/7] Verificando certbot..."
if ! command -v certbot &>/dev/null; then
    echo "      certbot no encontrado — instalando..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx
    echo "      ✓ certbot instalado"
else
    echo "      ✓ certbot ya instalado"
fi

# ─── Paso 6) SSL ──────────────────────────────────────────────────────────────
echo "[6/7] Gestionando certificado SSL..."
if [ ! -d "$CERT_DIR" ]; then
    echo "      Obteniendo certificado nuevo para $DOMINIO..."
    certbot certonly --nginx \
        -d "$DOMINIO" \
        --non-interactive \
        --agree-tos \
        -m "$EMAIL"
    echo "      ✓ Certificado obtenido"

    # Ahora que el cert existe, desplegar la config SSL completa del repo
    echo "      Activando config SSL completa..."
    cp "$REPO_NGINX" "$NGINX_AVAILABLE"

    # Descomentar las líneas de certificado en la config
    sed -i "s|# ssl_certificate |ssl_certificate |g" "$NGINX_AVAILABLE"
    sed -i "s|# ssl_certificate_key |ssl_certificate_key |g" "$NGINX_AVAILABLE"

    # Validar y recargar con SSL
    if ! nginx -t 2>&1; then
        echo -e "${RED}❌ nginx -t falló con config SSL. Revisar logs.${NC}"
        exit 1
    fi
    systemctl reload nginx
    echo "      ✓ Config SSL activa"
else
    echo "      Certificado ya existe — renovando si es necesario..."
    certbot renew --quiet
    echo "      ✓ Renovación completada"
fi

# ─── Paso 7) Recargar Nginx final ─────────────────────────────────────────────
echo "      Recargando Nginx..."
systemctl reload nginx
echo "      ✓ Nginx recargado"

# ─── Paso 8) Test de conectividad + rollback ──────────────────────────────────
echo "[7/7] Verificando proxy..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 15 \
    "https://$DOMINIO/api/ping.php" 2>/dev/null || echo "000")

if [ "$RESPONSE" = "200" ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ Proxy funcionando — HTTP $RESPONSE${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ❌ Falló (HTTP $RESPONSE) — ejecutando rollback...${NC}"
    rm -f "$NGINX_ENABLED"
    systemctl reload nginx
    echo "  Rollback ejecutado: symlink eliminado, Nginx recargado"
    echo "  Ver logs:"
    echo "    tail -f /var/log/nginx/proxy-batidospitaya-error.log"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
fi
