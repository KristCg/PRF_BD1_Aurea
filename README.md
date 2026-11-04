# Áurea · Un lugar para quedarse

Aplicación web en español para gestionar la cafetería: tablero, reservaciones, mesas, clientes, menú, inventario, personal, sucursales, cinco reportes y bitácora. Diseño inspirado en la imagen del equipo, adaptable a computadora y móvil.

## Probar la interfaz sin configurar PostgreSQL

Requiere Python 3.10 o superior. Desde esta carpeta:

```powershell
python server.py
```

En Windows, si `python` no se reconoce, usa `py server.py` (y `py` en lugar de `python` para los comandos iniciales).

Abre **http://localhost:8000** y elige Administrador, Gerente o Mesero en los botones de demostración. Puedes crear reservas, clientes, visitas y consumos; registrar movimientos de inventario; consultar reportes y exportar CSV. La demo guarda sus cambios solamente en el navegador y se puede restablecer. Las cuentas registradas en demo también son locales.

Para regresar al modo demo después de configurar PostgreSQL, elimina `DATABASE_URL` de la terminal y reinicia el servidor.

## Conectar a PostgreSQL y cargar datos

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
$env:AUREA_ADMIN_PASSWORD = 'REEMPLAZA_CON_UNA_CLAVE_DE_10_O_MAS_CARACTERES'
python server.py --seed
python server.py
```

La carga incluye dos sucursales, diez clientes, ocho platillos, doce ingredientes, lotes con alertas, mesas, personal, reservas, visitas, ventas y favoritos. Las fechas se calculan al ejecutar la carga. Se exigen tablas vacías y se usa una transacción: no se duplican ni se borran datos existentes. No vuelvas a ejecutar `--seed` sobre una base cargada.

5. Abre **http://localhost:8000** con el correo y contraseña configurados. En modo PostgreSQL desaparecen los botones demo. El registro público crea solamente meseros. Para asignar un gerente o administrador a una cuenta registrada, el responsable de la base puede ejecutar:

```sql
UPDATE usuario SET rol = 'Gerente' WHERE correo = 'persona@aurea.gt';
```

Cierra y vuelve a iniciar sesión después de cambiar el rol. El catálogo laboral `rol` y el rol de acceso `usuario.rol` son independientes.

## Permisos

| Operación | Mesero | Gerente | Administrador |
| --- | --- | --- | --- |
| Reservas, clientes, visitas y favoritos | Sí | Sí | Sí |
| Consultar menú y mesas | Sí | Sí | Sí |
| Editar menú/mesas y gestionar inventario | No | Sí | Sí |
| Personal y sucursales | No | No | Sí |
| Reportes, bitácora y eliminaciones sin relaciones | No | No | Sí |

## Preparar la presentación

- Crea un cliente y una reserva. Prueba un horario ocupado y capacidad insuficiente; se rechazan. Cancela o completa la reserva desde su formulario.
- Abre el nombre del cliente, agrega favoritos y registra una visita con consumo. Revisa el historial y los reportes.
- Revisa las alertas en Inventario y registra una entrada o merma. Se validan existencias y personal de la sucursal.
- Consulta los cinco reportes para un mes y sucursal, exporta CSV o imprime.
- Revisa la bitácora: los triggers guardan quién cambió qué y sus valores anteriores/nuevos.

La cobertura de la rúbrica y la interpretación del umbral del 15% están en [docs/RUBRICA.md](docs/RUBRICA.md). El modelo extendido y su DER actualizado en Mermaid están en [docs/MODELO.md](docs/MODELO.md). La imagen del DER original se conserva en `Diseño_BD_tablas_graficos/`.

Si tu base ya tenía datos y no puedes usar la carga de ejemplo, crea una cuenta desde la pantalla de registro y asigna su rol de administrador desde pgAdmin: `UPDATE usuario SET rol = 'Administrador' WHERE correo = 'tu-correo@aurea.gt';`. Luego cierra y vuelve a iniciar sesión.

## Estructura

```text
server.py                  HTTP, autenticación y API PostgreSQL
seed.py                    Carga ficticia transaccional
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
