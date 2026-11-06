"""Pruebas transaccionales: usar exclusivamente una base PostgreSQL de pruebas."""
import datetime as dt
import os
import unittest
from decimal import Decimal
import server

@unittest.skipUnless(os.getenv('AUREA_TEST_DATABASE_URL'),'Configura AUREA_TEST_DATABASE_URL con una base aislada y cargada.')
class DatabaseTests(unittest.TestCase):
 def setUp(self):
  os.environ['DATABASE_URL']=os.environ['AUREA_TEST_DATABASE_URL']
  self.conn=server.connection()
  self.user={'correo':'integration@test.local','rol':'Administrador'}
  server.actor(self.conn,self.user)
  self.client=self.conn.execute('SELECT cliente_id FROM cliente ORDER BY cliente_id LIMIT 1').fetchone()['cliente_id']
  self.table=self.conn.execute("SELECT * FROM mesa WHERE estado='Disponible' ORDER BY sucursal_id,mesa_id LIMIT 1").fetchone()
 def tearDown(self):
  self.conn.rollback();self.conn.close()
 def reservation(self,**kwargs):
  p={'cliente_id':self.client,'sucursal_id':self.table['sucursal_id'],'fecha_reserva':(dt.date.today()+dt.timedelta(days=90)).isoformat(),'hora_reserva':'12:00','estado':'Confirmada','personas':2,'duracion_min':90,'observaciones':'Prueba','mesas':[self.table['mesa_id']]}
  p.update(kwargs);return p
 def test_reservation_overlap_and_adjacent_interval(self):
  first=server.save_reservation(self.conn,self.reservation(),self.user)
  self.assertTrue(first['reserva_id'])
  with self.assertRaisesRegex(server.ValidationError,'Ya existe'):
   server.save_reservation(self.conn,self.reservation(hora_reserva='13:00'),self.user)
  adjacent=server.save_reservation(self.conn,self.reservation(hora_reserva='13:30'),self.user)
  self.assertNotEqual(first['reserva_id'],adjacent['reserva_id'])
 def test_reservation_capacity_and_cancellation(self):
  with self.assertRaisesRegex(server.ValidationError,'capacidad'):
   server.save_reservation(self.conn,self.reservation(personas=999),self.user)
  r=server.save_reservation(self.conn,self.reservation(),self.user)
  server.save_reservation(self.conn,self.reservation(reserva_id=r['reserva_id'],estado='Cancelada'),self.user)
  server.save_reservation(self.conn,self.reservation(),self.user)
 def test_inventory_balance_and_actor_audit(self):
  lot=self.conn.execute('SELECT * FROM lote_inventario WHERE sucursal_id=%s ORDER BY lote_id LIMIT 1',(self.table['sucursal_id'],)).fetchone()
  employee=self.conn.execute("SELECT empleado_id FROM empleado WHERE sucursal_id=%s AND estado='Activo' LIMIT 1",(lot['sucursal_id'],)).fetchone()['empleado_id']
  p={'lote_id':lot['lote_id'],'empleado_id':employee,'cantidad':str(lot['cantidad_disponible']+1),'tipo_movimiento':'Salida','motivo':'Prueba'}
  with self.assertRaisesRegex(server.ValidationError,'suficientes'):server.movement(self.conn,p,self.user)
  p.update(cantidad='.125',tipo_movimiento='Entrada')
  server.movement(self.conn,p,self.user)
  stock=self.conn.execute('SELECT cantidad_disponible FROM lote_inventario WHERE lote_id=%s',(lot['lote_id'],)).fetchone()['cantidad_disponible']
  self.assertEqual(stock,lot['cantidad_disponible']+Decimal('.125'))
  row=self.conn.execute("SELECT * FROM bitacora WHERE usuario=%s AND tabla='lote_inventario' ORDER BY bitacora_id DESC LIMIT 1",(self.user['correo'],)).fetchone()
  self.assertEqual(row['operacion'],'UPDATE');self.assertIsNotNone(row['anterior']);self.assertIsNotNone(row['nuevo'])
 def order(self, **kwargs):
  employee=self.conn.execute("SELECT empleado_id FROM empleado WHERE sucursal_id=%s AND estado='Activo' LIMIT 1",(self.table['sucursal_id'],)).fetchone()['empleado_id']
  dishes=self.conn.execute('SELECT platillo_id FROM platillo ORDER BY platillo_id LIMIT 2').fetchall()
  p={'sucursal_id':self.table['sucursal_id'],'empleado_id':employee,'cliente_id':self.client,'observaciones':'Pedido de prueba',
   'items':[{'platillo_id':d['platillo_id'],'cantidad':i+1,'precio_unitario':0,'observaciones':'Sin azúcar'} for i,d in enumerate(dishes)]}
  p.update(kwargs);return p
 def test_order_completion_records_sales_once_with_server_prices(self):
  payload=self.order()
  row=server.save_order(self.conn,payload,self.user)
  self.assertEqual(row['estado'],'Pendiente')
  self.assertIsNone(row['visita_id'])
  total=self.conn.execute('SELECT sum(d.cantidad*p.precio) AS total FROM detalle_orden d JOIN platillo p USING(platillo_id) WHERE orden_id=%s',(row['orden_id'],)).fetchone()['total']
  done=server.change_order_state(self.conn,{'orden_id':row['orden_id'],'estado':'Completada'},self.user)
  again=server.change_order_state(self.conn,{'orden_id':row['orden_id'],'estado':'Completada'},self.user)
  self.assertEqual(done['visita_id'],again['visita_id'])
  sales=self.conn.execute('SELECT count(*) AS n,sum(cantidad*precio_unitario) AS total FROM venta WHERE visita_id=%s',(done['visita_id'],)).fetchone()
  self.assertEqual(sales['n'],2);self.assertEqual(sales['total'],total)
  invoice=self.conn.execute('SELECT total FROM factura WHERE orden_id=%s',(row['orden_id'],)).fetchone()
  self.assertEqual(invoice['total'],total)
  self.assertTrue(self.conn.execute("SELECT 1 FROM movimiento_inventario WHERE motivo=%s",('Consumo por orden #'+str(row['orden_id']),)).fetchone())
  with self.assertRaisesRegex(server.ValidationError,'cerrada'):
   server.change_order_state(self.conn,{'orden_id':row['orden_id'],'estado':'Cancelada'},self.user)
  with self.assertRaisesRegex(server.ValidationError,'pendientes'):
   server.save_order(self.conn,{**payload,'orden_id':row['orden_id']},self.user)
 def test_guest_order_and_cancellation(self):
  row=server.save_order(self.conn,self.order(cliente_id=None),self.user)
  done=server.change_order_state(self.conn,{'orden_id':row['orden_id'],'estado':'Completada'},self.user)
  visit=self.conn.execute('SELECT cliente_id FROM visita WHERE visita_id=%s',(done['visita_id'],)).fetchone()
  self.assertIsNone(visit['cliente_id'])
  other=server.save_order(self.conn,self.order(),self.user)
  cancelled=server.change_order_state(self.conn,{'orden_id':other['orden_id'],'estado':'Cancelada'},self.user)
  self.assertIsNone(cancelled['visita_id'])
 def test_order_validation_and_waiter_ownership(self):
  p=self.order();dish=p['items'][0]['platillo_id']
  for items in [[],[{'platillo_id':dish,'cantidad':0}],[{'platillo_id':dish,'cantidad':1.5}],[{'platillo_id':dish,'cantidad':1}]*2]:
   with self.assertRaises(server.ValidationError):server.save_order(self.conn,{**p,'items':items},self.user)
  row=server.save_order(self.conn,p,self.user)
  outsider={'rol':'Mesero','empleado_id':-1}
  with self.assertRaisesRegex(server.ValidationError,'propias'):
   server.change_order_state(self.conn,{'orden_id':row['orden_id'],'estado':'Completada'},outsider)
  with self.assertRaisesRegex(server.ValidationError,'vinculado'):
   server.save_order(self.conn,p,outsider)
  p['empleado_id']=-1
  with self.assertRaisesRegex(server.ValidationError,'personal activo'):server.save_order(self.conn,p,self.user)
 def test_order_edit_preserves_quoted_price_and_replaces_items(self):
  p=self.order();row=server.save_order(self.conn,p,self.user)
  dish=p['items'][0]['platillo_id']
  original=self.conn.execute('SELECT precio_unitario FROM detalle_orden WHERE orden_id=%s AND platillo_id=%s',(row['orden_id'],dish)).fetchone()['precio_unitario']
  self.conn.execute('UPDATE platillo SET precio=precio+1 WHERE platillo_id=%s',(dish,))
  server.save_order(self.conn,{**p,'orden_id':row['orden_id'],'items':[{'platillo_id':dish,'cantidad':3}]},self.user)
  lines=self.conn.execute('SELECT * FROM detalle_orden WHERE orden_id=%s',(row['orden_id'],)).fetchall()
  self.assertEqual(len(lines),1);self.assertEqual(lines[0]['cantidad'],3);self.assertEqual(lines[0]['precio_unitario'],original)
 def test_official_catalog_and_expired_stock(self):
  self.assertEqual(self.conn.execute('SELECT count(*) n FROM ingrediente').fetchone()['n'],31)
  self.assertEqual(self.conn.execute('SELECT count(*) n FROM platillo').fetchone()['n'],21)
  pasta=self.conn.execute('SELECT nombre_platillo,precio FROM platillo WHERE platillo_id=2').fetchone()
  self.assertEqual(pasta['nombre_platillo'],'Pasta Alfredo con Pollo')
  self.assertEqual(pasta['precio'],Decimal('80.00'))
  stock=self.conn.execute('SELECT * FROM existencias WHERE ingrediente_id=4 AND sucursal_id=1').fetchone()
  lots=self.conn.execute('SELECT sum(cantidad_disponible) total FROM lote_inventario WHERE ingrediente_id=4 AND sucursal_id=1 AND fecha_vencimiento>=CURRENT_DATE').fetchone()
  self.assertEqual(stock['stock_actual'],lots['total'])
  self.assertGreater(stock['stock_vencido'],0)
 def test_insufficient_recipe_stock_rolls_back_completion(self):
  row=server.save_order(self.conn,self.order(),self.user)
  self.conn.execute("UPDATE lote_inventario SET cantidad_disponible=0 WHERE ingrediente_id=1 AND sucursal_id=%s",(row['sucursal_id'],))
  with self.assertRaisesRegex(Exception,'suficiente'):
   with self.conn.transaction():
    server.change_order_state(self.conn,{'orden_id':row['orden_id'],'estado':'Completada'},self.user)
  order=self.conn.execute('SELECT estado FROM orden WHERE orden_id=%s',(row['orden_id'],)).fetchone()
  self.assertEqual(order['estado'],'Pendiente')
  self.assertIsNone(self.conn.execute('SELECT 1 FROM factura WHERE orden_id=%s',(row['orden_id'],)).fetchone())
 def test_reports_totals_and_limits(self):
  result=server.reports(self.conn,{'desde':'2000-01-01','hasta':'2100-12-31','sucursal_id':0})
  self.assertEqual(set(result),{'platos','frecuentes','preferencias','insumos','sucursales'})
  self.assertLessEqual(len(result['platos']),10);self.assertLessEqual(len(result['preferencias']),5)
  total=self.conn.execute('SELECT SUM(total) total FROM v_ventas').fetchone()['total']
  self.assertEqual(sum(r['ventas'] for r in result['sucursales']),total)
 def test_permissions_and_password_hash(self):
  with self.assertRaisesRegex(server.ValidationError,'rol'):
   server.save_entity(self.conn,'ingredientes',{'nombre_ingrediente':'No permitido'},None,{'rol':'Mesero'})
  self.assertEqual(server.snapshot(self.conn,{'rol':'Mesero'})['bitacora'],[])
  hashed=server.password_hash('Una clave de prueba')
  self.assertTrue(server.check_password('Una clave de prueba',hashed))
  self.assertFalse(server.check_password('Incorrecta',hashed))
 def test_delete_audit_and_password_redaction(self):
  row=server.save_entity(self.conn,'clientes',{'nombre':'Temporal','apellido':'Prueba','telefono':'12345678','nit':'CF'},None,self.user)
  self.conn.execute('DELETE FROM cliente WHERE cliente_id=%s',(row['cliente_id'],))
  audit=self.conn.execute("SELECT * FROM bitacora WHERE tabla='cliente' AND operacion='DELETE' AND usuario=%s ORDER BY bitacora_id DESC LIMIT 1",(self.user['correo'],)).fetchone()
  self.assertEqual(audit['anterior']['cliente_id'],row['cliente_id']);self.assertIsNone(audit['nuevo'])
  self.conn.execute("INSERT INTO usuario(nombre,correo,password_hash,rol) VALUES ('Test','redaction@test.local','secret','Mesero')")
  audit=self.conn.execute("SELECT nuevo FROM bitacora WHERE tabla='usuario' AND usuario=%s ORDER BY bitacora_id DESC LIMIT 1",(self.user['correo'],)).fetchone()
  self.assertNotIn('password_hash',audit['nuevo'])

if __name__=='__main__':unittest.main()
