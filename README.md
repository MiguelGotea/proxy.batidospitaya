# 🌐 proxy.batidospitaya.com — Nginx Reverse Proxy

Nginx reverse proxy en el VPS de DigitalOcean que recibe el tráfico de las
sucursales (Microsoft Access con IPs dinámicas) y lo reenvía a
`api.batidospitaya.com` con IP fija, eliminando los bloqueos de Cloudflare.

> ✅ **Estado:** Operativo desde 2026-04-19
> ```json
> {"status":"success","message":"pong","timestamp":1776636336}
> ```

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
  Nginx 1.24.0 + Let's Encrypt SSL
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

> Sigue la convención `/root/<nombre-proyecto>` del VPS. Al ser solo
> configuración Nginx (sin Node/Python/PM2), no necesita entorno virtual
> ni ecosystem.config.js.

---

## 🚀 Deploy

### Deploy automático (flujo normal)

Desde Windows, dentro de la carpeta `proxy.batidospitaya.com/`:

```powershell
.\.scripts\gitpush.ps1
```

Esto hace commit + push → GitHub Actions conecta al VPS por SSH → ejecuta `setup.sh`.

```
[Tu PC] → gitpush.ps1 → GitHub → Actions → VPS (SSH) → setup.sh
```

### ¿Qué hace `setup.sh`?

El script es **idempotente** (se puede correr N veces sin romper nada) y
opera en dos fases según si el certificado SSL ya existe o no:

| Paso | Descripción |
|------|-------------|
| [0/7] | Instala Nginx si no está instalado (primera vez lo instala; después solo confirma) |
| [0.5/7] | Abre puertos 80 y 443 en UFW (idempotente, no duplica reglas) |
| [1/7] | **FASE 1** (sin cert): escribe config HTTP temporal para que `nginx -t` pase sin SSL<br>**FASE 2** (con cert): copia directamente la config SSL completa del repo |
| [2/7] | Crea symlink `sites-enabled/` si no existe |
| [3/7] | `nginx -t` — valida la config; abort si falla |
| [4/7] | `systemctl reload nginx` |
| [5/7] | Instala certbot si no está |
| [6/7] | **FASE 1**: `certbot certonly --nginx` → obtiene cert → activa config SSL completa<br>**FASE 2**: `certbot renew --quiet` |
| [7/7] | `curl` al endpoint de ping → rollback automático si no responde HTTP 200 |

### ¿Por qué dos fases?

Nginx valida **toda** la config al recargar. El bloque `listen 443 ssl` requiere
que el certificado exista físicamente en disco. Como certbot aún no corrió en la
primera instalación, `nginx -t` falla. La solución: config HTTP temporal → certbot
obtiene cert → config SSL completa.

### Deploy limpio en el VPS (git reset)

El `deploy.yml` usa `git reset --hard origin/main` en lugar de `git pull` para
garantizar que el VPS siempre refleja exactamente el repo, descartando cualquier
cambio local que haya quedado de un deploy fallido anterior.

```yaml
git fetch origin main
git reset --hard origin/main
```

---

## ✅ Verificar que el proxy funciona

```bash
curl -v https://proxy.batidospitaya.com/api/ping.php
```

Respuesta esperada:
```json
{"status":"success","message":"pong","timestamp":...}
```
HTTP 200 — Proxy operativo.

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

# 2. Revisar sintaxis de config
nginx -t

# 3. Ver errores recientes
tail -50 /var/log/nginx/proxy-batidospitaya-error.log

# 4. Verificar que el DNS resuelve correctamente
nslookup proxy.batidospitaya.com
# Debe devolver 198.211.97.243

# 5. Verificar que los puertos están abiertos en UFW
ufw status | grep -E "80|443"

# 6. Probar conexión directa a la API (sin proxy)
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
nginx -t && systemctl reload nginx
```

---

## 💡 Notas del VPS

### Nginx es exclusivo de este proyecto

**Nginx no estaba instalado** en el VPS antes de este proyecto.
PostulacionBotVPS y otros proyectos usan PM2 con FastAPI/Node directamente
en sus puertos — ninguno necesita Nginx. Este proyecto fue el primero en
instalarlo.

| Proyecto | Servidor | Nginx |
|----------|----------|-------|
| PostulacionBotVPS | FastAPI + PM2 (puerto 8765) | ❌ |
| Otros bots/scrapers | Node/Python + PM2 | ❌ |
| **proxy.batidospitaya** | **Nginx 1.24.0** | ✅ |

### GitHub Actions en VS Code

La extensión de GitHub Actions de VS Code muestra el repo según el **git root
activo**. Como el workspace apunta a `VisualCode/` (carpeta padre con múltiples
repos), no detecta `proxy.batidospitaya.com/` automáticamente.

Para ver las Actions de este repo:
- **En GitHub:** `https://github.com/MiguelGotea/proxy.batidospitaya/actions`
- **En VS Code:** `File → Add Folder to Workspace` → seleccionar `proxy.batidospitaya.com/`

---

## 🛡️ WireGuard — Análisis de configuración

Se leyó `/etc/wireguard/wg0.conf` directamente en el VPS.

El VPS actúa como **servidor WireGuard** (no cliente). Los peers son las
sucursales: `pitaya`, `villafontana`, `leon`, `matagalpa`, `esteli`,
`altamira`, `granada`, `lascolinas`, `masaya`, `natura`, `lasbrisas`,
`rivas`, `unica`, `ticuantepe`, `calli`, `contabilidad`, `sistemas`,
`procesamiento`.

| Aspecto | Resultado |
|---------|-----------|
| `AllowedIPs` de cada peer | Solo IPs privadas `10.66.66.x/32` |
| ¿`AllowedIPs = 0.0.0.0/0`? | ❌ No — el VPS no es cliente de nadie |
| PostUp/PostDown | Solo MASQUERADE para que los peers salgan por `eth0` |
| Tráfico saliente del VPS | Sale por `eth0` normalmente |

### ✅ Sin problema de ruteo

El tráfico de `proxy_pass` hacia `api.batidospitaya.com` sale por `eth0`
directamente. No se requiere ninguna corrección adicional en `setup.sh`.

> **Nota futura:** Si se agrega el VPS como cliente de otro túnel con
> `AllowedIPs = 0.0.0.0/0`, agregar ruta de política:
> ```bash
> ip rule add to $(dig +short api.batidospitaya.com | tail -1) table main priority 100
> ```

---

## 🔐 Seguridad

- Sin credenciales en el repositorio
- SSL/TLS gestionado por Let's Encrypt (certbot auto-renew via systemd timer)
- `proxy_ssl_verify off` es intencional: Cloudflare es el destino final de confianza
- HTTP (puerto 80) redirige automáticamente a HTTPS (301)
- Puertos 80 y 443 abiertos en UFW, resto bloqueado por defecto