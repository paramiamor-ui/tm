"""GPO Halloween - macro de caramelos en Python + OpenCV.

Teclas (dentro del juego):
  F1  grabar / terminar la ruta (por tramos)
  F2  mientras grabas: "este tramo termina contra una pared"
  F3  iniciar / parar
  F4  probar la compra (pegado a la bruja)
  F6  probar el alineado de cámara
  F7  diagnóstico: guarda diagnostico.png y lo que ve
  F8  salir

Ajustes en config.json (se crea solo la primera vez).
"""
import asyncio
import ctypes
import json
import os
import queue
import re
import sys
import threading
import time

import cv2
import numpy as np

import vision

AQUI = os.path.dirname(os.path.abspath(__file__))
ARCHIVO_CONFIG = os.path.join(AQUI, "config.json")
ARCHIVO_RUTA = os.path.join(AQUI, "ruta.json")
ARCHIVO_REGISTRO = os.path.join(AQUI, "registro.txt")

CONFIG_INICIAL = {
    "articulo": "Rare Fruit Chest",   # nombre exacto de la tienda; "" = no comprar
    "comprar_todo": True,             # False = compra solo 1 cada vez
    "parar_tras_comprar": False,      # True = compra una vez y se detiene
    "habilidad_cada_min": 5,          # 0 = no usar la habilidad
    "slot_bolsa": 2,
    "slot_habilidad": 3,
    "tecla_habilidad": "c",
    "mantener_e": 0.4,                # segundos que se mantiene E
    "espera_tras_caramelos": 1.5,     # aturdimiento después de una puerta que da caramelos
    "margen_pared": 0.5,              # segundos extra en los tramos que acaban en pared
    "rearme_puerta": 2.0,             # segundos de ruta antes de volver a tocar si el aviso no desaparece
    "corregir_camara": True,
    "factor_giro": 0.5,
    "buscar_puertas": True,
}

ARTICULOS = {
    "SP Reset Essence": 10, "Devil Fruit Remover": 25, "Race Reroll x5": 25,
    "Custom Spirit Color": 50, "Lantern": 50, "Trading Sign": 100,
    "Joker Costume": 100, "Ghost Face Costume": 100, "Plague Doctor Costume": 100,
    "Legendary Fruit Chest Blueprint": 100, "Mummy Wrappings": 100, "Devil Fruit Journal": 125,
    "Wizard Costume": 175, "Frankenstein Costume": 175, "Shark Costume": 175,
    "Fruit Bag": 250, "Rare Fruit Chest": 250, "Blood Scythe": 500,
}
# Nombres que en la tienda ocupan dos líneas o que el OCR puede leer mal.
CLAVES = {"Plague Doctor Costume": "plaguedoctor",
          "Legendary Fruit Chest Blueprint": "legendaryfruitchest",
          "Race Reroll x5": "racereroll"}

# Teclas de movimiento que se graban, por código de escaneo (no depende del idioma del teclado)
SCAN_MOVIMIENTO = {17: "w", 30: "a", 31: "s", 32: "d", 57: "space", 42: "shift"}
# Teclas de función, por código de escaneo. Se leen a mano (no con add_hotkey) para que
# funcionen aunque haya otra tecla pulsada, p. ej. F2 mientras empujas con W.
SCAN_F = {59: "f1", 60: "f2", 61: "f3", 62: "f4", 64: "f6", 65: "f7", 66: "f8"}


# ======================= utilidades =======================

def cargar_config():
    cfg = dict(CONFIG_INICIAL)
    if os.path.exists(ARCHIVO_CONFIG):
        try:
            with open(ARCHIVO_CONFIG, encoding="utf-8") as f:
                cfg.update(json.load(f))
        except Exception as e:
            print("config.json no se pudo leer, uso valores por defecto:", e)
    else:
        with open(ARCHIVO_CONFIG, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
    return cfg


estados = queue.Queue()   # mensajes para la ventanita


def registrar(texto):
    linea = time.strftime("%H:%M:%S") + "  " + texto
    print(linea)
    try:
        with open(ARCHIVO_REGISTRO, "a", encoding="utf-8") as f:
            f.write(linea + "\n")
    except OSError:
        pass
    estados.put(("estado", texto))


# ======================= Windows: pantalla, foco, teclado, ratón =======================

ES_WINDOWS = sys.platform == "win32"
if ES_WINDOWS:
    import keyboard
    import mss
    import pydirectinput

    pydirectinput.PAUSE = 0
    pydirectinput.FAILSAFE = False
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)   # coordenadas reales de píxel
    except Exception:
        pass

_hilo_local = threading.local()


def pantalla():
    """Captura la pantalla principal como imagen BGR."""
    if not hasattr(_hilo_local, "sct"):
        _hilo_local.sct = mss.mss()
    crudo = np.array(_hilo_local.sct.grab(_hilo_local.sct.monitors[1]))
    return cv2.cvtColor(crudo, cv2.COLOR_BGRA2BGR)


def roblox_activo():
    hwnd = ctypes.windll.user32.GetForegroundWindow()
    buf = ctypes.create_unicode_buffer(256)
    ctypes.windll.user32.GetWindowTextW(hwnd, buf, 256)
    return buf.value.strip() == "Roblox"


def activar_roblox():
    hwnd = ctypes.windll.user32.FindWindowW(None, "Roblox")
    if not hwnd:
        return False
    ctypes.windll.user32.ShowWindow(hwnd, 9)
    ctypes.windll.user32.SetForegroundWindow(hwnd)
    time.sleep(0.3)
    return roblox_activo()


def bajar(teclas):
    for t in teclas:
        pydirectinput.keyDown(t)


def subir(teclas):
    for t in teclas:
        pydirectinput.keyUp(t)


def pulsar(tecla, segundos=0.08):
    pydirectinput.keyDown(tecla)
    time.sleep(segundos)
    pydirectinput.keyUp(tecla)


def soltar_todo():
    for t in ("w", "a", "s", "d", "space", "shift", "e", "c"):
        pydirectinput.keyUp(t)
    pydirectinput.mouseUp(button="right")


def raton_relativo(dx, dy=0):
    ctypes.windll.user32.mouse_event(0x0001, int(dx), int(dy), 0, 0)


def rueda(clics):
    ctypes.windll.user32.mouse_event(0x0800, 0, 0, int(clics) * 120, 0)


def clic(x, y):
    # Roblox no registra el clic si el ratón no se mueve antes
    pydirectinput.moveTo(int(x), int(y))
    time.sleep(0.03)
    raton_relativo(1, 0)
    time.sleep(0.03)
    pydirectinput.click()
    time.sleep(0.05)


# ======================= OCR (opcional, con winocr) =======================

try:
    import winocr
    from PIL import Image
    OCR_DISPONIBLE = True
except Exception:
    OCR_DISPONIBLE = False
_idioma_ocr = None


def ocr(img, escala=2):
    """Devuelve (texto, palabras[(texto, x, y, w, h)]) con coordenadas de la imagen recibida."""
    global _idioma_ocr, OCR_DISPONIBLE
    if not OCR_DISPONIBLE:
        return "", []
    grande = cv2.resize(img, None, fx=escala, fy=escala, interpolation=cv2.INTER_CUBIC)
    pil = Image.fromarray(cv2.cvtColor(grande, cv2.COLOR_BGR2RGB))
    idiomas = [_idioma_ocr] if _idioma_ocr else ["en-US", "en", "es-MX", "es-ES", "es"]
    for idioma in idiomas:
        try:
            r = asyncio.run(winocr.recognize_pil(pil, idioma))
        except Exception:
            continue
        _idioma_ocr = idioma
        palabras = []
        for linea in getattr(r, "lines", []) or []:
            for p in getattr(linea, "words", []) or []:
                b = p.bounding_rect
                palabras.append((p.text, b.x / escala, b.y / escala, b.width / escala, b.height / escala))
        return (getattr(r, "text", "") or ""), palabras
    registrar("El lector de texto (OCR de Windows) no funciona: sigo sin leer el contador")
    OCR_DISPONIBLE = False
    return "", []


def leer_contador(img=None):
    """[actuales, máximo] de "219/500 Candies", o None."""
    img = pantalla() if img is None else img
    texto, _ = ocr(vision.recorte(img, vision.ZONA_CONTADOR))
    texto = re.sub(r"(?i)c\s*a\s*n.*$", "", texto)
    texto = re.sub(r"[oO]", "0", texto)
    texto = re.sub(r"[lI|]", "1", texto)
    texto = re.sub(r"[^\d/]", "", texto)      # "5.00" -> "500"
    m = re.search(r"(\d+)/(\d+)", texto)
    if m:
        a, b = int(m.group(1)), int(m.group(2))
        if 0 < b and a <= b:
            estados.put(("caramelos", (a, b)))
            return [a, b]
    return None


def leer_mensajes(img=None):
    img = pantalla() if img is None else img
    return ocr(vision.recorte(img, vision.ZONA_MENSAJES))[0]


def tienda_abierta(img=None):
    img = pantalla() if img is None else img
    texto = ocr(vision.recorte(img, vision.ZONA_TITULO_TIENDA))[0]
    return re.search(r"(?i)hall[o0]ween|sh[o0]p", texto) is not None


def caramelos_tienda():
    texto = re.sub(r"\D", "", ocr(vision.recorte(pantalla(), vision.ZONA_CARAMELOS_TIENDA), 3)[0])
    return int(texto) if texto else -1


# ======================= el macro =======================

class Macro:
    def __init__(self):
        self.cfg = cargar_config()
        self.activo = threading.Event()
        self.hilo = None
        self.lleno = False
        self.proxima_habilidad = 0.0
        self.vueltas = 0
        self.puertas = 0
        self.compras = 0
        # grabación
        self.grabando = False
        self.segmentos = []
        self.teclas_grabando = set()
        self.t_segmento = 0.0
        self.pared_actual = False
        self.norte_grabado = None
        self.f_pulsadas = set()

    # ---------- control ----------
    def sigue(self):
        if not self.activo.is_set():
            return False
        if not roblox_activo():
            registrar("Roblox dejó de estar en primer plano: me detengo")
            self.activo.clear()
            return False
        return True

    def esperar(self, segundos):
        fin = time.perf_counter() + segundos
        while time.perf_counter() < fin:
            if not self.sigue():
                return False
            time.sleep(0.02)
        return True

    def lanzar(self, funcion):
        if self.grabando or (self.hilo and self.hilo.is_alive()):
            return
        if not activar_roblox():
            registrar("No encuentro la ventana de Roblox")
            return
        self.activo.set()
        self.hilo = threading.Thread(target=self._envolver, args=(funcion,), daemon=True)
        self.hilo.start()

    def _envolver(self, funcion):
        try:
            funcion()
        except Exception as e:
            registrar(f"Error: {e!r}")
        finally:
            soltar_todo()
            self.activo.clear()
            estados.put(("activo", False))

    def iniciar_parar(self):
        if self.activo.is_set():
            self.activo.clear()
            registrar("Parando...")
            return
        if not os.path.exists(ARCHIVO_RUTA):
            registrar("Primero graba la ruta con F1")
            return
        estados.put(("activo", True))
        self.lanzar(self.bucle)

    # ---------- slots ----------
    def equipar(self, n):
        """Equipa el slot n solo si no lo está (pulsarlo estando equipado lo guarda)."""
        for _ in range(4):
            if vision.slot_equipado(pantalla()) == n:
                return True
            pulsar(str(n % 10))
            if not self.esperar(0.5):
                return False
        registrar(f"No pude confirmar que el slot {n} esté equipado")
        return True

    def habilidad_si_toca(self):
        minutos = self.cfg["habilidad_cada_min"]
        if minutos <= 0 or time.time() < self.proxima_habilidad:
            return True
        self.proxima_habilidad = time.time() + minutos * 60
        registrar(f"Usando la habilidad {self.cfg['tecla_habilidad'].upper()}")
        if not self.equipar(self.cfg["slot_habilidad"]):
            return False
        pulsar(self.cfg["tecla_habilidad"], 0.3)
        if not self.esperar(2.5):
            return False
        # de vuelta a la bolsa: con la fruta en la mano, E sería un ataque
        return self.equipar(self.cfg["slot_bolsa"])

    # ---------- puertas ----------
    def tocar_puerta(self):
        if not self.equipar(self.cfg["slot_bolsa"]):
            return False
        antes = leer_contador()
        pulsar("e", self.cfg["mantener_e"])
        resultado = ""
        fin = time.perf_counter() + 2.0
        while OCR_DISPONIBLE and time.perf_counter() < fin and not resultado:
            img = pantalla()
            c = leer_contador(img)
            if c and antes and c[0] != antes[0]:
                dif = c[0] - antes[0]
                resultado = f"+{dif} caramelos" if dif > 0 else f"te robaron {-dif}"
                self.puertas += 1
                if c[0] >= c[1]:
                    self.lleno = True
                break
            if re.search(r"(?i)full|reached", leer_mensajes(img)):
                resultado, self.lleno = "bolsa llena", True
                break
            time.sleep(0.15)
        if not OCR_DISPONIBLE:
            resultado = "tocada (sin OCR no sé el resultado)"
        registrar("Puerta: " + (resultado or "ya visitada o sin respuesta"))
        estados.put(("stats", (self.vueltas, self.puertas, self.compras)))
        return self.esperar(self.cfg["espera_tras_caramelos"] if "caramelos" in resultado else 0.3)

    # ---------- ruta ----------
    def recorrer(self, ruta):
        rearme = self.cfg["rearme_puerta"]
        armado, t_ultimo_toque, tiempo_ruta = True, -1e9, 0.0
        for n, seg in enumerate(ruta["segmentos"], start=1):
            teclas = seg["teclas"]
            duracion = seg["seg"] + (self.cfg["margen_pared"] if seg.get("pared") else 0)
            bajar(teclas)
            t0 = time.perf_counter()
            proximo_escaneo = 0.0
            while True:
                ahora = time.perf_counter()
                hecho = ahora - t0
                if hecho >= duracion:
                    break
                if not self.sigue():
                    subir(teclas)
                    return False
                if (self.cfg["buscar_puertas"] and teclas and not self.lleno
                        and duracion - hecho > 0.15 and ahora >= proximo_escaneo):
                    proximo_escaneo = ahora + 0.08
                    if not vision.knock_visible(pantalla()):
                        armado = True
                    elif armado or (tiempo_ruta + hecho) - t_ultimo_toque > rearme:
                        pausa = time.perf_counter()
                        subir(teclas)
                        if not self.tocar_puerta():
                            return False
                        bajar(teclas)
                        t0 += time.perf_counter() - pausa   # el tramo sigue donde se quedó
                        t_ultimo_toque = tiempo_ruta + (time.perf_counter() - t0)
                        armado = False
                        continue
                time.sleep(0.004)
            subir(teclas)
            tiempo_ruta += duracion
        return True

    def bucle(self):
        with open(ARCHIVO_RUTA, encoding="utf-8") as f:
            ruta = json.load(f)
        self.vueltas = self.puertas = self.compras = 0
        self.lleno = False
        self.proxima_habilidad = time.time() + 2
        registrar(f"Empiezo: ruta de {len(ruta['segmentos'])} tramos")
        if not self.equipar(self.cfg["slot_bolsa"]):
            return
        while self.sigue():
            c = leer_contador()
            if c and c[0] >= c[1]:
                self.lleno = True
            if self.lleno:
                if not self.cfg["articulo"]:
                    registrar("Bolsa llena y no hay artículo configurado: me detengo")
                    return
                compradas = self.comprar()
                if compradas is None:
                    return
                if compradas == 0:
                    registrar("La bolsa está llena pero no pude comprar: me detengo")
                    return
                self.compras += 1
                self.lleno = False
                if self.cfg["parar_tras_comprar"]:
                    registrar("Compra hecha: me detengo")
                    return
            if not self.habilidad_si_toca():
                return
            if self.cfg["corregir_camara"] and not self.alinear_camara(ruta.get("norte_x")):
                return
            registrar(f"Vuelta {self.vueltas + 1}")
            if not self.recorrer(ruta):
                return
            self.vueltas += 1
            estados.put(("stats", (self.vueltas, self.puertas, self.compras)))
        registrar(f"Parado tras {self.vueltas} vueltas, {self.puertas} puertas y {self.compras} compras")

    # ---------- cámara ----------
    def girar(self, dx):
        pydirectinput.mouseDown(button="right")
        time.sleep(0.04)
        restante = int(dx)
        while restante:
            paso = max(-20, min(20, restante))
            raton_relativo(paso, 0)
            restante -= paso
            time.sleep(0.005)
        time.sleep(0.04)
        pydirectinput.mouseUp(button="right")
        time.sleep(0.15)

    def alinear_camara(self, objetivo):
        """Gira hasta que la N de la brújula quede donde estaba al grabar."""
        if objetivo is None:
            registrar("La ruta se grabó sin ver la N: no corrijo la cámara")
            return True
        factor, ultimo = self.cfg["factor_giro"], 0
        for _ in range(15):
            if not self.sigue():
                return False
            x = vision.norte_x(pantalla())
            if x is None:
                if ultimo == 0:
                    registrar("No veo la N de la brújula: no corrijo la cámara")
                    return True
                self.girar(-ultimo)      # se pasó: deshace y prueba más fino
                factor /= 2
                ultimo = 0
                continue
            dif = x - objetivo
            if abs(dif) <= 6:
                return True
            paso = round(dif * factor) or (2 if dif > 0 else -2)
            if ultimo and (paso > 0) != (ultimo > 0):
                factor /= 2
            ultimo = max(-200, min(200, paso))
            self.girar(ultimo)
        return True

    # ---------- compra ----------
    def comprar(self):
        """Devuelve cuántos compró, o None si se paró."""
        articulo = self.cfg["articulo"]
        if articulo not in ARTICULOS:
            registrar(f"No conozco el artículo '{articulo}' (revisa config.json)")
            return 0
        if not OCR_DISPONIBLE:
            registrar("Sin OCR no puedo comprar")
            return 0
        precio = ARTICULOS[articulo]
        if not self.equipar(self.cfg["slot_bolsa"]):
            return None
        abierta = False
        for _ in range(2):
            pulsar("e", self.cfg["mantener_e"])
            fin = time.perf_counter() + 3
            while time.perf_counter() < fin and not abierta:
                abierta = tienda_abierta()
                if not abierta and not self.esperar(0.25):
                    return None
            if abierta:
                break
        if not abierta:
            registrar("No se abrió la tienda (¿estoy junto a la bruja?)")
            return 0
        compradas, fallos = 0, 0
        while self.sigue():
            antes = caramelos_tienda()
            if 0 <= antes < precio:
                break
            pos = self.buscar_articulo(articulo)
            if not pos:
                registrar(f"No encuentro '{articulo}' en la tienda")
                break
            clic(*pos)
            time.sleep(0.7)
            self.confirmar()
            time.sleep(0.8)
            despues = caramelos_tienda()
            if antes >= 0 and 0 <= despues < antes:
                compradas, fallos = compradas + 1, 0
                registrar(f"Comprado x{compradas}, quedan {despues} caramelos")
            else:
                fallos += 1
                if fallos >= 2:
                    break
            if not self.cfg["comprar_todo"] and compradas >= 1:
                break
        # cerrar la tienda: E otra vez y, si sigue abierta, un paso atrás y adelante
        pulsar("e", self.cfg["mantener_e"])
        time.sleep(0.6)
        if tienda_abierta():
            pulsar("s", 0.6)
            pulsar("w", 0.6)
        registrar(f"Compra terminada: {compradas} x {articulo}")
        return compradas if self.activo.is_set() else None

    def buscar_articulo(self, articulo):
        nombre = articulo.lower().replace(" ", "")
        corto = CLAVES.get(articulo, nombre)
        pydirectinput.moveTo(960, 600)
        rueda(15)                       # arriba del todo
        time.sleep(0.4)
        x0, y0 = vision.ZONA_ITEMS[:2]
        for _ in range(14):
            texto, palabras = ocr(vision.recorte(pantalla(), vision.ZONA_ITEMS), 1)
            # agrupa palabras por línea (misma altura aproximada)
            lineas = {}
            for (t, x, y, w, h) in palabras:
                lineas.setdefault(round(y / 12), []).append((t, x, y, w, h))
            for objetivo in (nombre, corto):
                for ps in lineas.values():
                    junto = "".join(p[0] for p in ps).lower()
                    if objetivo in junto:
                        xs = [p[1] for p in ps] + [p[1] + p[3] for p in ps]
                        return (x0 + (min(xs) + max(xs)) / 2, y0 + ps[0][2] + ps[0][4] / 2)
            pydirectinput.moveTo(960, 600)
            raton_relativo(1, 0)
            rueda(-1)
            time.sleep(0.45)
            if not self.sigue():
                return None
        return None

    def confirmar(self):
        _, palabras = ocr(pantalla(), 1)
        for (t, x, y, w, h) in palabras:
            if x > 1500 and y < 450:      # la ventanita del macro
                continue
            if re.fullmatch(r"(?i)(buy|purchase|confirm|yes|redeem|comprar|confirmar)!?", t.strip()):
                clic(x + w / 2, y + h / 2)
                return

    # ---------- grabación por tramos ----------
    def alternar_grabacion(self):
        if self.activo.is_set():
            return
        if self.grabando:
            self._cerrar_segmento()
            while self.segmentos and not self.segmentos[-1]["teclas"]:
                self.segmentos.pop()      # quita la espera final
            while self.segmentos and not self.segmentos[0]["teclas"]:
                self.segmentos.pop(0)     # y la del principio
            self.grabando = False
            with open(ARCHIVO_RUTA, "w", encoding="utf-8") as f:
                json.dump({"norte_x": self.norte_grabado, "segmentos": self.segmentos}, f, indent=1)
            total = sum(s["seg"] for s in self.segmentos)
            paredes = sum(1 for s in self.segmentos if s.get("pared"))
            registrar(f"Ruta guardada: {len(self.segmentos)} tramos, {total:.1f} s, {paredes} paredes")
            estados.put(("grabando", False))
            return
        if not activar_roblox():
            registrar("No encuentro la ventana de Roblox")
            return
        self.norte_grabado = vision.norte_x(pantalla())
        self.segmentos = []
        self.teclas_grabando = set()
        self.t_segmento = time.perf_counter()
        self.pared_actual = False
        self.grabando = True
        estados.put(("grabando", True))
        registrar("GRABANDO: camina la ruta. F2 al chocar con una pared. F1 para terminar."
                  + ("" if self.norte_grabado else " (No veo la N: la cámara no se corregirá)"))

    def _cerrar_segmento(self):
        ahora = time.perf_counter()
        dur = round(ahora - self.t_segmento, 3)
        if dur > 0.02:
            self.segmentos.append({"teclas": sorted(self.teclas_grabando), "seg": dur,
                                   "pared": self.pared_actual})
        self.t_segmento = ahora
        self.pared_actual = False

    def evento_tecla(self, ev):
        """Recibe todas las teclas físicas (librería keyboard)."""
        if ev.scan_code in SCAN_F:
            self.tecla_funcion(ev)
            return
        if not self.grabando or ev.scan_code not in SCAN_MOVIMIENTO:
            return
        tecla = SCAN_MOVIMIENTO[ev.scan_code]
        nuevas = set(self.teclas_grabando)
        if ev.event_type == "down":
            nuevas.add(tecla)
        else:
            nuevas.discard(tecla)
        if nuevas != self.teclas_grabando:
            self._cerrar_segmento()
            self.teclas_grabando = nuevas

    def tecla_funcion(self, ev):
        nombre = SCAN_F[ev.scan_code]
        if ev.event_type != "down":
            self.f_pulsadas.discard(nombre)
            return
        if nombre in self.f_pulsadas:      # auto-repetición al mantenerla
            return
        self.f_pulsadas.add(nombre)
        if nombre == "f2":
            self.marcar_pared()            # inmediato, para que quede en el tramo correcto
            return
        accion = {
            "f1": self.alternar_grabacion,
            "f3": self.iniciar_parar,
            "f4": lambda: self.lanzar(self.probar_compra),
            "f6": lambda: self.lanzar(self.probar_camara),
            "f7": self.diagnostico,
            "f8": self.salir,
        }[nombre]
        # en otro hilo, para no frenar la lectura del teclado
        threading.Thread(target=accion, daemon=True).start()

    def salir(self):
        self.activo.clear()
        soltar_todo()
        estados.put(("salir", None))

    def marcar_pared(self):
        if not self.grabando:
            return
        if self.teclas_grabando:
            self.pared_actual = True
        elif self.segmentos:
            # ya soltaste las teclas: marca el último tramo con movimiento
            for s in reversed(self.segmentos):
                if s["teclas"]:
                    s["pared"] = True
                    break
        registrar("Pared marcada")

    # ---------- pruebas ----------
    def probar_camara(self):
        objetivo = None
        if os.path.exists(ARCHIVO_RUTA):
            with open(ARCHIVO_RUTA, encoding="utf-8") as f:
                objetivo = json.load(f).get("norte_x")
        self.alinear_camara(objetivo or 960)
        registrar("Prueba de cámara terminada")

    def probar_compra(self):
        n = self.comprar()
        registrar(f"Prueba de compra: {n} comprados")

    def diagnostico(self):
        img = pantalla()
        cv2.imwrite(os.path.join(AQUI, "diagnostico.png"), img)
        c = leer_contador(img) if OCR_DISPONIBLE else None
        texto = (f"Contador: {c[0]}/{c[1]}" if c else "Contador: no leído" + ("" if OCR_DISPONIBLE else " (sin OCR)")) + \
                f" | Knock: {'sí' if vision.knock_visible(img) else 'no'}" + \
                f" | N en x={vision.norte_x(img)}" + \
                f" | slots={len(vision.slots(img))}, equipado={vision.slot_equipado(img)}"
        registrar(texto + "  (guardado diagnostico.png)")


# ======================= ventanita de estado =======================

def ventana(macro):
    import tkinter as tk
    raiz = tk.Tk()
    raiz.title("GPO Halloween")
    raiz.overrideredirect(True)
    raiz.attributes("-topmost", True)
    raiz.configure(bg="#15121F")
    raiz.geometry("+1560+30")
    fuente = ("Segoe UI", 9)
    tk.Label(raiz, text="GPO HALLOWEEN · python", fg="#FF7A1A", bg="#15121F",
             font=("Bahnschrift SemiBold", 11)).pack(anchor="w", padx=10, pady=(8, 0))
    caramelos = tk.Label(raiz, text="— / —", fg="#F2E9DC", bg="#15121F", font=("Bahnschrift", 20))
    caramelos.pack(anchor="w", padx=10)
    estado = tk.Label(raiz, text="F1 grabar · F3 iniciar · F8 salir", fg="#7CDB5A", bg="#15121F",
                      font=fuente, wraplength=330, justify="left")
    estado.pack(anchor="w", padx=10)
    stats = tk.Label(raiz, text="", fg="#8E88A8", bg="#15121F", font=fuente)
    stats.pack(anchor="w", padx=10, pady=(0, 8))

    def mover(ev):
        raiz.geometry(f"+{ev.x_root - 20}+{ev.y_root - 10}")
    raiz.bind("<B1-Motion>", mover)

    def revisar():
        try:
            while True:
                tipo, dato = estados.get_nowait()
                if tipo == "estado":
                    estado.config(text=dato)
                elif tipo == "caramelos":
                    caramelos.config(text=f"{dato[0]} / {dato[1]}")
                elif tipo == "stats":
                    stats.config(text=f"vueltas {dato[0]}  ·  puertas {dato[1]}  ·  compras {dato[2]}")
                elif tipo == "grabando":
                    estado.config(fg="#E0475B" if dato else "#7CDB5A")
                elif tipo == "salir":
                    raiz.destroy()
                    return
        except queue.Empty:
            pass
        raiz.after(150, revisar)
    raiz.after(150, revisar)
    raiz.mainloop()


def main():
    if not ES_WINDOWS:
        print("Este macro solo funciona en Windows (para probar la visión: python vision.py captura.png)")
        return
    macro = Macro()
    keyboard.hook(macro.evento_tecla)

    try:
        os.remove(ARCHIVO_REGISTRO)
    except OSError:
        pass
    registrar("Listo. OCR: " + ("sí" if OCR_DISPONIBLE else "NO (instala winocr para leer el contador y comprar)"))
    ventana(macro)
    soltar_todo()


if __name__ == "__main__":
    main()
