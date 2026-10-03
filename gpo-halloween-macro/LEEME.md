# Macro GPO Halloween (AutoHotkey v2)

Macro para recolectar caramelos tocando puertas en Spooksville y canjearlos con la bruja.
Funciona **grabando** lo que haces una vez y **repitiéndolo** en bucle. Solo simula teclado y ratón.

> Usar macros en GPO puede costarte un baneo. Si no quieres arriesgar tu cuenta principal, úsalo en una secundaria.

## Requisitos
- Windows y **AutoHotkey v2** (https://www.autohotkey.com).
- Roblox en **pantalla completa a 1920×1080**, siempre igual que cuando grabaste.
- La **bolsa de caramelos equipada** (ranura 2).

## Teclas
| Tecla | Acción |
|---|---|
| F1 | Empezar / terminar la grabación de la **ruta** de puertas |
| F2 | Empezar / terminar la grabación de la **compra** con la bruja |
| F3 | Iniciar / parar el macro |
| F4 | Probar solo la compra |
| F8 | Cerrar el macro |

## Cómo usarlo
1. Guarda `GPO_Halloween.ahk` en una carpeta y dale doble clic.
2. **Punto de inicio fijo:** ponte pegado al caldero de la bruja y gira la cámara hasta que la brújula de arriba marque **N** en el centro.
   La ruta y la compra deben empezar **siempre** así.
3. **Graba la ruta (F1):** camina con WASD hasta cada puerta, mantén **E** para tocar (Knock) y sigue con la siguiente.
   Al final **vuelve a chocar contra el caldero** y pulsa F1 otra vez.
   - **No muevas la cámara** (clic derecho) mientras grabas.
   - Chocar contra paredes o esquinas en el camino ayuda a que el personaje no se desvíe con cada vuelta.
4. **Graba la compra (F2):** desde el caldero, pulsa E para abrir la tienda, haz scroll y clic en el artículo, confirma, cierra la tienda y pulsa F2.
   Pruébala con **F4**.
5. Abre el archivo con el Bloc de notas y ajusta la **CONFIGURACIÓN** de arriba:
   - `COMPRAR_CADA_VUELTAS`: mira cuántos caramelos ganas por vuelta (cada puerta da +5) y divide 500 entre ese número.
   - `PARAR_TRAS_COMPRAR`: `true` = compra una vez y se detiene; `false` = sigue en bucle.
6. Vuelve al punto de inicio y pulsa **F3**.

Si cambias a otra ventana, el macro se detiene solo y suelta todas las teclas.
Si con las vueltas el personaje se va desviando, vuelve a grabar la ruta con más choques contra paredes, o más corta.
