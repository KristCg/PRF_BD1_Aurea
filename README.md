# Áurea · Un lugar para quedarse

Aplicación web en español para gestionar la cafetería: tablero, reservaciones, mesas, clientes, menú, inventario, personal, sucursales, cinco reportes y bitácora. Diseño inspirado en la imagen del equipo, adaptable a computadora y móvil.

## Probar la interfaz sin configurar PostgreSQL

Requiere Python 3.10 o superior. Desde esta carpeta:

```powershell
python server.py
```

En Windows, si `python` no se reconoce, usa `py server.py` (y `py` en lugar de `python` para los comandos iniciales).

Abre **http://localhost:8000** y elige Administrador, Gerente o Mesero en los botones de demostración. Puedes crear reservas, clientes, visitas y consumos; registrar movimientos de inventario; consultar reportes y exportar CSV. La demo guarda sus cambios solamente en el navegador y se puede restablecer. El administrador también puede crear cuentas demo desde Usuarios; estas son locales.

Para regresar al modo demo después de configurar PostgreSQL, elimina `DATABASE_URL` de la terminal y reinicia el servidor.

## Alternativa con Docker: PostgreSQL y aplicación juntos

Necesitas Docker Desktop abierto y configurado para contenedores Linux. No necesitas instalar Python ni PostgreSQL en tu equipo para esta alternativa.

1. Crea el archivo de configuración desde esta carpeta:

```powershell
Copy-Item .env.docker.example .env
```

Si ya tienes un `.env`, agrega las variables del ejemplo sin sobrescribir tu configuración. Para las pruebas locales, el ejemplo usa `1234` tanto en `POSTGRES_PASSWORD` como en `AUREA_ADMIN_PASSWORD`. La contraseña inicial del administrador requiere al menos cuatro caracteres. `.env` está excluido de Git y de la imagen.

2. Construye e inicia los dos servicios:

```powershell
docker compose up --build -d --wait
```

3. Abre **http://localhost:8000**. Ingresa con `AUREA_ADMIN_EMAIL` (por defecto `admin@aurea.gt`) y la contraseña de administrador que guardaste en `.env`.

### Credenciales para pruebas locales

Acceso a la aplicación en **http://localhost:8000** con la configuración incluida:

| Rol | Correo | Contraseña |
| --- | --- | --- |
| Administrador | `admin@aurea.gt` | `1234` |
| Gerente | `gerente@aurea.gt` | `1234` |
| Mesero | `mesero@aurea.gt` | `1234` |

Las cuentas de gerente y mesero se incluyen en la carga de datos ficticios (`AUREA_SEED=true`). El administrador puede editarlas desde Usuarios o crear más cuentas. Su contraseña inicial es `1234`; la del administrador corresponde al valor de `AUREA_ADMIN_PASSWORD`.

Conexión a PostgreSQL desde pgAdmin u otra herramienta en tu equipo:

| Campo | Valor |
| --- | --- |
| Host | `localhost` |
| Puerto | `5433` |
| Base de datos | `PRF_Aurea` |
| Usuario | `aurea` |
| Contraseña | `1234` |

Desde el contenedor de la aplicación, PostgreSQL se encuentra en `db:5432`. Si personalizas las variables de `.env`, utiliza los valores correspondientes.

El primer arranque instala el esquema y carga los datos ficticios. Los siguientes arranques aplican la migración y conservan los datos, sin repetir la carga de ejemplo. La UI usa la API de Python y esta se conecta a PostgreSQL mediante la red de Compose (`db:5432`). La aplicación espera a que la base esté lista antes de inicializarse.

| Servicio | Acceso desde tu equipo |
| --- | --- |
| Interfaz y API | `http://localhost:8000` |
| PostgreSQL / pgAdmin | Host `localhost`, puerto `5433`; base, usuario y contraseña de `.env` |

Los puertos locales se pueden cambiar con `APP_PORT` y `POSTGRES_PORT`. El puerto PostgreSQL dentro de Docker sigue siendo 5432. Esto permite conservar tu instalación local de PostgreSQL en 5432. Los servicios publicados se limitan a este equipo.

Comandos de uso diario:

```powershell
docker compose ps
docker compose logs -f app
docker compose down
docker compose up -d --wait
```

`down` detiene y elimina los contenedores, pero conserva la base en el volumen `postgres_data`. No agregues `-v` si quieres conservarla. Después de modificar el código, ejecuta nuevamente `docker compose up --build -d --wait`.

Para abrir SQL sin instalar pgAdmin:

```powershell
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Si solo necesitas la base en Docker, ejecuta `docker compose up -d db` y conecta tu aplicación local o pgAdmin a `localhost:5433` con las credenciales de `.env`. Esta opción por sí sola no carga el esquema: usa el procedimiento manual de abajo o inicia también `app`.

Para trabajar sin datos ficticios, configura `AUREA_SEED=false` antes del primer arranque. Se crea el esquema y, si todavía no existe un administrador, su cuenta con las credenciales de `.env`. Cambiar el correo o contraseña iniciales en `.env` no modifica cuentas existentes. Tampoco cambia la contraseña de una base cuyo volumen ya está inicializado.

El estado de la aplicación se puede comprobar en `http://localhost:8000/api/health`; responde 503 si no logra conectarse a PostgreSQL. Si falla el arranque, revisa `docker compose logs app db`.

Referencia del orden de arranque utilizado: [Docker Compose: dependencias y healthchecks](https://docs.docker.com/compose/how-tos/startup-order/).

## Conectar a PostgreSQL y cargar datos sin Docker

1. Instala PostgreSQL 17 o superior y Python 3.10 o superior.
2. Crea un entorno virtual e instala el controlador:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

3. Crea una base vacía desde pgAdmin o con `createdb -U postgres PRF_Aurea`. Configura la conexión en la terminal usando tus credenciales:

```powershell
$env:DATABASE_URL = 'postgresql://postgres:TU_PASSWORD@localhost:5432/PRF_Aurea'
python server.py --init-db
```

`--init-db` instala la estructura base si no existe `cliente` y aplica la migración de la aplicación. El respaldo original se conserva: tiene formato custom de PostgreSQL a pesar de su extensión .sql. La inicialización utiliza su estructura exportada en `db/001_base.sql`, sin importar automáticamente sus datos.

Si ya restauraste la base original, respáldala y ejecuta `--init-db` para aplicar solamente los complementos de la aplicación. La migración puede repetirse y no elimina tablas ni registros.

4. Para una instalación nueva, crea el primer administrador y carga los datos ficticios:

```powershell
$env:AUREA_ADMIN_EMAIL = 'admin@aurea.gt'
$env:AUREA_ADMIN_PASSWORD = '1234'
python server.py --seed
python server.py
```

La carga incluye dos sucursales, diez clientes, ocho platillos, doce ingredientes, lotes con alertas, mesas, personal, reservas, visitas, ventas y favoritos. Las fechas se calculan al ejecutar la carga. Se exigen tablas vacías y se usa una transacción: no se duplican ni se borran datos existentes. No vuelvas a ejecutar `--seed` sobre una base cargada.

5. Abre **http://localhost:8000** con el correo y contraseña configurados. En modo PostgreSQL desaparecen los botones demo. Desde **Usuarios → Nuevo usuario**, el administrador registra el nombre, correo, contraseña y rol de cada integrante del equipo: Administrador, Gerente o Mesero. El vínculo a un empleado es opcional.

La pantalla de acceso solo permite iniciar sesión; no existe registro público. Para cambiar permisos, el administrador abre Usuarios y edita la cuenta. Puede dejar la contraseña vacía para conservarla o escribir una nueva de al menos cuatro caracteres. Los permisos se consultan en cada solicitud y no se permite quitarse el propio rol de administrador. Al restablecer una contraseña se cierran las otras sesiones de esa cuenta.

El catálogo laboral `rol` describe puestos de empleados; el campo `usuario.rol` controla el acceso a la aplicación.

## Permisos

| Operación | Mesero | Gerente | Administrador |
| --- | --- | --- | --- |
| Reservas, clientes, visitas y favoritos | Sí | Sí | Sí |
| Consultar menú y mesas | Sí | Sí | Sí |
| Editar menú/mesas y gestionar inventario | No | Sí | Sí |
| Personal y sucursales | No | No | Sí |
| Crear cuentas y asignar roles en Usuarios | No | No | Sí |
| Reportes, bitácora y eliminaciones sin relaciones | No | No | Sí |

## Preparar la presentación

- Crea un cliente y una reserva. Prueba un horario ocupado y capacidad insuficiente; se rechazan. Cancela o completa la reserva desde su formulario.
- Abre el nombre del cliente, agrega favoritos y registra una visita con consumo. Revisa el historial y los reportes.
- Revisa las alertas en Inventario y registra una entrada o merma. Se validan existencias y personal de la sucursal.
- Consulta los cinco reportes para un mes y sucursal, exporta CSV o imprime.
- Revisa la bitácora: los triggers guardan quién cambió qué y sus valores anteriores/nuevos.

La cobertura de la rúbrica y la interpretación del umbral del 15% están en [docs/RUBRICA.md](docs/RUBRICA.md). El modelo extendido y su DER actualizado en Mermaid están en [docs/MODELO.md](docs/MODELO.md). La imagen del DER original se conserva en `Diseño_BD_tablas_graficos/`.

Si tu base ya tenía datos y no puedes usar la carga de ejemplo, configura `AUREA_ADMIN_EMAIL` y `AUREA_ADMIN_PASSWORD` y ejecuta `python server.py --create-admin`. Este comando instala el esquema de la aplicación y crea el primer administrador solo si aún no existe uno. No reemplaza cuentas ni contraseñas existentes. En Docker este paso se realiza automáticamente al arrancar.

## Estructura

```text
server.py                  HTTP, autenticación y API PostgreSQL
seed.py                    Carga ficticia transaccional
Dockerfile                 Imagen de Python y la interfaz
compose.yaml               Aplicación y PostgreSQL con volumen persistente
docker/entrypoint.py       Inicialización y carga opcional al arrancar
.env.docker.example        Configuración de ejemplo para Compose
static/index.html          Aplicación web sin compilación
static/app.js              Pantallas, formularios y demo
static/styles.css          Diseño adaptable e impresión
db/001_base.sql            Estructura original exportada
db/002_aplicacion.sql       Extensiones, vistas, índices y triggers
tests/test_integration.py  Pruebas en PostgreSQL aislado
```

No se necesita Node ni npm. La fotografía se incluye en `static/assets`; las tipografías tienen alternativas locales. El servidor escucha en localhost. Para acceso remoto, configura un proxy HTTPS, un servicio persistente y credenciales privadas de PostgreSQL; no publiques contraseñas en Git.

## Pruebas

Usa una base **de pruebas aislada**, inicializada con `--init-db --seed`, y las dependencias instaladas. Cada caso termina en rollback. No apuntes estas pruebas a producción.

```powershell
$env:AUREA_TEST_DATABASE_URL = 'postgresql://postgres:TU_PASSWORD@localhost:5432/PRF_Aurea_test'
python -m unittest discover -s tests -v
```

## Información original del equipo
Proyecto 2 y Final del curso de Base de Datos 1


Documento con información general y base del menú, ingredientes, etc. de Aurea. https://app.notion.com/p/ESTILO-Y-MEN-CAFETER-A-3faf6ebcf13680e78cc0c4b55fde6609
