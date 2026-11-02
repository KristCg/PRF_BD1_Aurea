"""API y archivos estáticos del módulo de inventario de Áurea."""
import os
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

import psycopg
from psycopg.rows import dict_row
from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

app = Flask(__name__, static_folder='static', static_url_path='')
app.config['MAX_CONTENT_LENGTH'] = 32 * 1024
CATEGORIES = ('Café y té', 'Lácteos', 'Panadería', 'Despensa', 'Frutas y frescos')
UNITS = ('kg', 'g', 'L', 'ml', 'ud')


def connect():
    return psycopg.connect(os.environ['DATABASE_URL'], row_factory=dict_row,
                          options='-c search_path=inventario,public -c timezone=America/Guatemala')


def serial(value):
    if isinstance(value, dict):
        return {k: serial(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [serial(v) for v in value]
    if isinstance(value, Decimal):
        return str(value)  # conservar precisión; el navegador formatea la presentación
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def response(value, status=200):
    return jsonify(serial(value)), status


def payload():
    value = request.get_json(silent=True)
    if not isinstance(value, dict):
        raise ValueError('Envía un objeto JSON válido.')
    return value


def text_field(data, name, limit):
    value = data.get(name)
    if not isinstance(value, str) or not value.strip() or len(value.strip()) > limit:
        raise ValueError(f'{name}: escribe entre 1 y {limit} caracteres.')
    return value.strip()


def number(data, name, positive=False):
    try:
        if isinstance(data.get(name), bool):
            raise ValueError()
        value = Decimal(str(data.get(name)))
        if not value.is_finite() or value < 0 or value > Decimal('999999999.999'):
            raise ValueError()
        if value != value.quantize(Decimal('.001')) or (positive and value == 0):
            raise ValueError()
        return value
    except (InvalidOperation, ValueError, TypeError):
        raise ValueError(f'{name}: usa una cantidad {"mayor que cero" if positive else "no negativa"}, con hasta 3 decimales.') from None


def identifier(value, name):
    if isinstance(value, bool) or not str(value).isdigit() or int(value) <= 0:
        raise ValueError(f'{name} no válido.')
    return int(value)


def ingredient_data(data):
    name = text_field(data, 'nombre_ingrediente', 60)
    category = text_field(data, 'categoria', 25)
    unit = text_field(data, 'unidad_medida', 4)
    minimum = number(data, 'stock_minimo')
    reference = number(data, 'stock_referencia', positive=True)
    if category not in CATEGORIES or unit not in UNITS:
        raise ValueError('Categoría o unidad de medida no válida.')
    if minimum > reference:
        raise ValueError('La existencia de referencia debe ser igual o mayor al mínimo.')
    return name, category, unit, minimum, reference


@app.errorhandler(ValueError)
def validation_error(error):
    return response({'error': str(error)}, 400)


@app.errorhandler(psycopg.Error)
def database_error(error):
    if isinstance(error, psycopg.errors.UniqueViolation):
        message, status = 'Ese nombre de insumo o código de lote ya existe.', 409
    elif isinstance(error, psycopg.errors.ForeignKeyViolation):
        message, status = 'El registro está relacionado con otros datos o ya no existe.', 409
    elif error.sqlstate == 'P0001':
        message, status = error.diag.message_primary, 409
    elif isinstance(error, (psycopg.errors.CheckViolation, psycopg.errors.NumericValueOutOfRange)):
        message, status = 'Los datos no cumplen las restricciones del inventario.', 400
    else:
        app.logger.exception('Error de base de datos')
        message, status = 'No se pudo consultar la base de datos. Intenta nuevamente.', 503
    return response({'error': message}, status)


@app.errorhandler(HTTPException)
def http_error(error):
    if request.path.startswith('/api/'):
        return response({'error': error.description}, error.code)
    return error


@app.after_request
def headers(res):
    res.headers['X-Content-Type-Options'] = 'nosniff'
    res.headers['Content-Security-Policy'] = "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
    if request.path.startswith('/api/'):
        res.headers['Cache-Control'] = 'no-store'
    return res


@app.get('/')
def index():
    return app.send_static_file('index.html')


@app.get('/api/health')
def health():
    with connect() as conn:
        conn.execute('SELECT 1 FROM inventario.ingrediente LIMIT 1')
    return response({'status': 'ok'})


@app.get('/api/inventario')
def inventory():
    branch = identifier(request.args.get('sucursal_id', '1'), 'Sucursal')
    with connect() as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        branches = conn.execute('SELECT * FROM sucursal ORDER BY sucursal_id').fetchall()
        if not any(b['sucursal_id'] == branch for b in branches):
            raise ValueError('La sucursal no existe.')
        items = conn.execute('SELECT * FROM existencias WHERE sucursal_id=%s ORDER BY ingrediente_id', (branch,)).fetchall()
        lots = conn.execute('''SELECT l.*, i.nombre_ingrediente, i.unidad_medida, i.categoria,
            (l.fecha_vencimiento - CURRENT_DATE) AS dias_restantes
            FROM lote_inventario l JOIN ingrediente i USING(ingrediente_id)
            WHERE l.sucursal_id=%s ORDER BY l.fecha_vencimiento, l.lote_id''', (branch,)).fetchall()
        movements = conn.execute('''SELECT m.*, i.nombre_ingrediente, i.unidad_medida,
            i.categoria, i.ingrediente_id
            FROM movimiento_inventario m JOIN lote_inventario l USING(lote_id)
            JOIN ingrediente i USING(ingrediente_id) WHERE l.sucursal_id=%s
            ORDER BY m.fecha_hora DESC, m.movimiento_id DESC''', (branch,)).fetchall()
        today = conn.execute('SELECT CURRENT_DATE AS hoy').fetchone()['hoy']
    return response({'sucursales': branches, 'insumos': items, 'lotes': lots,
                     'movimientos': movements, 'hoy': today, 'dias_alerta': 7})


@app.post('/api/insumos')
def create_ingredient():
    values = ingredient_data(payload())
    with connect() as conn:
        row = conn.execute('''INSERT INTO ingrediente(nombre_ingrediente,categoria,unidad_medida,stock_minimo,stock_referencia)
            VALUES (%s,%s,%s,%s,%s) RETURNING ingrediente_id''', values).fetchone()
    return response(row, 201)


@app.put('/api/insumos/<int:item_id>')
def update_ingredient(item_id):
    values = ingredient_data(payload())
    with connect() as conn:
        old = conn.execute('SELECT * FROM ingrediente WHERE ingrediente_id=%s FOR UPDATE', (item_id,)).fetchone()
        if not old:
            return response({'error': 'El insumo no existe.'}, 404)
        if old['unidad_medida'] != values[2] and conn.execute('SELECT 1 FROM lote_inventario WHERE ingrediente_id=%s LIMIT 1', (item_id,)).fetchone():
            raise ValueError('No se puede cambiar la unidad de un insumo con lotes registrados.')
        conn.execute('''UPDATE ingrediente SET nombre_ingrediente=%s,categoria=%s,unidad_medida=%s,
            stock_minimo=%s,stock_referencia=%s WHERE ingrediente_id=%s''', (*values, item_id))
    return response({'ok': True})


@app.delete('/api/insumos/<int:item_id>')
def delete_ingredient(item_id):
    with connect() as conn:
        if conn.execute('SELECT 1 FROM lote_inventario WHERE ingrediente_id=%s LIMIT 1', (item_id,)).fetchone():
            return response({'error': 'Este insumo tiene lotes registrados. Se conserva para mantener su historial.'}, 409)
        row = conn.execute('DELETE FROM ingrediente WHERE ingrediente_id=%s RETURNING ingrediente_id', (item_id,)).fetchone()
        if not row:
            return response({'error': 'El insumo no existe.'}, 404)
    return response({'ok': True})


@app.post('/api/lotes')
def create_lot():
    data = payload()
    code = text_field(data, 'lote_id', 30)
    item = identifier(data.get('ingrediente_id'), 'Insumo')
    branch = identifier(data.get('sucursal_id'), 'Sucursal')
    quantity = number(data, 'cantidad', positive=True)
    responsible = text_field(data, 'responsable', 60)
    reason = text_field(data, 'motivo', 200)
    try:
        expires = date.fromisoformat(data.get('fecha_vencimiento', ''))
    except (ValueError, TypeError):
        raise ValueError('La fecha de vencimiento no es válida.') from None
    with connect() as conn:
        today = conn.execute('SELECT CURRENT_DATE AS hoy').fetchone()['hoy']
        if expires < today:
            raise ValueError('No se pueden recibir lotes vencidos.')
        # Comparte bloqueo con la edición: la unidad no puede cambiar durante una recepción.
        if not conn.execute('SELECT 1 FROM ingrediente WHERE ingrediente_id=%s FOR SHARE', (item,)).fetchone():
            raise ValueError('El insumo no existe.')
        conn.execute('''INSERT INTO lote_inventario(lote_id,ingrediente_id,sucursal_id,fecha_vencimiento)
            VALUES (%s,%s,%s,%s)''', (code, item, branch, expires))
        row = conn.execute('''INSERT INTO movimiento_inventario(lote_id,tipo_movimiento,cantidad,responsable,motivo)
            VALUES (%s,'Entrada',%s,%s,%s) RETURNING movimiento_id''', (code, quantity, responsible, reason)).fetchone()
    return response(row, 201)


@app.post('/api/movimientos')
def create_movement():
    data = payload()
    code = text_field(data, 'lote_id', 30)
    kind = text_field(data, 'tipo_movimiento', 10)
    if kind not in ('Entrada', 'Salida', 'Merma', 'Ajuste'):
        raise ValueError('El tipo de movimiento no es válido.')
    quantity = number(data, 'cantidad', positive=kind != 'Ajuste')
    responsible = text_field(data, 'responsable', 60)
    reason = text_field(data, 'motivo', 200)
    with connect() as conn:
        row = conn.execute('''INSERT INTO movimiento_inventario(lote_id,tipo_movimiento,cantidad,responsable,motivo)
            VALUES (%s,%s,%s,%s,%s) RETURNING movimiento_id, stock_resultante''',
            (code, kind, quantity, responsible, reason)).fetchone()
    return response(row, 201)
