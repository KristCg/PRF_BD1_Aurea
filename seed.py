"""Carga reproducible de datos ficticios: python server.py --seed."""
import datetime as dt
import os
from server import actor, connection, password_hash, require, save_user

def seed_data():
 password=os.getenv('AUREA_ADMIN_PASSWORD','')
 require(len(password)>=4,'Define AUREA_ADMIN_PASSWORD con al menos 4 caracteres.')
 today=dt.date.today()
 with connection() as conn:
  for table in ['cliente','usuario','sucursal','rol','ingrediente','platillo']:
   require(conn.execute(f'SELECT COUNT(*) AS n FROM {table}').fetchone()['n']==0,f'La carga exige tablas vacías: {table} contiene datos. No se modificaron.')
  for role in ['Gerente','Mesero','Administrador','Encargado de Inventario']: conn.execute('INSERT INTO rol(rol) VALUES (%s)',(role,))
  branches=[]
  for name,address,capacity in [('Zona 10','12 calle 4-35, zona 10, Guatemala',80),('Cayalá','Paseo Cayalá, zona 16, Guatemala',60)]:
   branches.append(conn.execute('INSERT INTO sucursal(nombre_sucursal,telefono,dirreccion,capacidad) VALUES (%s,%s,%s,%s) RETURNING sucursal_id',(name,'2334-5678',address,capacity)).fetchone()['sucursal_id'])
  roles={r['rol']:r['rol_id'] for r in conn.execute('SELECT * FROM rol')}
  employees=[]
  for name,last,role,branch in [('Maya','Salazar','Gerente',branches[0]),('Daniel','Pérez','Mesero',branches[0]),('Ana','Luna','Encargado de Inventario',branches[1])]:
   employees.append(conn.execute('INSERT INTO empleado(nombre_empleado,apellido,rol_id,sucursal_id) VALUES (%s,%s,%s,%s) RETURNING empleado_id',(name,last,roles[role],branch)).fetchone()['empleado_id'])
  admin=conn.execute('INSERT INTO usuario(nombre,correo,password_hash,rol,empleado_id) VALUES (%s,%s,%s,%s,%s) RETURNING usuario_id,correo,rol',('Maya Salazar',os.getenv('AUREA_ADMIN_EMAIL','admin@aurea.gt').lower(),password_hash(password),'Administrador',employees[0])).fetchone()
  actor(conn,admin)
  for name,email,role,employee in [('Maya Salazar','gerente@aurea.gt','Gerente',employees[0]),('Daniel Pérez','mesero@aurea.gt','Mesero',employees[1])]:
   save_user(conn,{'nombre':name,'correo':email,'rol':role,'empleado_id':employee,'password':'1234'},admin)
  for b in branches:
   for i in range(1,13 if b==branches[0] else 9): conn.execute('INSERT INTO mesa VALUES (%s,%s,%s,%s)',(i,b,6 if i%3==1 else 4,'Ocupada' if i%4==1 else 'Disponible'))
  clients=[]
  for i,(name,last) in enumerate([('Valeria','Torres'),('Diego','Ramírez'),('Sofía','Méndez'),('Carlos','Herrera'),('Lucía','Gómez'),('Mariana','López'),('Andrés','Castillo'),('Isabella','Fuentes'),('Javier','Morales'),('Camila','Rivas')]):
   clients.append(conn.execute('INSERT INTO cliente(nit,nombre,apellido,telefono) VALUES (%s,%s,%s,%s) RETURNING cliente_id',('CF',name,last,str(50234567+i))).fetchone()['cliente_id'])
  dishes=[]
  for name,price,category in [('Pasta Alfredo con pollo',65,'Pastas'),('Cappuccino de la casa',24,'Café'),('Croissant de almendra',28,'Panadería'),('Ensalada Áurea',48,'Ensaladas'),('Sándwich de pollo',45,'Sándwiches'),('Cheesecake de frutos rojos',32,'Postres'),('Latte de vainilla',27,'Café'),('Tostadas de aguacate',38,'Desayunos')]:
   dishes.append(conn.execute('INSERT INTO platillo(nombre_platillo,precio,categoria) VALUES (%s,%s,%s) RETURNING *',(name,price,category)).fetchone())
  source=[('Pechuga de pollo','kg',5,2),('Crema','L',2,.5),('Champiñones','kg',3,1),('Café en grano','kg',2,8),('Leche','L',5,18),('Pasta','kg',3,12),('Queso parmesano','kg',1,4),('Harina','kg',3,15),('Aguacate','ud',10,30),('Pan artesanal','ud',8,24),('Frutos rojos','kg',1,5),('Azúcar','kg',2,10)]
  ingredients=[]
  for i,(name,unit,minimum,qty) in enumerate(source):
   ing=conn.execute('INSERT INTO ingrediente(nombre_ingrediente,unidad_medida,stock_minimo) VALUES (%s,%s,%s) RETURNING ingrediente_id',(name,unit,minimum)).fetchone()['ingrediente_id'];ingredients.append(ing)
   for j,b in enumerate(branches): conn.execute('INSERT INTO lote_inventario VALUES (%s,%s,%s,%s,%s,%s)',(f'S{j+1}-L{i+1:03}',ing,b,today-dt.timedelta(days=5),today+dt.timedelta(days=3 if i==1 else 20+i),qty+(3 if j else 0)))
  for ingredient,qty in [(0,.15),(1,.05),(2,.06),(5,.15),(6,.03)]: conn.execute('INSERT INTO detalle_receta VALUES (%s,%s,%s,%s)',(dishes[0]['platillo_id'],ingredients[ingredient],qty,source[ingredient][1]))
  for i,c in enumerate(clients):
   row=conn.execute('INSERT INTO reserva(cliente_id,sucursal_id,fecha_reserva,hora_reserva,estado,personas) VALUES (%s,%s,%s,%s,%s,%s) RETURNING reserva_id',(c,branches[0],today,['10:00','11:30','13:00','14:30','19:00','15:00','16:30','18:00','19:30','20:00'][i],'Pendiente' if i in [2,4] else 'Confirmada',4 if i%3==0 else 2)).fetchone()
   conn.execute('INSERT INTO reserva_mesa VALUES (%s,%s,%s)',(row['reserva_id'],[2,4,6,8,10,12,2,4,6,8][i],branches[0]))
  for i in range(63):
   visit=conn.execute('INSERT INTO visita(cliente_id,sucursal_id,fecha,observaciones) VALUES (%s,%s,%s,%s) RETURNING visita_id',(clients[i%10],branches[1] if i%4==0 else branches[0],today-dt.timedelta(days=i//9),'Prefiere una mesa tranquila junto a la ventana.' if i%5==0 else 'Excelente atención.')).fetchone()
   dish=dishes[i%8];conn.execute('INSERT INTO venta(visita_id,platillo_id,cantidad,precio_unitario) VALUES (%s,%s,%s,%s)',(visit['visita_id'],dish['platillo_id'],i%3+1,dish['precio']))
  for c,p in [(clients[0],dishes[0]['platillo_id']),(clients[0],dishes[1]['platillo_id']),(clients[2],dishes[3]['platillo_id'])]: conn.execute('INSERT INTO preferencia VALUES (%s,%s)',(c,p))
 print('Datos ficticios cargados. Administrador:',os.getenv('AUREA_ADMIN_EMAIL','admin@aurea.gt'))
