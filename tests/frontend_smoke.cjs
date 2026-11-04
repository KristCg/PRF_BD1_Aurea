// Verifica lógica y generación de pantallas sin automatizar un navegador.
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const nodes=new Map();
const node=s=>{if(!nodes.has(s))nodes.set(s,{innerHTML:'',textContent:'',value:'1',classList:{add(){},remove(){},toggle(){}},addEventListener(){},showModal(){},close(){},focus(){},setSelectionRange(){}});return nodes.get(s)};
const context=vm.createContext({document:{querySelector:node,querySelectorAll:()=>[],addEventListener(){}},window:{scrollTo(){}},fetch:async()=>({ok:true,json:async()=>({mode:'demo',user:null})}),Intl,Date,console,setTimeout:()=>0,clearTimeout(){},localStorage:{setItem(){},getItem(){return null}},URL,Blob,TextEncoder});
vm.runInContext(fs.readFileSync('static/app.js','utf8'),context);
vm.runInContext("state.user={usuario_id:1,nombre:'Maya Salazar',correo:'admin@aurea.gt',rol:'Administrador'};state.mode='demo';state.data=demoData();state.branch=1",context);
for(const page of ['inicio','reservas','mesas','clientes','platillos','inventario','personal','usuarios','sucursales','bitacora','reportes','buscar']){
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
 state.user.rol='Mesero';
 if(allowed('usuarios')||canEdit('usuarios')||allowed('reportes')||allowed('inventario')||canEdit('platillos'))throw Error('Permisos de mesero incorrectos');
 state.user.rol='Gerente';
 if(allowed('usuarios')||canEdit('usuarios')||allowed('reportes')||!allowed('inventario')||!canEdit('platillos'))throw Error('Permisos de gerente incorrectos');
 state.user=null;renderLogin();
`,context);
assert(node('#app').innerHTML.includes('login-form'));
assert(!node('#app').innerHTML.includes('Crea tu cuenta'));
assert(!node('#app').innerHTML.includes('toggle-register'));
console.log('OK: 12 pantallas, acceso sin registro público, reportes, alertas, capacidad, cruces y permisos.');
