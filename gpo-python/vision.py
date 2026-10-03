"""Detección en pantalla para el macro de GPO Halloween.

Todas las funciones reciben la pantalla completa como imagen BGR de numpy
(1920x1080) y no tocan el teclado ni el ratón, así que se pueden probar con
capturas guardadas: python vision.py captura1.png captura2.png ...
"""
import os

import cv2
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))


def _plantilla(nombre):
    """Carga una plantilla PNG con fondo magenta (= transparente) y devuelve
    la máscara de sus píxeles blancos como float32 (1 = blanco)."""
    img = cv2.imread(os.path.join(AQUI, "assets", nombre))
    if img is None:
        raise FileNotFoundError(f"Falta assets/{nombre}")
    mascara = np.all(img == 255, axis=2).astype(np.float32)
    return mascara


KNOCK = _plantilla("knock.png")      # 98x34: recuadro de la "E" + "Knock"
NORTE = _plantilla("norte.png")      # 17x21: letra "N" del centro de la brújula

# Puntos del interior del recuadro de la E que tienen que ser oscuros
# (descartan zonas blancas grandes, como ventanas de error).
KNOCK_OSCUROS = [(6, 8), (22, 8), (6, 24), (22, 24), (14, 26), (22, 16)]


def _buscar_blancos(img, plantilla, x0, y0, x1, y1, umbral=185, minimo=0.97):
    """Busca la plantilla de píxeles blancos dentro del rectángulo.
    Devuelve una lista de (x, y) en coordenadas de pantalla, mejor primero."""
    zona = img[y0:y1, x0:x1]
    blancos = (zona.min(axis=2) >= umbral).astype(np.float32)
    total = plantilla.sum()
    res = cv2.matchTemplate(blancos, plantilla, cv2.TM_CCORR)
    ys, xs = np.where(res >= total * minimo)
    orden = np.argsort(-res[ys, xs])
    return [(int(xs[i]) + x0, int(ys[i]) + y0) for i in orden]


def knock_visible(img):
    """¿Está en pantalla el aviso "E Knock" de una puerta?"""
    for (x, y) in _buscar_blancos(img, KNOCK, 450, 250, 1450, 750)[:20]:
        if all(img[y + dy, x + dx].max() < 150 for dx, dy in KNOCK_OSCUROS):
            return True
    return False


def norte_x(img):
    """Posición x (centro) de la "N" blanca de la brújula, o None.
    Solo la letra del centro de la brújula es blanca pura, así que si la
    encuentra es que la cámara mira casi al Norte."""
    h, w = NORTE.shape
    for (x, y) in _buscar_blancos(img, NORTE, 700, 5, 1220, 60, umbral=185, minimo=0.95):
        # descarta "NE"/"NW": no puede haber otra letra blanca pegada
        der = img[y + 4:y + h - 4, x + w + 1:x + w + 20].min(axis=2)
        izq = img[y + 4:y + h - 4, max(0, x - 20):x - 1].min(axis=2)
        if (der >= 215).sum() < 4 and (izq >= 215).sum() < 4:
            return x + w // 2
    return None


def slots(img):
    """Centros x de los slots de la barra de abajo (detecta los números 1..0)."""
    banda = img[999:1015, 560:1360].min(axis=2) > 200
    xs = np.where(banda.any(axis=0))[0]
    grupos = []
    for x in xs:
        if grupos and x - grupos[-1][-1] <= 4:
            grupos[-1].append(x)
        else:
            grupos.append([x])
    return [560 + int(np.mean(g)) for g in grupos]


def slot_equipado(img):
    """Número (1..10) del slot equipado (borde blanco), o None."""
    for i, c in enumerate(slots(img), start=1):
        izq = img[1012:1062, c - 30:c - 23].min(axis=2) > 215
        der = img[1012:1062, c + 28:c + 35].min(axis=2) > 215
        if izq.sum() > 40 and der.sum() > 40:
            return i
    return None


# Zonas para el lector de texto (OCR): (x, y, ancho, alto)
ZONA_CONTADOR = (820, 850, 280, 55)            # "219/500 Candies"
ZONA_MENSAJES = (450, 155, 1020, 90)           # "You got +5 Candies!" ...
ZONA_TITULO_TIENDA = (450, 215, 500, 70)       # "Halloween Shop"
ZONA_CARAMELOS_TIENDA = (1300, 250, 120, 45)   # caramelos arriba a la derecha de la tienda
ZONA_ITEMS = (500, 290, 920, 580)              # tarjetas de la tienda


def recorte(img, zona):
    x, y, w, h = zona
    return img[y:y + h, x:x + w]


if __name__ == "__main__":
    import sys
    for ruta in sys.argv[1:]:
        img = cv2.imread(ruta)
        if img is None:
            print(ruta, "no se pudo abrir")
            continue
        if img.shape[1] < 1900:
            print(ruta, "no es una captura de 1920x1080, se omite")
            continue
        print(f"{os.path.basename(ruta):14s} knock={knock_visible(img)!s:5s} "
              f"norte_x={norte_x(img)!s:5s} slots={len(slots(img))} equipado={slot_equipado(img)}")
