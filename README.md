# NOVA

Proyecto iOS original con la misma funcionalidad de catálogo, parches y activación, rebrandeado como **NOVA**. La activación ya no depende de M3SB: el servidor NOVA genera, almacena y valida sus propias claves.

## API NOVA

`nova-api/` es una implementación opcional Flask/SQLite para despliegue propio. La IPA de la rama principal usa ahora la NOVA Key Console alojada en `https://novakey-8h6koiim.manus.space/` y su API en `https://novakey-8h6koiim.manus.space/api`. Sus almacenes son independientes: genera las claves destinadas a esta compilación en la consola alojada, no en el backend opcional.

Para desarrollo local:

```bash
cd nova-api
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export NOVA_ADMIN_USERNAME=admin
export NOVA_ADMIN_PASSWORD='elige-una-clave-larga-y-unica'
export NOVA_DATA="$PWD/data"
python server.py
```

Abre `http://127.0.0.1:5000` para entrar al panel. Antes de exponerlo a Internet, configura HTTPS mediante un proxy inverso y una contraseña administrativa fuerte. No uses el servidor de desarrollo de Flask como servicio público.

Rutas principales: `POST /api/license/verify` valida una clave y devuelve la sesión temporal de cliente; `POST /api/admin/licenses` (sesión de administrador) genera claves; `GET /api/admin/licenses` lista metadatos no secretos; `POST /api/admin/licenses/revoke` revoca una clave. El backend conserva las rutas autenticadas de catálogo y descarga que usa la app.

## Conectar la IPA

GitHub Actions configura `NOVA_API_BASE_URL` en `.github/workflows/build.yml` con la dirección base pública actual `https://novakey-8h6koiim.manus.space/api`. La URL no es un secreto. Si cambia el dominio alojado, actualiza ese valor en el workflow. Para compilar localmente, puedes pasar la misma variable:

```bash
NOVA_API_BASE_URL=https://novakey-8h6koiim.manus.space/api ./build_unsigned.sh
```

La compilación de IPA requiere macOS y Xcode. El artefacto de GitHub Actions se llamará `NOVA-Build-49-unsigned-IPA` y contendrá `NOVA-Build-49-unsigned.ipa`. La IPA es sin firmar y debes firmarla con tu método habitual antes de instalarla.

## Pruebas

```bash
python3 -m unittest discover -s nova-api -v
python3 generate_embedded_localizations.py --check
```
