// Verifica lógica y generación de pantallas sin automatizar un navegador.
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const nodes=new Map();
const node=s=>{if(!nodes.has(s))nodes.set(s,{innerHTML:'',textContent:'',value:'1',classList:{add(){},remove(){},toggle(){}},addEventListener(){},showModal(){},close(){},focus(){},setSelectionRange(){}});return nodes.get(s)};
const context=vm.createContext({document:{querySelector:node,querySelectorAll:()=>[],addEventListener(){}},window:{scrollTo(){}},fetch:async()=>({ok:true,json:async()=>({mode:'demo',user:null})}),Intl,Date,console,setTimeout:()=>0,clearTimeout(){},localStorage:{setItem(){},getItem(){return null}},URL,Blob,TextEncoder});
vm.runInContext(fs.readFileSync('static/app.js','utf8'),context);
vm.runInContext("state.user={usuario_id:1,nombre:'Maya Salazar',correo:'admin@aurea.gt',rol:'Administrador'};state.mode='demo';state.data=demoData();state.branch=1",context);
for(const page of ['inicio','reservas','ordenes','mesas','clientes','platillos','inventario','personal','usuarios','sucursales','bitacora','reportes','buscar']){
 vm.runInContext(`state.page='${page}';state.report=demoReports();render()`,context);
 const html=node('#app').innerHTML;
 assert(html.length>1000,page+' debe generar contenido');
 assert(!html.includes('undefined'),page+' contiene undefined');
 assert(!html.includes('NaN'),page+' contiene NaN');
 assert(!html.includes('Invalid Date'),page+' tiene fecha inválida');
}
vm.runInContext(`
 if(alerts().length!==3)throw Error('Se esperan 3 alertas en Zona 10');
 const report=demoReports();
 const total=branchRows('ventas').filter(v=>v.fecha>=state.reportFrom&&v.fecha<=state.reportTo).reduce((n,v)=>n+v.total,0);
 if(report.sucursales.reduce((n,v)=>n+v.ventas,0)!==total)throw Error('Totales inconsistentes');
 const p={cliente_id:1,sucursal_id:1,fecha_reserva:today(),hora_reserva:'10:00',estado:'Confirmada',personas:2,duracion_minutos:90,mesas:[2]};
 let overlap=false;try{validateDemoReservation(p)}catch(e){overlap=e.message.includes('Ya existe')}
 if(!overlap)throw Error('La demo debe rechazar cruces');
 let seats=false;try{validateDemoReservation({...p,fecha_reserva:offsetDate(10),personas:99})}catch(e){seats=e.message.includes('capacidad')}
 if(!seats)throw Error('La demo debe validar capacidad');
 const payload={sucursal_id:1,empleado_id:1,cliente_id:1,reserva_id:null,observaciones:'Sin prisa',items:[{platillo_id:1,cantidad:2,precio_unitario:0},{platillo_id:2,cantidad:1}]};
 const order=saveDemoOrder(payload);
 if(orderTotal(order.orden_id)!==154)throw Error('La orden debe usar los precios del menú');
 const beforeSales=records('ventas').length;
 changeDemoOrderState(order.orden_id,'Completada');changeDemoOrderState(order.orden_id,'Completada');
 if(records('ventas').length!==beforeSales+2)throw Error('La orden debe registrar ventas una sola vez');
 let closed=false;try{saveDemoOrder({...payload,orden_id:order.orden_id})}catch{closed=true}
 if(!closed)throw Error('No se puede editar una orden completada');
 let duplicate=false;try{saveDemoOrder({...payload,items:[payload.items[0],payload.items[0]]})}catch{duplicate=true}
 if(!duplicate)throw Error('No se pueden repetir platillos');
 const cancelled=saveDemoOrder(payload);changeDemoOrderState(cancelled.orden_id,'Cancelada');
 if(records('ventas').length!==beforeSales+2)throw Error('Cancelar no debe generar ventas');
 state.page='ordenes';state.filter='';state.query='';render();
 if(!document.querySelector('#app').innerHTML.includes('154.00')||!document.querySelector('#app').innerHTML.includes('Completada'))throw Error('Las órdenes deben mostrar total y estado');
 orderDetail(order.orden_id);
 if(!document.querySelector('#modal').innerHTML.includes('Sin prisa'))throw Error('El detalle debe mostrar las observaciones');
 state.user.rol='Mesero';
 state.user.empleado_id=2;
 if(!allowed('ordenes')||!canEdit('ordenes')||orderEditable(cancelled))throw Error('Permisos de órdenes incorrectos');
 let ownership=false;try{changeDemoOrderState(order.orden_id,'Completada')}catch{ownership=true}
 if(!ownership)throw Error('Un mesero no debe cambiar órdenes ajenas');
 if(allowed('usuarios')||canEdit('usuarios')||allowed('reportes')||allowed('inventario')||canEdit('platillos'))throw Error('Permisos de mesero incorrectos');
 state.user.rol='Gerente';
 if(allowed('usuarios')||canEdit('usuarios')||allowed('reportes')||!allowed('inventario')||!canEdit('platillos'))throw Error('Permisos de gerente incorrectos');
 state.user=null;renderLogin();
`,context);
assert(node('#app').innerHTML.includes('login-form'));
assert(!node('#app').innerHTML.includes('Crea tu cuenta'));
assert(!node('#app').innerHTML.includes('toggle-register'));
console.log('OK: 13 pantallas, órdenes, totales, ventas sin duplicados, acceso, reportes, alertas, capacidad, cruces y permisos.');
