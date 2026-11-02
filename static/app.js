'use strict';
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const icon = name => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const fmt = value => new Intl.NumberFormat('es-GT', {maximumFractionDigits:3}).format(Number(value));
const day = value => value ? new Intl.DateTimeFormat('es-GT', {day:'2-digit',month:'short',year:'numeric'}).format(new Date(`${value}T12:00:00`)) : 'Sin lotes';
const timestamp = value => new Intl.DateTimeFormat('es-GT', {timeZone:'America/Guatemala',day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(value));
const norm = value => String(value).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const state = {view:'insumos', data:null, branch:'1', page:1, rows:[], query:'', category:'', status:'', loading:true};
const views = {
  insumos:{title:'Tus insumos',subtitle:'Consulta y administra los ingredientes de tu cafetería.',search:'Buscar un insumo…',action:'Registrar movimiento',actionIcon:'swap'},
  lotes:{title:'Lotes y caducidad',subtitle:'Controla cada recepción y conserva la frescura de tus insumos.',search:'Buscar insumo o código de lote…',action:'Recibir lote',actionIcon:'plus'},
  movimientos:{title:'Historial de movimientos',subtitle:'Entradas, salidas, mermas y ajustes con trazabilidad por lote.',search:'Buscar insumo, lote, responsable o motivo…',action:'Registrar movimiento',actionIcon:'swap'},
  alertas:{title:'Centro de alertas',subtitle:'Atiende las existencias bajas y los lotes que necesitan tu atención.',search:'Buscar un insumo en alerta…',action:'Recibir lote',actionIcon:'plus'}
};
const size = 8;
let toastTimer;
let loadId = 0;
let modalSave;

async function api(path, options = {}) {
  const res = await fetch(path, {headers:{'Content-Type':'application/json'}, ...options});
  let data;
  try { data = await res.json(); } catch { throw new Error('El servidor no respondió correctamente. Intenta nuevamente.'); }
  if (!res.ok) throw new Error(data.error || 'No se pudo completar la operación.');
  return data;
}

function toast(message, error = false) {
  clearTimeout(toastTimer);
  $('#toast').textContent = message;
  $('#toast').className = `toast${error ? ' error' : ''}`;
  $('#toast').hidden = false;
  toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 5500);
}

async function load() {
  const current = ++loadId;
  state.loading = true;
  $('#connection').className = 'connection';
  $('#connection').innerHTML = '<span></span>Conectando';
  $('#load-error').hidden = true;
  $('#branch').disabled = true;
  $('#export').disabled = true;
  $('#new-item').disabled = true;
  $('#panel-action').disabled = true;
  $('.inventory-panel').setAttribute('aria-busy','true');
  $('#content').innerHTML = '<div class="empty"><span class="loader"></span><h3>Actualizando inventario</h3><p>Consultando existencias de la sucursal.</p></div>';
  $('#results').textContent = 'Cargando…';
  try {
    const data = await api(`/api/inventario?sucursal_id=${encodeURIComponent(state.branch)}`);
    if (current !== loadId) return;
    state.data = data;
    state.loading = false;
    $('#branch').innerHTML = data.sucursales.map(s => `<option value="${s.sucursal_id}">${esc(s.nombre_sucursal)}</option>`).join('');
    $('#branch').value = state.branch;
    $('#connection').className = 'connection online';
    $('#connection').innerHTML = '<span></span>Base de datos conectada';
    $('#today').textContent = day(data.hoy);
    updateSummary();
    render();
  } catch (error) {
    if (current !== loadId) return;
    state.loading = false;
    state.data = null;
    $('#connection').className = 'connection offline';
    $('#connection').innerHTML = '<span></span>Sin conexión';
    $('#load-error span').textContent = error.message;
    $('#load-error').hidden = false;
    $('#content').innerHTML = empty('No pudimos cargar los datos', 'Comprueba que los contenedores estén encendidos y vuelve a intentarlo.', 'box');
    $('#results').textContent = 'Datos no disponibles';
    $('#prev').disabled = $('#next').disabled = true;
    ['#stat-total','#stat-low','#stat-soon','#stat-healthy','#nav-alerts'].forEach(s => $(s).textContent = '—');
    $('#attention-title').textContent = 'No se pudieron verificar las alertas';
    $('#attention-sub').textContent = 'Restablece la conexión para consultar el inventario actual.';
  } finally {
    if (current === loadId) {
      $('.inventory-panel').setAttribute('aria-busy','false');
      $('#branch').disabled = !state.data;
      $('#export').disabled = $('#new-item').disabled = $('#panel-action').disabled = !state.data;
    }
  }
}

function hasAlert(i) { return i.stock_bajo || i.lotes_por_vencer > 0 || Number(i.stock_vencido) > 0; }
function updateSummary() {
  const {insumos, lotes} = state.data;
  const low = insumos.filter(i => i.stock_bajo).length;
  const soon = lotes.filter(l => Number(l.cantidad_disponible) > 0 && l.dias_restantes >= 0 && l.dias_restantes <= 7).length;
  const expired = lotes.filter(l => Number(l.cantidad_disponible) > 0 && l.dias_restantes < 0).length;
  const alerts = insumos.filter(hasAlert).length;
  $('#stat-total').textContent = insumos.length;
  $('#stat-low').textContent = low;
  $('#stat-soon').textContent = soon;
  $('#stat-healthy').textContent = insumos.filter(i => !hasAlert(i)).length;
  $('#nav-alerts').textContent = alerts;
  $('#attention-title').textContent = alerts ? `${alerts} ${alerts === 1 ? 'insumo necesita' : 'insumos necesitan'} tu atención` : 'Tu inventario está en su punto';
  $('#attention-sub').textContent = alerts ? `${low} con existencias bajas · ${soon} lotes por vencer${expired ? ` · ${expired} lotes vencidos` : ''}.` : 'Todos los insumos tienen existencias suficientes y lotes vigentes.';
}

function setView(view, status = '') {
  state.view = view; state.page = 1; state.query = ''; state.category = ''; state.status = status;
  $('#search').value = ''; $('#category').value = ''; $('#status').value = status;
  $$('[data-view]').forEach(button => {
    button.classList.toggle('active', button.dataset.view === view);
    if (button.classList.contains('tab')) button.setAttribute('aria-selected', String(button.dataset.view === view));
    else if (button.dataset.view === view) button.setAttribute('aria-current','page');
    else button.removeAttribute('aria-current');
  });
  const config = views[view];
  $('#panel-title').innerHTML = `${esc(config.title)} <span id="panel-count" class="count-pill">0</span>`;
  $('#panel-subtitle').textContent = config.subtitle;
  $('#search').placeholder = config.search;
  $('#panel-action').innerHTML = `${icon(config.actionIcon)}${config.action}`;
  $('#panel-action').setAttribute('aria-label', config.action);
  $('#category').hidden = view === 'movimientos';
  const statusOptions = view === 'movimientos'
    ? [['','Todos los movimientos'],['Entrada','Entradas'],['Salida','Salidas'],['Merma','Mermas'],['Ajuste','Ajustes']]
    : view === 'lotes'
      ? [['','Todos los lotes'],['soon','Por vencer'],['expired','Vencidos'],['healthy','Vigentes'],['empty','Agotados']]
      : [['','Todos los estados'],['low','Existencias bajas'],['soon','Por vencer'],['expired','Vencidos'],['healthy','Al día']];
  $('#status').innerHTML = statusOptions.map(([value,label]) => `<option value="${value}">${label}</option>`).join('');
  $('#status').value = status;
  if (state.data) render();
}

function filteredRows() {
  const query = norm(state.query);
  let rows = state.view === 'lotes' ? state.data.lotes : state.view === 'movimientos' ? state.data.movimientos : state.data.insumos;
  if (state.view === 'alertas') rows = rows.filter(hasAlert);
  return rows.filter(row => {
    if (query && !norm([row.nombre_ingrediente,row.lote_id,row.responsable,row.motivo].filter(Boolean).join(' ')).includes(query)) return false;
    if (state.category && row.categoria !== state.category) return false;
    if (!state.status) return true;
    if (state.view === 'movimientos') return row.tipo_movimiento === state.status;
    if (state.view === 'lotes') {
      const quantity = Number(row.cantidad_disponible);
      return {soon:quantity>0 && row.dias_restantes>=0 && row.dias_restantes<=7, expired:quantity>0 && row.dias_restantes<0, healthy:quantity>0 && row.dias_restantes>7, empty:quantity===0}[state.status];
    }
    return {low:row.stock_bajo, soon:row.lotes_por_vencer>0, expired:Number(row.stock_vencido)>0, healthy:!hasAlert(row)}[state.status];
  });
}

function empty(title, description, symbol = 'search') {
  return `<div class="empty">${icon(symbol)}<h3>${esc(title)}</h3><p>${esc(description)}</p></div>`;
}

function badges(item) {
  const result = [];
  if (item.stock_bajo) result.push('<span class="badge low">Existencias bajas</span>');
  if (Number(item.stock_vencido)>0) result.push('<span class="badge expired">Lotes vencidos</span>');
  if (item.lotes_por_vencer>0) result.push('<span class="badge soon">Por vencer</span>');
  return `<div class="badges">${result.length ? result.join('') : '<span class="badge">Al día</span>'}</div>`;
}

function lotBadge(lot) {
  if (Number(lot.cantidad_disponible) === 0) return '<span class="badge">Agotado</span>';
  if (lot.dias_restantes<0) return '<span class="badge expired">Vencido</span>';
  if (lot.dias_restantes<=7) return `<span class="badge soon">${lot.dias_restantes === 0 ? 'Vence hoy' : `Vence en ${lot.dias_restantes} d`}</span>`;
  return '<span class="badge">Vigente</span>';
}

function mark(item) {
  const category = {'Café y té':['C','coffee'],'Lácteos':['L','dairy'],'Panadería':['P','bakery'],'Despensa':['D','pantry'],'Frutas y frescos':['F','fresh']}[item.categoria] || ['I',''];
  return `<span class="ingredient-mark ${category[1]}" aria-hidden="true">${category[0]}</span>`;
}

function itemName(item, code = '') {
  return `<div class="item-name">${mark(item)}<div><button class="name-link" data-detail="${item.ingrediente_id}">${esc(item.nombre_ingrediente)}</button><span class="item-code">${esc(code || `INS-${String(item.ingrediente_id).padStart(3,'0')}`)}</span></div></div>`;
}

function render() {
  if (!state.data || state.loading) return;
  const rows = filteredRows();
  state.rows = rows;
  const pages = Math.max(1, Math.ceil(rows.length / size));
  state.page = Math.min(state.page, pages);
  const slice = rows.slice((state.page-1)*size, state.page*size);
  $('#panel-count').textContent = rows.length;
  $('#clear-filters').hidden = !state.query && !state.category && !state.status;
  if (!rows.length) {
    $('#content').innerHTML = empty(state.view==='alertas' && !state.query && !state.status && !state.category ? 'Todo está en su punto' : 'No encontramos registros', state.query || state.category || state.status ? 'Prueba con otra búsqueda o limpia los filtros.' : state.view==='insumos' ? 'Agrega tu primer insumo para comenzar a organizar la cocina.' : state.view==='alertas' ? 'No hay alertas pendientes en esta sucursal.' : 'Los nuevos registros aparecerán aquí.');
  } else if (state.view === 'alertas') {
    $('#content').innerHTML = `<div class="alerts-list">${slice.map(i => `<article class="alert-card ${Number(i.stock_vencido)>0?'expired':''}">${icon('alert')}<div><h3>${esc(i.nombre_ingrediente)}</h3>${badges(i)}<p>${i.stock_bajo ? `Disponible: <strong>${fmt(i.stock_actual)} ${esc(i.unidad_medida)}</strong> · Umbral de alerta: ${fmt(i.umbral_alerta)} ${esc(i.unidad_medida)}.<br>`:''}${i.lotes_por_vencer>0 ? `${i.lotes_por_vencer} ${i.lotes_por_vencer===1?'lote vence':'lotes vencen'} en los próximos 7 días.<br>`:''}${Number(i.stock_vencido)>0 ? `${fmt(i.stock_vencido)} ${esc(i.unidad_medida)} vencidos, excluidos del stock disponible.`:''}</p><button class="text-button" data-detail="${i.ingrediente_id}">Ver insumo y lotes →</button></div></article>`).join('')}</div>`;
  } else {
    let head, body;
    if (state.view === 'insumos') {
      head = ['Insumo','Categoría','Disponible','Mínimo','Próxima caducidad','Estado','Acciones'];
      body = slice.map(i => `<tr><td>${itemName(i)}</td><td><span class="category-label">${esc(i.categoria)}</span></td><td class="${i.stock_bajo?'low-stock':''}"><span class="stock-number">${fmt(i.stock_actual)}</span><span class="stock-unit">${esc(i.unidad_medida)}</span><progress value="${Math.min(Number(i.stock_actual),Number(i.stock_referencia))}" max="${i.stock_referencia}" aria-label="Existencias de ${esc(i.nombre_ingrediente)} respecto a la referencia"></progress></td><td>${fmt(i.stock_minimo)} <span class="stock-unit">${esc(i.unidad_medida)}</span></td><td><span class="date-small ${i.lotes_por_vencer>0?'urgent':''}">${day(i.proximo_vencimiento)}</span></td><td>${badges(i)}</td><td><div class="row-actions"><button class="icon-button" data-receive="${i.ingrediente_id}" title="Recibir lote de ${esc(i.nombre_ingrediente)}" aria-label="Recibir lote de ${esc(i.nombre_ingrediente)}">${icon('plus')}</button><button class="icon-button" data-edit="${i.ingrediente_id}" title="Editar ${esc(i.nombre_ingrediente)}" aria-label="Editar ${esc(i.nombre_ingrediente)}">${icon('edit')}</button><button class="icon-button danger" data-delete="${i.ingrediente_id}" title="Eliminar ${esc(i.nombre_ingrediente)}" aria-label="Eliminar ${esc(i.nombre_ingrediente)}">${icon('trash')}</button></div></td></tr>`).join('');
    } else if (state.view === 'lotes') {
      head = ['Insumo / lote','Ingreso','Vencimiento','Existencias','Estado','Acciones'];
      body = slice.map(l => `<tr><td>${itemName(l,l.lote_id)}</td><td class="date-small">${day(l.fecha_ingreso)}</td><td class="date-small ${l.dias_restantes<=7?'urgent':''}">${day(l.fecha_vencimiento)}</td><td><span class="stock-number">${fmt(l.cantidad_disponible)}</span><span class="stock-unit">${esc(l.unidad_medida)}</span></td><td>${lotBadge(l)}</td><td><button class="text-button" data-move="${esc(l.lote_id)}">Registrar movimiento →</button></td></tr>`).join('');
    } else {
      head = ['Fecha','Insumo / lote','Movimiento','Variación','Saldo del lote','Responsable / motivo'];
      body = slice.map(m => `<tr><td class="date-small">${timestamp(m.fecha_hora)}</td><td>${itemName(m,m.lote_id)}</td><td><span class="movement-type ${Number(m.variacion)>0?'positive':'negative'}">${esc(m.tipo_movimiento)}</span></td><td class="movement-type ${Number(m.variacion)>0?'positive':'negative'}">${Number(m.variacion)>0?'+':''}${fmt(m.variacion)} ${esc(m.unidad_medida)}</td><td>${fmt(m.stock_resultante)} ${esc(m.unidad_medida)}</td><td class="note-cell"><strong>${esc(m.responsable)}</strong><br><span class="muted">${esc(m.motivo)}</span></td></tr>`).join('');
    }
    $('#content').innerHTML = `<div class="table-scroll"><table><thead><tr>${head.map(h=>`<th scope="col">${h}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`;
  }
  $('#results').textContent = rows.length ? `Mostrando ${(state.page-1)*size+1}–${Math.min(state.page*size,rows.length)} de ${rows.length} registros` : '0 registros';
  $('#page-label').textContent = `${state.page} / ${pages}`;
  $('#prev').disabled = state.page <= 1;
  $('#next').disabled = state.page >= pages;
}

function showModal(title, html, onSave) {
  $('#modal-title').textContent = title;
  $('#modal-body').innerHTML = html;
  modalSave = onSave;
  if (!$('#modal').open) $('#modal').showModal();
}

function formFooter(label = 'Guardar cambios') {
  return `<div id="form-error" class="form-error" role="alert" hidden></div><div class="form-actions"><button type="button" class="button secondary" data-close>Cancelar</button><button type="submit" class="button primary">${label}</button></div>`;
}
function options(values, selected) {return values.map(v=>`<option${v===selected?' selected':''}>${esc(v)}</option>`).join('');}

function ingredientForm(id) {
  if (!state.data || state.loading) return;
  const item = state.data.insumos.find(i=>i.ingrediente_id===Number(id));
  const hasLots = item && state.data.lotes.some(l=>l.ingrediente_id===item.ingrediente_id);
  showModal(item ? 'Editar insumo' : 'Nuevo insumo', `<form id="inventory-form"><div class="form-note">Organiza tu catálogo. Las existencias se registran al recibir un lote.</div><div class="form-grid">
    <label class="field full">Nombre del insumo<input name="nombre_ingrediente" required maxlength="60" placeholder="Ej. Café de especialidad" value="${esc(item?.nombre_ingrediente || '')}" autofocus></label>
    <label class="field">Categoría<select name="categoria">${options(['Café y té','Lácteos','Panadería','Despensa','Frutas y frescos'],item?.categoria)}</select></label>
    <label class="field">Unidad de medida<select name="unidad_medida" ${hasLots?'disabled':''}>${options(['kg','g','L','ml','ud'],item?.unidad_medida)}</select>${hasLots?'<small>La unidad se conserva al tener lotes registrados.</small>':''}</label>
    <label class="field">Existencia mínima<input name="stock_minimo" type="number" required min="0" max="999999999.999" step="0.001" value="${esc(item?.stock_minimo || '0')}"></label>
    <label class="field">Existencia de referencia<input name="stock_referencia" type="number" required min="0.001" max="999999999.999" step="0.001" value="${esc(item?.stock_referencia || '')}" placeholder="Ej. 20"></label>
    <div class="field full"><small>Se alerta al llegar al mayor valor entre el mínimo y el 15% de la referencia. El cálculo se hace por sucursal y excluye lotes vencidos.</small></div>
    </div>${formFooter(item?'Guardar cambios':'Crear insumo')}</form>`, async data => {
      if (hasLots) data.unidad_medida = item.unidad_medida;
      await api(item?`/api/insumos/${item.ingrediente_id}`:'/api/insumos', {method:item?'PUT':'POST',body:JSON.stringify(data)});
      return item?'Insumo actualizado.':'Insumo creado. Ya puedes recibir su primer lote.';
    });
}

function receiveForm(itemId) {
  if (!state.data || state.loading) return;
  if (!state.data.insumos.length) { ingredientForm(); return; }
  showModal('Recibir un lote', `<form id="inventory-form"><div class="form-note">Registra la entrada en <strong>${esc($('#branch').selectedOptions[0].textContent)}</strong>. Cada lote conserva su propia fecha de caducidad.</div><div class="form-grid">
    <label class="field full">Insumo<select name="ingrediente_id" id="receive-item">${state.data.insumos.map(i=>`<option value="${i.ingrediente_id}" ${i.ingrediente_id===Number(itemId)?'selected':''}>${esc(i.nombre_ingrediente)} (${esc(i.unidad_medida)})</option>`).join('')}</select></label>
    <label class="field">Código del lote<input name="lote_id" maxlength="30" required placeholder="Ej. CAFE-2026-01"></label>
    <label class="field">Fecha de vencimiento<input name="fecha_vencimiento" type="date" min="${state.data.hoy}" required></label>
    <label class="field">Cantidad recibida<input name="cantidad" type="number" min="0.001" max="999999999.999" step="0.001" required placeholder="0.000"><small id="receive-unit"></small></label>
    <label class="field">Responsable<input name="responsable" maxlength="60" required placeholder="Nombre de quien recibe"></label>
    <label class="field full">Motivo o referencia<textarea name="motivo" maxlength="200" required placeholder="Ej. Compra a proveedor, factura 1042"></textarea></label>
    </div>${formFooter('Registrar entrada')}</form>`, async data => {
      data.sucursal_id = Number(state.branch);
      await api('/api/lotes',{method:'POST',body:JSON.stringify(data)});
      return 'Lote recibido. Existencias actualizadas.';
    });
  const updateUnit = () => { const item=state.data.insumos.find(i=>i.ingrediente_id===Number($('#receive-item').value)); $('#receive-unit').textContent=`Unidad de registro: ${item.unidad_medida}`; };
  $('#receive-item').addEventListener('change',updateUnit); updateUnit();
}

function movementForm(lotId) {
  if (!state.data || state.loading) return;
  if (!state.data.lotes.length) { receiveForm(); return; }
  showModal('Registrar movimiento', `<form id="inventory-form"><div class="form-note">Cada movimiento actualiza el saldo del lote y queda guardado en el historial.</div><div class="form-grid">
    <label class="field full">Lote<select name="lote_id" id="move-lot">${state.data.lotes.map(l=>`<option value="${esc(l.lote_id)}" ${l.lote_id===lotId?'selected':''}>${esc(l.nombre_ingrediente)} · ${esc(l.lote_id)} (${fmt(l.cantidad_disponible)} ${esc(l.unidad_medida)})</option>`).join('')}</select><small id="lot-balance"></small></label>
    <label class="field">Tipo de movimiento<select name="tipo_movimiento" id="move-type">${options(['Salida','Entrada','Merma','Ajuste'])}</select></label>
    <label class="field"><span id="quantity-label">Cantidad</span><input name="cantidad" id="move-quantity" type="number" min="0.001" max="999999999.999" step="0.001" required placeholder="0.000"><small id="quantity-hint"></small></label>
    <label class="field full">Responsable<input name="responsable" maxlength="60" required placeholder="Nombre de quien registra"></label>
    <label class="field full">Motivo<textarea name="motivo" maxlength="200" required placeholder="Ej. Consumo en cocina, producto dañado o conteo físico"></textarea></label>
    </div>${formFooter('Guardar movimiento')}</form>`, async data => {
      await api('/api/movimientos',{method:'POST',body:JSON.stringify(data)});
      return 'Movimiento registrado. Saldo del lote actualizado.';
    });
  const update = () => {
    const lot = state.data.lotes.find(l=>l.lote_id===$('#move-lot').value);
    const expired = lot.dias_restantes<0;
    $$('option', $('#move-type')).forEach(o=>{o.disabled = expired && ['Entrada','Salida'].includes(o.value);});
    if ($('#move-type').selectedOptions[0].disabled) $('#move-type').value='Merma';
    const adjustment=$('#move-type').value==='Ajuste';
    $('#quantity-label').textContent=adjustment?'Conteo físico final':'Cantidad';
    $('#move-quantity').min=adjustment?'0':'0.001';
    $('#lot-balance').textContent=`Disponible en este lote: ${fmt(lot.cantidad_disponible)} ${lot.unidad_medida} · Vence: ${day(lot.fecha_vencimiento)}${expired?' · LOTE VENCIDO':''}`;
    $('#quantity-hint').textContent=adjustment ? `Escribe el saldo contado en ${lot.unidad_medida}. Se calculará la diferencia.${expired?' Solo se permite reducir el saldo vencido.':''}` : `Cantidad en ${lot.unidad_medida}.${expired?' Solo se permite retirar el producto vencido.':''}`;
  };
  $('#move-lot').addEventListener('change',update); $('#move-type').addEventListener('change',update); update();
}

function detail(id) {
  if (!state.data || state.loading) return;
  const item=state.data.insumos.find(i=>i.ingrediente_id===Number(id));
  const lots=state.data.lotes.filter(l=>l.ingrediente_id===item.ingrediente_id);
  showModal(item.nombre_ingrediente, `<div class="detail-stats"><div class="detail-stat">Disponible para usar<strong>${fmt(item.stock_actual)} ${esc(item.unidad_medida)}</strong></div><div class="detail-stat">Umbral de alerta<strong>${fmt(item.umbral_alerta)} ${esc(item.unidad_medida)}</strong></div></div>${badges(item)}<p class="form-note">Mínimo: ${fmt(item.stock_minimo)} ${esc(item.unidad_medida)} · Referencia: ${fmt(item.stock_referencia)} ${esc(item.unidad_medida)}.<br>El stock disponible excluye los lotes vencidos.</p><h3 class="detail-title">Lotes en esta sucursal</h3>${lots.length?lots.map(l=>`<div class="detail-lot"><div><strong>${esc(l.lote_id)}</strong><br><small>Vence ${day(l.fecha_vencimiento)}</small><br><button class="text-button" data-move="${esc(l.lote_id)}">Registrar movimiento →</button></div><div class="detail-right">${fmt(l.cantidad_disponible)} ${esc(item.unidad_medida)}<br>${lotBadge(l)}</div></div>`).join(''):'<p class="detail-empty">Este insumo aún no tiene lotes en la sucursal seleccionada.</p>'}<div class="form-actions"><button class="button secondary" data-edit="${item.ingrediente_id}">${icon('edit')}Editar insumo</button><button class="button primary" data-receive="${item.ingrediente_id}">${icon('plus')}Recibir lote</button></div>`);
}

function deleteForm(id) {
  if (!state.data || state.loading) return;
  const item=state.data.insumos.find(i=>i.ingrediente_id===Number(id));
  showModal('Eliminar insumo', `<form id="inventory-form"><p class="form-note">Vas a eliminar <strong>${esc(item.nombre_ingrediente)}</strong> del catálogo de todas las sucursales. Solo se puede eliminar un insumo sin lotes registrados.</p>${formFooter('Eliminar insumo')}</form>`,async()=>{
    await api(`/api/insumos/${id}`,{method:'DELETE'});
    return 'Insumo eliminado del catálogo.';
  });
}

function exportCsv() {
  if (!state.data || state.loading) return;
  const columns = state.view==='lotes' ? [['lote_id','Lote'],['nombre_ingrediente','Insumo'],['fecha_ingreso','Ingreso'],['fecha_vencimiento','Vencimiento'],['cantidad_disponible','Existencias'],['unidad_medida','Unidad']]
    : state.view==='movimientos' ? [['fecha_hora','Fecha'],['lote_id','Lote'],['nombre_ingrediente','Insumo'],['tipo_movimiento','Tipo'],['cantidad','Cantidad / conteo'],['variacion','Variación'],['stock_resultante','Saldo'],['unidad_medida','Unidad'],['responsable','Responsable'],['motivo','Motivo']]
    : [['nombre_ingrediente','Insumo'],['categoria','Categoría'],['stock_actual','Stock utilizable'],['unidad_medida','Unidad'],['stock_minimo','Mínimo'],['stock_referencia','Referencia'],['umbral_alerta','Umbral de alerta'],['stock_bajo','Stock bajo'],['stock_vencido','Stock vencido'],['lotes_por_vencer','Lotes por vencer'],['proximo_vencimiento','Próximo vencimiento']];
  const cell=value=>{
    let text=String(value??'');
    // Evitar fórmulas al abrir valores de texto capturados por el usuario en Excel.
    if (/^[\s]*[=+@-]/.test(text) && !/^-?\d+(\.\d+)?$/.test(text)) text=`'${text}`;
    return `"${text.replace(/"/g,'""')}"`;
  };
  const rows=filteredRows();
  const csv=[['Sucursal',...columns.map(([,label])=>label)],...rows.map(row=>[$('#branch').selectedOptions[0].textContent,...columns.map(([key])=>row[key])])].map(row=>row.map(cell).join(',')).join('\r\n');
  const url=URL.createObjectURL(new Blob(['\ufeff',csv],{type:'text/csv;charset=utf-8;'}));
  const link=document.createElement('a');link.href=url;link.download=`aurea-${state.view}-${state.branch}-${state.data.hoy}.csv`;link.click();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
  toast(`Se exportaron ${rows.length} registros de la vista actual.`);
}

document.addEventListener('click',event=>{
  const target=event.target.closest('button');
  if (!target) return;
  if (target.dataset.view) setView(target.dataset.view);
  if ('detail' in target.dataset) detail(target.dataset.detail);
  if ('edit' in target.dataset) ingredientForm(target.dataset.edit);
  if ('receive' in target.dataset) receiveForm(target.dataset.receive);
  if ('move' in target.dataset) movementForm(target.dataset.move);
  if ('delete' in target.dataset) deleteForm(target.dataset.delete);
  if ('close' in target.dataset) $('#modal').close();
  if ('stat' in target.dataset && state.data) {
    if (target.dataset.stat==='soon') setView('lotes','soon');
    else setView('insumos', {all:'',low:'low',healthy:'healthy'}[target.dataset.stat]);
  }
});
$('#modal-body').addEventListener('submit', async event=>{
  event.preventDefault();
  if (!modalSave) return;
  const form=event.target;
  const submit=$('button[type="submit"]',form);
  const label=submit.textContent;
  const close=$('#close-modal');
  submit.disabled=true;close.disabled=true;
  $$('[data-close]',form).forEach(b=>b.disabled=true);
  submit.textContent='Guardando…';
  $('#form-error').hidden=true;
  try {
    const message=await modalSave(Object.fromEntries(new FormData(form)));
    $('#modal').close();
    await load();
    toast(state.data?message:`${message} No se pudo refrescar la vista. Usa Reintentar.`,!state.data);
  } catch (error) {
    $('#form-error').textContent=error.message;$('#form-error').hidden=false;
    submit.disabled=false;submit.textContent=label;
    $$('[data-close]',form).forEach(b=>b.disabled=false);
  } finally {close.disabled=false;}
});
$('#modal').addEventListener('cancel',event=>{if ($('#close-modal').disabled) event.preventDefault();});
$('#close-modal').addEventListener('click',()=>$('#modal').close());
$('#branch').addEventListener('change',()=>{state.branch=$('#branch').value;state.page=1;load();});
$('#retry').addEventListener('click',load);
$('#new-item').addEventListener('click',()=>ingredientForm());
$('#panel-action').addEventListener('click',()=>['lotes','alertas'].includes(state.view)?receiveForm():movementForm());
$('#attention').addEventListener('click',()=>setView('alertas'));
$('#export').addEventListener('click',exportCsv);
$('#search').addEventListener('input',()=>{state.query=$('#search').value;state.page=1;render();});
$('#category').addEventListener('change',()=>{state.category=$('#category').value;state.page=1;render();});
$('#status').addEventListener('change',()=>{state.status=$('#status').value;state.page=1;render();});
$('#clear-filters').addEventListener('click',()=>{state.query=state.category=state.status='';state.page=1;$('#search').value=$('#category').value=$('#status').value='';render();});
$('#prev').addEventListener('click',()=>{state.page--;render();});
$('#next').addEventListener('click',()=>{state.page++;render();});
$('.tabs').addEventListener('keydown',event=>{
  if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
  event.preventDefault();
  const tabs=$$('.tab');const index=tabs.indexOf(document.activeElement);
  const next=event.key==='Home'?0:event.key==='End'?tabs.length-1:(index+(event.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length;
  tabs[next].focus();setView(tabs[next].dataset.view);
});
load();
