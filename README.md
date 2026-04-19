# 🌐 proxy.batidospitaya.com — Nginx Reverse Proxy

Nginx reverse proxy en el VPS de DigitalOcean que recibe el tráfico de las
sucursales (Microsoft Access con IPs dinámicas) y lo reenvía a
`api.batidospitaya.com` con IP fija, eliminando los bloqueos de Cloudflare.

---

## ¿Por qué existe este proyecto?

Las sucursales consumen la API del ERP (`api.batidospitaya.com`) usando
**Microsoft Access** (`MSXML2.ServerXMLHTTP.6.0`). El problema:

- Las sucursales tienen **IPs dinámicas** que cambian constantemente.
- `api.batidospitaya.com` está detrás de **Cloudflare** (gestionado por Hostinger).
- Cloudflare bloquea IPs desconocidas con **JS challenges** que Access no puede resolver.

**Solución:** Un proxy propio en el VPS con IP fija (`198.211.97.243`) que actúa
como intermediario. Las sucursales hablan con el proxy, y el proxy habla con la API.
Cloudflare solo ve la IP fija del VPS, que está en whitelist.

---

## 🏗️ Arquitectura

```
Access (sucursales, IP dinámica)
  │
  │  HTTPS → proxy.batidospitaya.com
  ▼
VPS DigitalOcean — 198.211.97.243 (IP fija)
  Nginx reverse proxy
  │
  │  HTTPS → api.batidospitaya.com
  ▼
Hostinger + Cloudflare
  api.batidospitaya.com (ERP)
```

---

## 🗂️ Estructura del Proyecto

```
proxy.batidospitaya.com/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD via GitHub Actions
├── .scripts/
│   └── gitpush.ps1             # Deploy rápido desde Windows
├── nginx/
│   └── proxy.batidospitaya.com.conf   # Configuración Nginx
├── scripts/
│   └── setup.sh                # Instalación idempotente en el VPS
├── INSTRUCCIONES-PREVIAS.md    # Pasos manuales antes del primer deploy
└── README.md                   # Este archivo
```

**Ruta en el VPS:** `/root/proxy-batidospitaya`

> Se usó `/root/proxy-batidospitaya` siguiendo la convención del VPS
> (`/root/<nombre-proyecto>`). Al ser solo configuración Nginx (no app Node/Python),
> no necesita entorno virtual ni PM2 — solo el repositorio y el script setup.sh.

---

## 🚀 Deploy

### Deploy automático (flujo normal)

Desde Windows, en la carpeta del proyecto:

```powershell
.\.scripts\gitpush.ps1
```

Esto hace commit + push → GitHub Actions conecta al VPS por SSH → ejecuta `setup.sh`.

```
[Tu PC] → gitpush.ps1 → GitHub → Actions → VPS (SSH) → setup.sh
```

### ¿Qué hace setup.sh?

1. Copia `nginx/proxy.batidospitaya.com.conf` a `/etc/nginx/sites-available/`
2. Crea symlink en `sites-enabled/` (solo si no existe)
3. Valida la config con `nginx -t`
4. Recarga Nginx
5. Instala certbot si no está
6. Obtiene/renueva certificado SSL via Let's Encrypt
7. Recarga Nginx con SSL
8. Verifica que el proxy responde — rollback automático si falla

---

## ✅ Verificar que el proxy funciona

Desde cualquier PC con curl:

```bash
curl -v https://proxy.batidospitaya.com/api/ping.php
```

Respuesta esperada: **HTTP 200**

---

## 📋 Ver logs en el VPS

```bash
# Tráfico en tiempo real (sucursales conectándose)
tail -f /var/log/nginx/proxy-batidospitaya-access.log

# Errores del proxy
tail -f /var/log/nginx/proxy-batidospitaya-error.log
```

---

## 🔧 Diagnóstico y Rollback Manual

### Si el proxy no responde:

```bash
ssh root@198.211.97.243

# 1. Verificar que Nginx está corriendo
systemctl status nginx

# 2. Revisar config
nginx -t

# 3. Ver errores recientes
tail -50 /var/log/nginx/proxy-batidospitaya-error.log

# 4. Verificar DNS
nslookup proxy.batidospitaya.com

# 5. Probar conexión directa a la API (sin proxy)
curl -v https://api.batidospitaya.com/api/ping.php
```

### Rollback manual:

```bash
# Desactivar el vhost sin borrar la config
rm /etc/nginx/sites-enabled/proxy.batidospitaya.com
systemctl reload nginx
```

### Re-activar después del rollback:

```bash
ln -s /etc/nginx/sites-available/proxy.batidospitaya.com \
      /etc/nginx/sites-enabled/proxy.batidospitaya.com
systemctl reload nginx
```

---

## 🛡️ WireGuard — Análisis de configuración

Se leyó la configuración actual del VPS en `/etc/wireguard/wg0.conf`.

### Hallazgos:

El VPS actúa como **servidor WireGuard** (no cliente). Los clientes conectados
son las sucursales (`pitaya`, `villafontana`, `leon`, `matagalpa`, `esteli`,
`altamira`, `granada`, `lascolinas`, `masaya`, `natura`, `lasbrisas`, `rivas`,
`unica`, `ticuantepe`, `calli`, `contabilidad`, `sistemas`, `procesamiento`).

**Puntos clave analizados:**

| Aspecto | Resultado |
|---------|-----------|
| `AllowedIPs` de cada peer | Solo IPs privadas: `10.66.66.x/32` |
| ¿`AllowedIPs = 0.0.0.0/0`? | ❌ **No existe** — el VPS NO es cliente de nadie |
| PostUp/PostDown | Solo MASQUERADE para que los peers salgan por `eth0` |
| Tráfico saliente del VPS | Sale por `eth0` normalmente |

### Conclusión: ✅ Sin problema de ruteo

El VPS es el servidor WireGuard — su tráfico saliente (incluyendo `proxy_pass`
hacia `api.batidospitaya.com`) **siempre sale por `eth0`**. No hay reglas que
desvíen el tráfico del VPS por un túnel externo.

**No se requiere ninguna corrección adicional en `setup.sh`** relacionada con
WireGuard.

> Si en el futuro se agrega el VPS como cliente de otro túnel (con
> `AllowedIPs = 0.0.0.0/0`), se deberá agregar una ruta de política para que
> el tráfico a `api.batidospitaya.com` salga por `eth0`:
> ```bash
> ip rule add to $(dig +short api.batidospitaya.com | tail -1) table main priority 100
> ```

---

## 🔐 Seguridad

- No hay credenciales en el repositorio
- SSL/TLS gestionado por Let's Encrypt (certbot)
- `proxy_ssl_verify off` es intencional: confía en Cloudflare como destino final
- El proxy solo acepta tráfico HTTPS (HTTP redirige a HTTPS)