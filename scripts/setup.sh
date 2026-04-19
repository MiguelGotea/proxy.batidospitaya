#!/bin/bash
# =============================================================================
# setup.sh — Configura Nginx reverse proxy para proxy.batidospitaya.com
# Idempotente: se puede correr múltiples veces sin romper nada.
# =============================================================================
set -euo pipefail

# ─── Variables ───────────────────────────────────────────────────────────────
DOMINIO="proxy.batidospitaya.com"
EMAIL="miguelgotea.1@gmail.com"
NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMINIO"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMINIO"
REPO_NGINX="$(dirname "$0")/../nginx/$DOMINIO.conf"

# ─── Colores para output ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Setup: $DOMINIO${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ─── Paso a) Copiar configuración Nginx ──────────────────────────────────────
echo "[1/7] Copiando configuración Nginx..."
if [ ! -f "$REPO_NGINX" ]; then
    echo -e "${RED}❌ No se encontró el archivo: $REPO_NGINX${NC}"
    exit 1
fi
cp "$REPO_NGINX" "$NGINX_AVAILABLE"
echo "      ✓ Copiado a $NGINX_AVAILABLE"

# ─── Paso b) Crear symlink en sites-enabled ──────────────────────────────────
echo "[2/7] Verificando symlink en sites-enabled..."
if [ ! -L "$NGINX_ENABLED" ]; then
    ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
    echo "      ✓ Symlink creado"
else
    echo "      ✓ Symlink ya existe — sin cambios"
fi

# ─── Paso c) Validar configuración Nginx ─────────────────────────────────────
echo "[3/7] Validando configuración Nginx..."
if ! nginx -t 2>&1; then
    echo -e "${RED}❌ nginx -t falló. Abortando sin modificar el servidor.${NC}"
    echo "    Revisa la configuración en: $NGINX_AVAILABLE"
    exit 1
fi
echo "      ✓ Configuración válida"

# ─── Paso d) Recargar Nginx ───────────────────────────────────────────────────
echo "[4/7] Recargando Nginx..."
systemctl reload nginx
echo "      ✓ Nginx recargado"

# ─── Paso e) Instalar certbot si no existe ───────────────────────────────────
echo "[5/7] Verificando certbot..."
if ! command -v certbot &>/dev/null; then
    echo "      certbot no encontrado — instalando..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx
    echo "      ✓ certbot instalado"
else
    echo "      ✓ certbot ya instalado"
fi

# ─── Paso f) Obtener o renovar certificado SSL ───────────────────────────────
echo "[6/7] Gestionando certificado SSL..."
if [ ! -d "/etc/letsencrypt/live/$DOMINIO" ]; then
    echo "      Obteniendo certificado nuevo para $DOMINIO..."
    certbot --nginx -d "$DOMINIO" \
        --non-interactive \
        --agree-tos \
        -m "$EMAIL"
    echo "      ✓ Certificado obtenido"
else
    echo "      Certificado ya existe — renovando si es necesario..."
    certbot renew --quiet
    echo "      ✓ Renovación completada"
fi

# ─── Paso g) Recargar Nginx con SSL activo ───────────────────────────────────
echo "      Recargando Nginx con SSL activo..."
systemctl reload nginx
echo "      ✓ Nginx recargado con SSL"

# ─── Paso h) Test de conectividad + rollback automático ──────────────────────
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
