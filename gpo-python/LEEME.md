# GPO Halloween: macro en Python + OpenCV

Recorre una ruta de puertas en Spooksville, toca cada puerta en cuanto ve el aviso **"E Knock"**, usa la habilidad C cada X minutos y, cuando la bolsa se llena, compra con la bruja. Solo **mira la pantalla y pulsa teclas**: no se mete dentro del juego.

> Usar macros en GPO puede costarte un baneo. Pruébalo primero en una cuenta secundaria.

## Instalación (una vez)
1. Instala **Python** desde https://www.python.org/downloads. En la primera pantalla del instalador, **marca "Add python.exe to PATH"**.
2. Descomprime esta carpeta donde quieras (por ejemplo, en el escritorio).
3. Doble clic en **`instalar.bat`** y espera a que termine.

## Uso
Doble clic en **`iniciar.bat`**. Se abre una consola, que puedes minimizar pero no cerrar, y una ventanita arriba a la derecha.

| Tecla | Qué hace |
|---|---|
| **F1** | Grabar / terminar la ruta |
| **F2** | Mientras grabas: "este tramo acaba **contra una pared**" |
| **F3** | Iniciar / parar |
| **F4** | Probar la compra (pegado a la bruja) |
| **F6** | Probar la corrección de cámara |
| **F7** | Diagnóstico: guarda `diagnostico.png` y dice qué ve |
| **F8** | Salir |

Los ajustes están en **`config.json`**, que se crea al abrirlo la primera vez. Ábrelo con el Bloc de notas: `articulo`, `comprar_todo`, `habilidad_cada_min`, etc.

## Cómo grabar la ruta
La ruta se guarda como **tramos** ("W+D durante 3,4 s"). Los tramos que marcas con **F2** se alargan medio segundo al repetirlos: así el personaje **siempre llega a tocar la pared**, y cualquier desvío del tramo anterior se corrige ahí.

1. Ponte **pegado al caldero**, con la **bolsa en la mano** y la cámara **mirando al Norte** (la N blanca arriba en el centro).
2. Pulsa **F1** y camina la ruta **pegado a las fachadas**. No hace falta pulsar E: el macro toca las puertas solo.
3. Cada vez que **choques con una esquina o una pared**, pulsa **F2** (mientras sigues empujando contra ella o justo después).
4. Termina **chocando contra el caldero**, pulsa **F2** y luego **F1**.
5. **No muevas la cámara** mientras grabas.

En `ruta-recomendada.png` (en la carpeta del macro de AutoHotkey) está el orden de puertas recomendado, con las esquinas A y B donde conviene chocar.

## Si algo falla
- Pulsa **F7** en el momento del problema y manda **`diagnostico.png`** y **`registro.txt`**. Con la captura se puede probar la detección exactamente como la ve el macro.
- `probar_vision.bat`: arrastra capturas encima para ver qué detecta (aviso Knock, N de la brújula, slot equipado).
