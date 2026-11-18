# NOVA API

API Flask propia para la app NOVA. No necesita cuenta, token ni respuesta firmada de M3SB. Incluye el servicio que atiende catálogo y sesiones de cliente, más generación y revocación de claves de licencia propias.

## Configuración básica

Instala las dependencias y configura las variables privadas en el entorno del proceso:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export NOVA_ADMIN_USERNAME=admin
export NOVA_ADMIN_PASSWORD='reemplaza-esto-por-una-contraseña-larga'
export NOVA_DATA=/opt/nova-api/data
export NOVA_PACKAGE_PASSWORDS='[]'
python server.py
```

Para uso público, ejecuta detrás de un proxy TLS/HTTPS con un servidor WSGI de producción y restringe el acceso de red al panel. No subas `.env`, la base de datos ni secretos al repositorio. Conserva `NOVA_DATA` en almacenamiento persistente y protegido.

## Panel de claves

Inicia sesión en la página principal y abre **License key generator**. Elige cantidad (1–100), días de vigencia (0 significa permanente), límite de dispositivos (1–10) y una nota opcional. El panel presenta el valor completo de cada clave solo en el momento de creación: guárdalo en ese momento. El servidor conserva únicamente el hash SHA-256 y los últimos cuatro caracteres para identificarla en la lista. Una clave se enlaza al primer dispositivo que la active; solicitudes posteriores desde ese mismo dispositivo funcionan y el resto se rechaza al alcanzar el límite. Revocar elimina también las sesiones activas de esa licencia.

## API

- `POST /api/license/verify` JSON `{ "key": "NOVA-…", "device_id": "…" }`; responde con `valid`, `expires_at` y una sesión temporal `client_session` si la clave es válida.
- `POST /api/client/session/logout` revoca la sesión cliente autenticada con `Authorization: Bearer …`.
- `POST /api/admin/licenses` requiere sesión de administrador; recibe `count`, `days`, `max_devices` y `note`. Las claves se devuelven una sola vez.
- `GET /api/admin/licenses` requiere sesión de administrador; no devuelve claves completas.
- `POST /api/admin/licenses/revoke` requiere sesión de administrador y recibe la clave completa en JSON `{ "key": "…" }`.
- `GET /api/patches` y descargas de paquetes siguen requiriendo sesión Bearer válida.

Las claves se guardan como hash, las respuestas de activación llevan `Cache-Control: no-store` y las sesiones de cliente son aleatorias, de corta duración y almacenadas en forma de hash. La identidad del dispositivo es un identificador aleatorio persistido en Keychain por la app; no es un UDID de hardware.

## Pruebas

Desde el directorio raíz del proyecto:

```bash
python3 -m unittest discover -s nova-api -v
```

## Despliegue en servidor propio

Copia `nova-api/` a un VPS Linux con Docker y un proxy inverso que proporcione HTTPS; crea `.env` a partir de `.env.example` y pon una contraseña real. Después ejecuta `docker compose up -d --build`. El servicio queda escuchando solo en `127.0.0.1:8000`; el proxy TLS debe enviar el tráfico a ese puerto y reemplazar `X-Forwarded-*` antes de entregarlo a NOVA. Configura `NOVA_API_BASE_URL=https://tu-dominio/api` al compilar la IPA. El volumen `nova-data` conserva la base y archivos al actualizar el contenedor.
