"""Genera ventas_aurea_simuladas.csv (Enero 1 - Oct 14, 2026) para el DataMart de Aurea.

- Mismas columnas y formato que ventas_aurea_p2.csv  -> los scripts 07, 08 y 09 NO cambian.
- Reproducible: semilla fija.  Uso:  python generar_simulados.py
"""
import csv
import random
from collections import defaultdict
from datetime import date, timedelta

SEED = 2026
FECHA_INI, FECHA_FIN = date(2026, 1, 1), date(2026, 10, 14)   # el dato real empieza el 15-oct
ORDEN_BASE = 1_000_000                                         # no choca con las ordenes reales (<= 478)
PROB_SIN_CLIENTE = 0.04                                        # ~3-4 % como en el dato real
rng = random.Random(SEED)

#1. Catalogo REAL (precios intactos)
cat, suc = {}, {}
with open("ventas_aurea_p2.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        cat[int(r["platillo_id"])] = (r["nombre_platillo"], r["categoria"], r["precio_unitario"])
        suc[int(r["sucursal_id"])] = r["nombre_sucursal"]
cat_ids = {c: [i for i, v in cat.items() if v[1] == c] for c in ("Plato Fuerte", "Postre", "Bebida")}
FRIAS = {17, 18, 19, 20, 21}                                  

# 2. Parametros de demanda (calibrados con el dato real de Proyecto 2) 
# ordenes base por dia con tendencia = 1.0 (Lun..Dom): el fin de semana es ~4x un dia de semana
BASE_DIA = [12, 10, 12, 11, 16, 48, 50]

SHARE_INI = {1: 0.38, 2: 0.24, 3: 0.38}
SHARE_FIN = {1: 0.337, 2: 0.297, 3: 0.366}                     # = reparto real de Oct/Nov
CRECIMIENTO_TOTAL = (0.74, 1.00)                               # volumen total: ene -> oct

H = range(8, 23)
HORA_SEMANA = dict(zip(H, [16, 15, 8, 1, 21, 17, 13, 7, 4, 7, 11, 10, 5, 7, 1]))
HORA_FINDE = dict(zip(H, [12, 15, 8, 1, 88, 158, 7, 5, 6, 7, 4, 8, 13, 3, 0]))
SUAVE = 2.0

def pesos_hora(finde, cena=False):
    base = HORA_FINDE if finde else HORA_SEMANA
    w = {h: base[h] + SUAVE for h in H}
    if cena:                                                   # dias especiales: mas cenas
        for h in (19, 20, 21):
            w[h] *= 5
    return list(w.keys()), list(w.values())

# eventos: (multiplicador de ordenes, ¿mas cenas?)
EVENTOS = {
    date(2026, 1, 1): (0.5, False),    # Año Nuevo
    date(2026, 2, 14): (1.9, True),    # San Valentin
    date(2026, 4, 2): (0.6, False),    # Jueves Santo
    date(2026, 4, 3): (0.6, False),    # Viernes Santo
    date(2026, 4, 4): (0.8, False),    # Sabado Santo
    date(2026, 5, 10): (1.5, False),   # Dia de la Madre
    date(2026, 9, 15): (2.6, False),   # Independencia (martes feriado)
}

def mult_quincena(d):
    ultimo = (date(d.year + (d.month == 12), d.month % 12 + 1, 1) - timedelta(days=1)).day
    return 1.15 if d.day in (15, ultimo) else 1.0

#3. Contenido de cada orden}
COMBOS = [("B+PF", .30), ("B+PF+P", .31), ("B", .14), ("B+P", .17), ("PF+P", .05), ("PF", .02), ("P", .01)]
NOMBRE = {"B": "Bebida", "PF": "Plato Fuerte", "P": "Postre"}
K_ITEMS = {"Plato Fuerte": ([1, 2], [.68, .32]), "Bebida": ([1, 2], [.35, .65]), "Postre": ([1, 2], [.80, .20])}

def peso_platillo(pid, mes, finde):
    nombre, categoria, _ = cat[pid]
    w = 1.0
    if categoria == "Bebida":
        if pid in FRIAS:
            w *= 1.6 if mes in (3, 4, 5) else 0.8              # calor de mar-may
        else:
            w *= 1.25 if mes in (1, 2, 6, 7, 8, 9, 10) else 0.9  # frio / lluvias
    if categoria == "Postre" and finde:
        w *= 1.2
    if nombre in ("Pollo a la Parrilla", "Lomo en salsa de Pimienta"):
        w *= 1.15
    return w

def elegir(lista, pesos):
    return rng.choices(lista, weights=pesos, k=1)[0]

def armar_orden(mes, finde):
    combo = elegir([c for c, _ in COMBOS], [p for _, p in COMBOS]).split("+")
    pids = []
    for c in combo:
        categoria = NOMBRE[c]
        ks, kp = K_ITEMS[categoria]
        k = elegir(ks, kp)
        disp = cat_ids[categoria][:]
        pesos = [peso_platillo(p, mes, finde) for p in disp]
        for _ in range(min(k, len(disp))):                     # sin repetir platillo en la orden
            i = rng.choices(range(len(disp)), weights=pesos, k=1)[0]
            pids.append(disp.pop(i)); pesos.pop(i)
    pids = pids[:5]
    return [(p, elegir([1, 2], [.49, .51])) for p in pids]

# 4. Clientes
CLIENTES = list(range(1, 31))
PESO_CLI = [rng.lognormvariate(0, 0.45) for _ in CLIENTES]
FAV = {c: rng.choice(list(suc)) for c in CLIENTES}

def elegir_cliente(sucursal):
    if rng.random() < PROB_SIN_CLIENTE:
        return None
    pesos = [w * (2.2 if FAV[c] == sucursal else 1.0) for c, w in zip(CLIENTES, PESO_CLI)]
    return elegir(CLIENTES, pesos)

# 5. Generacion 
dias = (FECHA_FIN - FECHA_INI).days
ordenes = []                                                   # (datetime-str, sucursal, cliente, [(pid, qty)])
for n in range(dias + 1):
    d = FECHA_INI + timedelta(days=n)
    t = n / dias
    crec = CRECIMIENTO_TOTAL[0] + (CRECIMIENTO_TOTAL[1] - CRECIMIENTO_TOTAL[0]) * t
    ev_mult, cena = EVENTOS.get(d, (1.0, False))
    finde = d.weekday() >= 5
    media = BASE_DIA[d.weekday()] * crec * ev_mult * mult_quincena(d)
    media *= rng.lognormvariate(0, 0.12)                       # ruido diario
    total = max(1, round(media))
    shares = {s: SHARE_INI[s] + (SHARE_FIN[s] - SHARE_INI[s]) * t for s in suc}
    horas, ph = pesos_hora(finde or ev_mult > 2, cena)
    for _ in range(total):
        s = elegir(list(shares), list(shares.values()))
        h = elegir(horas, ph)
        m = rng.randrange(60)
        ts = f"{d.isoformat()} {h:02d}:{m:02d}:00-06"
        ordenes.append((ts, s, elegir_cliente(s), armar_orden(d.month, finde)))

ordenes.sort(key=lambda o: o[0])                               # ids crecientes en orden cronologico

# 6. Escritura (mismo formato que ventas_aurea_p2.csv) 
with open("ventas_aurea_simuladas.csv", "w", encoding="utf-8", newline="") as f:
    f.write('"orden_id","fecha_hora","sucursal_id","nombre_sucursal","cliente_id","platillo_id",'
            '"nombre_platillo","categoria","cantidad","precio_unitario"\r\n')
    lineas = 0
    for i, (ts, s, cli, items) in enumerate(ordenes, start=1):
        oid = ORDEN_BASE + i
        for pid, qty in sorted(items):
            nombre, categoria, precio = cat[pid]
            f.write(f'{oid},"{ts}",{s},"{suc[s]}",{"NULL" if cli is None else cli},{pid},'
                    f'"{nombre}","{categoria}",{qty},{precio}\r\n')
            lineas += 1
print(f"{len(ordenes)} ordenes, {lineas} lineas, {FECHA_INI} -> {FECHA_FIN}")
