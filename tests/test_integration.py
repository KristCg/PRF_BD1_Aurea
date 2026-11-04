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
  p={'cliente_id':self.client,'sucursal_id':self.table['sucursal_id'],'fecha_reserva':(dt.date.today()+dt.timedelta(days=90)).isoformat(),'hora_reserva':'12:00','estado':'Confirmada','personas':2,'duracion_minutos':90,'observaciones':'Prueba','mesas':[self.table['mesa_id']]}
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
