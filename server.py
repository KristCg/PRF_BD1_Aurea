"""Áurea: servidor HTTP y API PostgreSQL. Sin DATABASE_URL sirve el modo demo."""
import argparse
import datetime as dt
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
from decimal import Decimal
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
SESSIONS = {}
LOGIN_ATTEMPTS = {}
LOCK = threading.Lock()
ENTITIES = {
 'clientes': ('cliente','cliente_id',['nit','nombre','apellido','telefono']),
 'platillos': ('platillo','platillo_id',['nombre_platillo','precio','categoria']),
 'ingredientes': ('ingrediente','ingrediente_id',['nombre_ingrediente','unidad_medida','stock_minimo']),
 'lotes': ('lote_inventario','lote_id',['lote_id','ingrediente_id','sucursal_id','fecha_ingreso','fecha_vencimiento','cantidad_disponible']),
 'personal': ('empleado','empleado_id',['nombre_empleado','apellido','fecha_contratacion','rol_id','sucursal_id','estado']),
 'sucursales': ('sucursal','sucursal_id',['nombre_sucursal','telefono','dirreccion','capacidad']),
 'mesas': ('mesa','mesa_id',['mesa_id','sucursal_id','capacidad','estado']),
}

class ValidationError(Exception):
 pass

def connection():
 import psycopg
 from psycopg.rows import dict_row
 return psycopg.connect(os.environ['DATABASE_URL'], row_factory=dict_row)

def password_hash(password, salt=None):
 salt = salt or secrets.token_hex(16)
 digest = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 600000).hex()
 return salt + ':' + digest

def check_password(password, encoded):
 return hmac.compare_digest(password_hash(password, encoded.split(':')[0]), encoded)

def json_default(value):
 if isinstance(value, (dt.date,dt.time,dt.datetime)): return value.isoformat()
 if isinstance(value, Decimal): return float(value)
 raise TypeError(type(value).__name__)

def require(condition, message):
 if not condition: raise ValidationError(message)

def actor(conn, user):
 conn.execute("SELECT set_config('aurea.usuario',%s,true)",(user['correo'],))

def snapshot(conn, user):
 data = {}
 for key,(table,_,_) in ENTITIES.items():
  data[key] = conn.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall()
 for key,table in [('reservas','reserva'),('asignaciones','reserva_mesa'),('roles','rol'),('preferencias','preferencia'),('visitas','visita'),('ventas','v_ventas')]:
  data[key] = conn.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall()
 data['movimientos'] = conn.execute('SELECT * FROM movimiento_inventario ORDER BY fecha_hora DESC LIMIT 200').fetchall() if user['rol']!='Mesero' else []
 data['bitacora'] = conn.execute('SELECT bitacora_id,fecha_hora,usuario,tabla,operacion,anterior,nuevo FROM bitacora ORDER BY bitacora_id DESC LIMIT 300').fetchall() if user['rol']=='Administrador' else []
 if user['rol']=='Mesero':
  for key in ['ingredientes','lotes','personal']: data[key]=[]
 return data

def save_entity(conn,key,payload,record_id,user):
 require(key in ENTITIES,'Módulo desconocido.')
 require(user['rol']!='Mesero' or key=='clientes','Tu rol no permite esta operación.')
 require(user['rol']=='Administrador' or key not in ['personal','sucursales'],'Se requiere administrador.')
 table,pk,fields=ENTITIES[key]
 values={k:payload[k] for k in fields if k in payload}
 require(values,'Completa los campos del formulario.')
 for field in ['nombre','apellido','nombre_platillo','nombre_ingrediente','nombre_empleado','nombre_sucursal','unidad_medida','categoria','dirreccion']:
  if field in values: require(str(values[field]).strip(),f'El campo {field} es obligatorio.')
 for field in ['precio','stock_minimo','cantidad_disponible']:
  if field in values: require(Decimal(str(values[field]))>=0,'Las cantidades no pueden ser negativas.')
 if 'capacidad' in values: require(int(values['capacidad'])>0,'La capacidad debe ser mayor a cero.')
 if key=='lotes': require(values.get('fecha_vencimiento','9999')>=values.get('fecha_ingreso','0000'),'El vencimiento debe ser posterior al ingreso.')
 if record_id is not None:
  where=f'{pk}=%s'; args=[record_id]
  if key=='mesas': where+=' AND sucursal_id=%s'; args.append(payload['sucursal_id'])
  edits={k:v for k,v in values.items() if k!=pk}
  result=conn.execute(f"UPDATE {table} SET "+','.join(f'{k}=%s' for k in edits)+f' WHERE {where} RETURNING *',list(edits.values())+args).fetchone()
  require(result is not None,'El registro ya no existe.')
 else:
  result=conn.execute(f"INSERT INTO {table} ({','.join(values)}) VALUES ({','.join(['%s']*len(values))}) RETURNING *",list(values.values())).fetchone()
 return result

def save_reservation(conn,p,user):
 branch=int(p['sucursal_id']); tables=[int(x) for x in p.get('mesas',[])]
 require(tables,'Selecciona al menos una mesa.')
 require(len(set(tables))==len(tables),'No repitas mesas.')
 require(int(p['personas'])>0,'Indica una cantidad válida de personas.')
 require(p['estado'] in ['Pendiente','Confirmada','Cancelada','Completada'],'Estado inválido.')
 duration=int(p.get('duracion_minutos',90)); require(15<=duration<=480,'La duración debe estar entre 15 y 480 minutos.')
 start=dt.datetime.fromisoformat(p['fecha_reserva']+'T'+p['hora_reserva'])
 rid=p.get('reserva_id')
 # Serialize overlapping checks within a branch; the lock is held through commit.
 conn.execute('SELECT pg_advisory_xact_lock(%s)',(branch,))
 seats=0
 for mid in tables:
  mesa=conn.execute('SELECT * FROM mesa WHERE mesa_id=%s AND sucursal_id=%s FOR UPDATE',(mid,branch)).fetchone()
  require(mesa is not None,'La mesa no pertenece a esta sucursal.')
  if p['estado'] in ['Pendiente','Confirmada']:
   require(mesa['estado']!='Ocupada','La mesa está ocupada. Libérala antes de asignarla.')
   conflict=conn.execute("""SELECT r.reserva_id FROM reserva r JOIN reserva_mesa rm USING(reserva_id,sucursal_id)
    WHERE rm.mesa_id=%s AND r.sucursal_id=%s AND r.estado IN ('Pendiente','Confirmada')
    AND r.reserva_id<>%s AND r.fecha_reserva+r.hora_reserva < %s
    AND r.fecha_reserva+r.hora_reserva+r.duracion_minutos*interval '1 minute'>%s""",
    (mid,branch,rid or 0,start+dt.timedelta(minutes=duration),start)).fetchone()
   require(not conflict,'Ya existe una reserva para esa mesa en ese horario.')
  seats+=mesa['capacidad']
 require(seats>=int(p['personas']),'La capacidad de las mesas es insuficiente.')
 fields=['cliente_id','sucursal_id','fecha_reserva','hora_reserva','estado','personas','duracion_minutos','observaciones']
 values=[p.get(f,90 if f=='duracion_minutos' else '') for f in fields]
 if rid:
  row=conn.execute('UPDATE reserva SET '+','.join(f'{f}=%s' for f in fields)+' WHERE reserva_id=%s RETURNING *',values+[rid]).fetchone()
  require(row,'La reserva ya no existe.')
  conn.execute('DELETE FROM reserva_mesa WHERE reserva_id=%s',(rid,))
 else:
  row=conn.execute('INSERT INTO reserva ('+','.join(fields)+') VALUES ('+','.join(['%s']*len(fields))+') RETURNING *',values).fetchone()
 for mid in tables: conn.execute('INSERT INTO reserva_mesa VALUES (%s,%s,%s)',(row['reserva_id'],mid,branch))
 return row

def movement(conn,p,user):
 require(user['rol']!='Mesero','Tu rol no puede modificar inventario.')
 qty=Decimal(str(p['cantidad'])); kind=p['tipo_movimiento']
 require(qty>0,'La cantidad debe ser mayor a cero.')
 require(kind in ['Entrada','Salida','Merma','Ajuste'],'Movimiento inválido.')
 require(str(p.get('motivo','')).strip(),'Escribe el motivo del movimiento.')
 lote=conn.execute('SELECT * FROM lote_inventario WHERE lote_id=%s FOR UPDATE',(p['lote_id'],)).fetchone()
 require(lote,'El lote no existe.')
 employee=conn.execute('SELECT empleado_id FROM empleado WHERE empleado_id=%s AND sucursal_id=%s AND estado=\'Activo\'',(p['empleado_id'],lote['sucursal_id'])).fetchone()
 require(employee,'Selecciona personal activo de esta sucursal.')
 new=qty if kind=='Ajuste' else lote['cantidad_disponible']+(qty if kind=='Entrada' else -qty)
 require(new>=0,'No hay existencias suficientes para este movimiento.')
 conn.execute('UPDATE lote_inventario SET cantidad_disponible=%s WHERE lote_id=%s',(new,p['lote_id']))
 return conn.execute('INSERT INTO movimiento_inventario(lote_id,empleado_id,tipo_movimiento,cantidad,motivo) VALUES (%s,%s,%s,%s,%s) RETURNING *',(p['lote_id'],p['empleado_id'],kind,qty,p['motivo'])).fetchone()

def record_visit(conn,p):
 row=conn.execute('INSERT INTO visita(cliente_id,sucursal_id,fecha,observaciones) VALUES (%s,%s,%s,%s) RETURNING *',(p['cliente_id'],p['sucursal_id'],p['fecha'],p.get('observaciones',''))).fetchone()
 if p.get('platillo_id'):
  price=conn.execute('SELECT precio FROM platillo WHERE platillo_id=%s',(p['platillo_id'],)).fetchone()
  require(price,'Platillo inválido.'); require(int(p['cantidad'])>0,'Cantidad inválida.')
  conn.execute('INSERT INTO venta(visita_id,platillo_id,cantidad,precio_unitario) VALUES (%s,%s,%s,%s)',(row['visita_id'],p['platillo_id'],p['cantidad'],price['precio']))
 return row

def reports(conn,p):
 start=dt.date.fromisoformat(p['desde']); end=dt.date.fromisoformat(p['hasta'])
 require(start<=end,'El rango de fechas es inválido.')
 branch=int(p.get('sucursal_id') or 0); args=(start,end,branch,branch)
 sales="fecha BETWEEN %s AND %s AND (%s=0 OR sucursal_id=%s)"
 return {
 'platos':conn.execute(f'SELECT nombre_platillo AS nombre,SUM(cantidad) AS cantidad,SUM(total) AS total FROM v_ventas WHERE {sales} GROUP BY platillo_id,nombre_platillo ORDER BY cantidad DESC,nombre LIMIT 10',args).fetchall(),
 'frecuentes':conn.execute(f"SELECT c.nombre||' '||c.apellido AS nombre,COUNT(*) AS visitas FROM visita v JOIN cliente c USING(cliente_id) WHERE {sales} GROUP BY c.cliente_id ORDER BY visitas DESC,nombre LIMIT 10",args).fetchall(),
 'preferencias':conn.execute(f"""WITH ranking AS (SELECT cliente_id,COUNT(*) reservas FROM reserva WHERE fecha_reserva BETWEEN %s AND %s AND (%s=0 OR sucursal_id=%s) AND estado<>'Cancelada' GROUP BY cliente_id ORDER BY reservas DESC,cliente_id LIMIT 5)
 SELECT c.nombre||' '||c.apellido AS nombre,r.reservas,COALESCE(string_agg(p.nombre_platillo,', '),'Sin preferencias') AS preferencias FROM ranking r JOIN cliente c USING(cliente_id) LEFT JOIN preferencia pr USING(cliente_id) LEFT JOIN platillo p USING(platillo_id) GROUP BY c.cliente_id,r.reservas ORDER BY r.reservas DESC,c.cliente_id""",args).fetchall(),
 'insumos':conn.execute("SELECT i.nombre_ingrediente AS nombre,s.nombre_sucursal,l.lote_id,l.cantidad_disponible,i.stock_minimo,l.fecha_vencimiento FROM lote_inventario l JOIN ingrediente i USING(ingrediente_id) JOIN sucursal s USING(sucursal_id) JOIN v_alertas_inventario a USING(ingrediente_id,sucursal_id) WHERE (%s=0 OR l.sucursal_id=%s) AND (a.stock_bajo OR (l.fecha_vencimiento BETWEEN %s AND %s AND l.cantidad_disponible>0)) ORDER BY l.fecha_vencimiento",(branch,branch,start,end)).fetchall(),
 'sucursales':conn.execute("""WITH r AS (SELECT sucursal_id,COUNT(*) reservas FROM reserva WHERE fecha_reserva BETWEEN %s AND %s AND estado<>'Cancelada' GROUP BY sucursal_id), v AS (SELECT sucursal_id,SUM(total) ventas FROM v_ventas WHERE fecha BETWEEN %s AND %s GROUP BY sucursal_id) SELECT s.nombre_sucursal AS nombre,COALESCE(r.reservas,0) reservas,COALESCE(v.ventas,0) ventas FROM sucursal s LEFT JOIN r USING(sucursal_id) LEFT JOIN v USING(sucursal_id) WHERE (%s=0 OR s.sucursal_id=%s) ORDER BY reservas DESC,ventas DESC""",(start,end,start,end,branch,branch)).fetchall()
 }

class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(ROOT/'static'),**kwargs)
 def send_json(self,data,status=200,cookie=None):
  raw=json.dumps(data,default=json_default,ensure_ascii=False).encode()
  self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store')
  if cookie: self.send_header('Set-Cookie',cookie)
  self.send_header('Content-Length',str(len(raw))); self.end_headers(); self.wfile.write(raw)
 def session(self):
  cookie=SimpleCookie(self.headers.get('Cookie','')); token=cookie.get('aurea_session')
  record=SESSIONS.get(token.value) if token else None
  if record and record['expires']>time.time(): return record['user']
  return None
 def do_GET(self):
  path=urlparse(self.path).path
  if path=='/api/session': return self.send_json({'mode':'postgres' if os.getenv('DATABASE_URL') else 'demo','user':self.session()})
  if path.startswith('/api/'):
   if not self.session(): return self.send_json({'error':'Inicia sesión.'},401)
   try:
    with connection() as conn:
     if path=='/api/data': return self.send_json(snapshot(conn,self.session()))
    return self.send_json({'error':'Ruta no encontrada.'},404)
   except Exception as exc:
    print(type(exc).__name__,str(exc)); return self.send_json({'error':'No se pudo leer PostgreSQL. Revisa la conexión y las migraciones.'},503)
  return super().do_GET()
 def do_POST(self):
  try:
   require(self.headers.get('Content-Type','').startswith('application/json'),'Se requiere JSON.')
   origin=self.headers.get('Origin')
   require(not origin or urlparse(origin).netloc==self.headers.get('Host'),'Origen no permitido.')
   size=int(self.headers.get('Content-Length',0)); require(0<size<=65536,'Solicitud inválida.')
   p=json.loads(self.rfile.read(size)); path=urlparse(self.path).path
   if path=='/api/logout':
    cookies=SimpleCookie(self.headers.get('Cookie','')); token=cookies.get('aurea_session')
    if token: SESSIONS.pop(token.value,None)
    return self.send_json({'ok':True},cookie='aurea_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0')
   require(bool(os.getenv('DATABASE_URL')),'Usa el acceso de demostración o configura DATABASE_URL.')
   with connection() as conn:
    if path in ['/api/login','/api/register']:
     email=p.get('correo','').strip().lower(); pwd=p.get('password','')
     require('@' in email and len(email)<=120,'Escribe un correo válido.')
     if path=='/api/register':
      require(len(pwd)>=10,'La contraseña debe tener al menos 10 caracteres.')
      require(p.get('nombre','').strip(),'Escribe tu nombre.')
      conn.execute('INSERT INTO usuario(nombre,correo,password_hash,rol) VALUES (%s,%s,%s,\'Mesero\')',(p['nombre'],email,password_hash(pwd)))
     key=(self.client_address[0],email)
     with LOCK:
      attempts=[t for t in LOGIN_ATTEMPTS.get(key,[]) if t>time.time()-300]
      require(len(attempts)<10,'Demasiados intentos. Intenta en 5 minutos.')
      LOGIN_ATTEMPTS[key]=attempts+[time.time()]
     user=conn.execute('SELECT * FROM usuario WHERE correo=%s',(email,)).fetchone()
     require(user and check_password(pwd,user['password_hash']),'Correo o contraseña incorrectos.')
     user.pop('password_hash'); token=secrets.token_urlsafe(32)
     SESSIONS[token]={'user':user,'expires':time.time()+28800}
     with LOCK: LOGIN_ATTEMPTS.pop(key,None)
     conn.commit()
     return self.send_json({'user':user},cookie=f'aurea_session={token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800')
    user=self.session()
    if not user: return self.send_json({'error':'Tu sesión terminó. Inicia sesión.'},401)
    actor(conn,user)
    if path=='/api/entity': result=save_entity(conn,p['entity'],p['data'],p.get('id'),user)
    elif path=='/api/reservation': result=save_reservation(conn,p,user)
    elif path=='/api/movement': result=movement(conn,p,user)
    elif path=='/api/visit': result=record_visit(conn,p)
    elif path=='/api/preference':
     if p.get('remove'): conn.execute('DELETE FROM preferencia WHERE cliente_id=%s AND platillo_id=%s',(p['cliente_id'],p['platillo_id']))
     else: conn.execute('INSERT INTO preferencia VALUES (%s,%s) ON CONFLICT DO NOTHING',(p['cliente_id'],p['platillo_id']))
     result={'ok':True}
    elif path=='/api/delete':
     require(user['rol']=='Administrador','Se requiere administrador para eliminar.')
     key=p['entity']; require(key in ENTITIES,'Módulo desconocido.')
     table,pk,_=ENTITIES[key]; where=f'{pk}=%s'; values=[p['id']]
     if key=='mesas': where+=' AND sucursal_id=%s'; values.append(p['sucursal_id'])
     require(conn.execute(f'DELETE FROM {table} WHERE {where} RETURNING {pk}',values).fetchone(),'El registro ya no existe.')
     result={'ok':True}
    elif path=='/api/reports':
     require(user['rol']=='Administrador','Reportes disponibles para administradores.')
     result=reports(conn,p)
    else: return self.send_json({'error':'Ruta no encontrada.'},404)
    conn.commit(); return self.send_json(result)
  except (ValidationError,KeyError,ValueError,ArithmeticError,json.JSONDecodeError) as exc: return self.send_json({'error':str(exc) or 'Revisa los datos del formulario.'},400)
  except Exception as exc:
   print(type(exc).__name__,str(exc))
   code=getattr(exc,'sqlstate','')
   message={'23503':'Este registro tiene relaciones o una referencia inválida. Revisa los datos relacionados.','23505':'Ya existe un registro con esos datos.','23514':'Los datos no cumplen las restricciones.','22001':'Uno de los campos supera la longitud permitida.'}.get(code,'No se pudo completar la operación. Revisa la conexión con PostgreSQL.')
   return self.send_json({'error':message},409 if code in ['23503','23505'] else 400)

def initialize(seed=False):
 with connection() as conn:
  # Base installation is explicit and only valid for a new, empty database.
  if not conn.execute("SELECT to_regclass('public.cliente') AS name").fetchone()['name']:
   sql=(ROOT/'db/001_base.sql').read_text(encoding='utf-8')
   sql='\n'.join(line for line in sql.splitlines() if not line.startswith('\\'))
   conn.execute(sql,prepare=False)
  conn.commit()
  conn.execute('SET search_path TO public')
  conn.execute((ROOT/'db/002_aplicacion.sql').read_text(encoding='utf-8'),prepare=False)
 if seed:
  from seed import seed_data
  seed_data()

if __name__=='__main__':
 parser=argparse.ArgumentParser(); parser.add_argument('--init-db',action='store_true'); parser.add_argument('--seed',action='store_true'); args=parser.parse_args()
 if args.init_db or args.seed:
  require(bool(os.getenv('DATABASE_URL')),'Configura DATABASE_URL primero.')
  initialize(args.seed)
 else:
  port=int(os.getenv('PORT','8000')); print(f'Áurea: http://localhost:{port} | '+('PostgreSQL' if os.getenv('DATABASE_URL') else 'Demostración'),flush=True)
  ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()
