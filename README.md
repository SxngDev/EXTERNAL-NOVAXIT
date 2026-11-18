# NOVA

Proyecto iOS original con la misma funcionalidad de catálogo, parches y activación, rebrandeado como **NOVA**. La activación ya no depende de M3SB: el servidor NOVA genera, almacena y valida sus propias claves.

## API NOVA

El backend está en [`nova-api/`](nova-api/README.md). Usa Flask y SQLite; el panel web privado permite emitir hasta 100 claves por lote, elegir vigencia (0 = permanente), limitar dispositivos y revocar claves. Las claves se muestran solo al generarlas; la base guarda únicamente su SHA-256. Por defecto una licencia queda enlazada al primer dispositivo que la active.

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

La app recibe la URL base de API al compilar mediante `NOVA_API_BASE_URL`, con formato `https://tu-dominio/api`. El valor de ejemplo `https://api.nova.example/api` no es un servidor real; sustituye el dominio después de desplegar el backend. En GitHub Actions, configura la variable de repositorio `NOVA_API_BASE_URL`; para una compilación local:

```bash
NOVA_API_BASE_URL=https://api.tu-dominio.com/api ./build_unsigned.sh
```

La compilación de IPA requiere macOS y Xcode. El archivo resultante se llamará `build/NOVA-Build-49-unsigned.ipa`. La IPA es sin firmar y debes firmarla con tu método habitual. Este entorno Linux no puede producir el IPA final de Xcode.

## Pruebas

```bash
python3 -m unittest discover -s nova-api -v
python3 generate_embedded_localizations.py --check
```
