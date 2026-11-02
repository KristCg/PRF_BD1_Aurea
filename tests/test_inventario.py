"""Pruebas de integración en una BD temporal, sin tocar datos de la aplicación."""
import os
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo

sys.path.insert(0, '/app')
from app import app, connect


class InventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original_url = os.environ['DATABASE_URL']
        cls.database = 'inventario_test_' + uuid4().hex
        with psycopg.connect(cls.original_url, autocommit=True) as conn:
            conn.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(cls.database)))
        settings = conninfo_to_dict(cls.original_url)
        settings['dbname'] = cls.database
        os.environ['DATABASE_URL'] = make_conninfo(**settings)
        with connect() as conn:
            conn.execute(Path('/schema/01_schema.sql').read_text(encoding='utf-8'))
            conn.execute(Path('/schema/02_seed.sql').read_text(encoding='utf-8'))
        app.config['TESTING'] = True

    @classmethod
    def tearDownClass(cls):
        os.environ['DATABASE_URL'] = cls.original_url
        with psycopg.connect(cls.original_url, autocommit=True) as conn:
            conn.execute(sql.SQL('DROP DATABASE {} WITH (FORCE)').format(sql.Identifier(cls.database)))

    def setUp(self):
        self.client = app.test_client()

    def new_item(self, minimum='1', reference='10', unit='kg'):
        data = dict(nombre_ingrediente='Prueba '+uuid4().hex[:10],categoria='Despensa',
                    unidad_medida=unit,stock_minimo=minimum,stock_referencia=reference)
        res = self.client.post('/api/insumos', json=data)
        self.assertEqual(res.status_code, 201, res.json)
        return res.json['ingrediente_id'], data

    def new_lot(self, quantity='5', expires=20, item=None, branch=1):
        if item is None:
            item, _ = self.new_item()
        code = 'TEST-' + uuid4().hex[:18]
        data = dict(lote_id=code,ingrediente_id=item,sucursal_id=branch,
                    cantidad=quantity,fecha_vencimiento=(date.today()+timedelta(days=expires)).isoformat(),
                    responsable='Prueba',motivo='Recepción de prueba')
        res = self.client.post('/api/lotes',json=data)
        self.assertEqual(res.status_code,201,res.json)
        return code,item

    def move(self, lot, kind, quantity, client=None):
        return (client or self.client).post('/api/movimientos',json=dict(
            lote_id=lot,tipo_movimiento=kind,cantidad=quantity,responsable='Prueba',motivo='Verificación'))

    def stock(self, lot):
        with connect() as conn:
            return conn.execute('SELECT cantidad_disponible FROM lote_inventario WHERE lote_id=%s',(lot,)).fetchone()['cantidad_disponible']

    def item_stock(self, item, branch=1):
        res = self.client.get(f'/api/inventario?sucursal_id={branch}')
        self.assertEqual(res.status_code,200,res.json)
        return next(i for i in res.json['insumos'] if i['ingrediente_id']==item)

    def test_health_and_assets(self):
        for path in ('/','/app.js','/styles.css','/favicon.svg','/api/health'):
            with self.client.get(path) as res:
                self.assertEqual(res.status_code,200,path)

    def test_initial_low_stock_and_expiring_data(self):
        data=self.client.get('/api/inventario').json
        self.assertTrue(any(i['stock_bajo'] for i in data['insumos']))
        self.assertTrue(any(i['lotes_por_vencer']>0 for i in data['insumos']))
        self.assertTrue(all('ingrediente_id' in m for m in data['movimientos']))

    def test_create_edit_delete_unused_ingredient(self):
        item,data=self.new_item()
        data['nombre_ingrediente']='Editado '+uuid4().hex[:10]
        self.assertEqual(self.client.put(f'/api/insumos/{item}',json=data).status_code,200)
        self.assertEqual(self.item_stock(item)['nombre_ingrediente'],data['nombre_ingrediente'])
        self.assertEqual(self.client.delete(f'/api/insumos/{item}').status_code,200)
        with connect() as conn:
            operations=conn.execute("SELECT operacion FROM cambio_inventario WHERE tabla='ingrediente' AND COALESCE(nuevo,anterior)->>'ingrediente_id'=%s ORDER BY cambio_id",(str(item),)).fetchall()
        self.assertEqual([o['operacion'] for o in operations],['INSERT','UPDATE','DELETE'])

    def test_duplicate_names_are_case_insensitive(self):
        _,data=self.new_item()
        data['nombre_ingrediente']=' '+data['nombre_ingrediente'].upper()+' '
        self.assertEqual(self.client.post('/api/insumos',json=data).status_code,409)

    def test_receipt_and_decimal_movements(self):
        lot,_=self.new_lot('5.125')
        self.assertEqual(self.move(lot,'Salida','1.015').status_code,201)
        self.assertEqual(self.move(lot,'Entrada','0.100').status_code,201)
        self.assertEqual(self.move(lot,'Merma','0.010').status_code,201)
        self.assertEqual(self.stock(lot),Decimal('4.200'))

    def test_insufficient_stock_rolls_back(self):
        lot,_=self.new_lot('2')
        self.assertEqual(self.move(lot,'Salida','2.001').status_code,409)
        self.assertEqual(self.stock(lot),Decimal('2'))
        with connect() as conn:
            count=conn.execute('SELECT count(*) AS n FROM movimiento_inventario WHERE lote_id=%s',(lot,)).fetchone()['n']
        self.assertEqual(count,1)

    def test_physical_count_sets_absolute_balance(self):
        lot,_=self.new_lot('5')
        self.assertEqual(self.move(lot,'Ajuste','3.4').status_code,201)
        self.assertEqual(self.stock(lot),Decimal('3.4'))
        self.assertEqual(self.move(lot,'Ajuste','3.4').status_code,409)
        self.assertEqual(self.move(lot,'Ajuste','0').status_code,201)
        self.assertEqual(self.stock(lot),0)

    def test_threshold_includes_fifteen_percent(self):
        item,_=self.new_item('5','100')
        lot,_=self.new_lot('15',item=item)
        self.assertTrue(self.item_stock(item)['stock_bajo'])
        self.assertEqual(self.move(lot,'Entrada','0.001').status_code,201)
        self.assertFalse(self.item_stock(item)['stock_bajo'])

    def test_minimum_can_exceed_fifteen_percent(self):
        item,_=self.new_item('20','100')
        self.new_lot('19',item=item)
        self.assertTrue(self.item_stock(item)['stock_bajo'])
        self.assertEqual(Decimal(self.item_stock(item)['umbral_alerta']),20)

    def test_expiry_window_includes_today_and_day_seven(self):
        item,_=self.new_item()
        self.new_lot('1',expires=0,item=item)
        self.new_lot('1',expires=7,item=item)
        self.new_lot('1',expires=8,item=item)
        self.assertEqual(self.item_stock(item)['lotes_por_vencer'],2)

    def test_expired_lots_excluded_and_only_reductions_allowed(self):
        lot,item=self.new_lot('5')
        with connect() as conn:
            conn.execute('UPDATE lote_inventario SET fecha_ingreso=CURRENT_DATE-2,fecha_vencimiento=CURRENT_DATE-1 WHERE lote_id=%s',(lot,))
        record=self.item_stock(item)
        self.assertEqual(Decimal(record['stock_actual']),0)
        self.assertEqual(Decimal(record['stock_vencido']),5)
        for kind,qty in [('Salida','1'),('Entrada','1'),('Ajuste','6')]:
            self.assertEqual(self.move(lot,kind,qty).status_code,409)
        self.assertEqual(self.move(lot,'Merma','2').status_code,201)
        self.assertEqual(self.move(lot,'Ajuste','0').status_code,201)

    def test_lots_keep_history_and_unit(self):
        item,data=self.new_item()
        self.new_lot(item=item,branch=2)
        self.assertEqual(self.client.delete(f'/api/insumos/{item}').status_code,409)
        data['unidad_medida']='g'
        self.assertEqual(self.client.put(f'/api/insumos/{item}',json=data).status_code,400)

    def test_branch_balances_are_isolated(self):
        item,_=self.new_item()
        self.new_lot('5',item=item,branch=1)
        self.new_lot('8',item=item,branch=2)
        self.assertEqual(Decimal(self.item_stock(item,1)['stock_actual']),5)
        self.assertEqual(Decimal(self.item_stock(item,2)['stock_actual']),8)

    def test_rejects_bad_values(self):
        lot,_=self.new_lot()
        for value in ('NaN','Infinity','-1','0','0.0001',True,None,'1000000000'):
            self.assertEqual(self.move(lot,'Entrada',value).status_code,400,str(value))
        self.assertEqual(self.client.post('/api/insumos',json=[]).status_code,400)
        self.assertEqual(self.client.get('/api/inventario?sucursal_id=999').status_code,400)

    def test_receipt_is_atomic_on_invalid_responsible(self):
        item,_=self.new_item()
        code='INVALID-'+uuid4().hex[:12]
        res=self.client.post('/api/lotes',json=dict(lote_id=code,ingrediente_id=item,sucursal_id=1,cantidad='2',
             fecha_vencimiento=date.today().isoformat(),responsable=' ',motivo='Prueba'))
        self.assertEqual(res.status_code,400)
        with connect() as conn:
            self.assertIsNone(conn.execute('SELECT 1 FROM lote_inventario WHERE lote_id=%s',(code,)).fetchone())

    def test_concurrent_withdrawals_cannot_overdraw(self):
        lot,_=self.new_lot('5')
        def withdraw(_):
            with app.test_client() as client:
                return self.move(lot,'Salida','4',client).status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(withdraw,range(2)))
        self.assertEqual(sorted(results),[201,409])
        self.assertEqual(self.stock(lot),1)


if __name__=='__main__':
    unittest.main(verbosity=2)
