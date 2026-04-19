# INSTRUCCIONES PREVIAS — proxy.batidospitaya.com

> ⚠️ Seguir estos pasos **en orden estricto** antes del primer deploy automático.

---

## Paso 1 — DNS en Hostinger

1. Acceder al panel de Hostinger → **Dominios** → `batidospitaya.com` → **DNS Zone**
2. Agregar el registro:

   | Tipo | Nombre | Valor           | TTL |
   |------|--------|-----------------|-----|
   | A    | proxy  | 198.211.97.243  | 300 |

3. Verificar propagación (esperar 2-5 minutos):

   ```
   nslookup proxy.batidospitaya.com
   ```

   ✅ Debe devolver `198.211.97.243` antes de continuar al siguiente paso.

---

## Paso 2 — Whitelist IP del VPS en Cloudflare (via Hostinger)

Cloudflare está gestionado por Hostinger sin acceso directo al panel CF.  
El VPS hace muchas peticiones seguidas a `api.batidospitaya.com` — sin whitelist,
Cloudflare puede bloquearlas con rate limiting o JS challenges.

### Opción A — Si Hostinger tiene sección "Cloudflare" en el panel:
1. Ir a **Seguridad** o **Cloudflare** dentro del panel de Hostinger
2. Buscar **IP Access Rules** o **Firewall Rules**
3. Agregar regla:
   - Acción: `Allow`
   - IP: `198.211.97.243`
   - Zona: `api.batidospitaya.com`

### Opción B — Via soporte de Hostinger (si no tienes acceso al panel CF):
Abrir ticket con el siguiente mensaje exacto:

> "Necesito que la IP `198.211.97.243` sea marcada como **trusted** en Cloudflare
> para el dominio `api.batidospitaya.com`. Esta IP pertenece a nuestro servidor proxy
> propio y realiza muchas peticiones seguidas legítimas desde sucursales.
> Necesito que se cree una IP Access Rule de tipo **Allow** para esta IP."

---

## Paso 3 — Secrets en GitHub

En el repositorio `MiguelGotea/proxy.batidospitaya`:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret            | Valor                                           |
|-------------------|-------------------------------------------------|
| `VPS_HOST`        | `198.211.97.243`                                |
| `VPS_USER`        | `root`                                          |
| `SSH_PRIVATE_KEY` | La misma llave privada de `PostulacionBotVPS`   |

> 💡 Los valores son idénticos a los de `MiguelGotea/PostulacionBotVPS`.

---


## Paso 4 — Primer clone en el VPS via SSH

Conectarse al VPS y clonar el repositorio en la ruta del proyecto:

```bash
ssh root@198.211.97.243

# Crear el directorio del proyecto
mkdir -p /root/proxy-batidospitaya
cd /root/proxy-batidospitaya

# Clonar el repositorio (nota: sin .com en el nombre del repo)
git clone https://github.com/MiguelGotea/proxy.batidospitaya .

# Verificar que los archivos están
ls -la
```

> Después de esto, cada push via `.scripts/gitpush.ps1` dispara el deploy automáticamente.

---

## Paso 5 — Cambio de URLs en Access (manual desde el editor VBA)

Realizar en cada archivo `.accdb` de las sucursales, **una por una** (probar primero en una):

1. Abrir el archivo `.accdb`
2. Presionar **Alt+F11** → se abre el editor VBA
3. Presionar **Ctrl+H** → cuadro de buscar y reemplazar
4. Configurar:
   - **Find What:** `api.batidospitaya.com`
   - **Replace With:** `proxy.batidospitaya.com`
   - **Current Project** (scope)
5. Click en **Replace All** → guardar el archivo

> ✅ Probar con una sucursal antes de distribuir el cambio a las demás.
