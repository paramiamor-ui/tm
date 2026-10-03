# Macro GPO Halloween (AutoHotkey v2)

Macro automático para recolectar caramelos en Spooksville y canjearlos con la bruja.
Solo **lee la pantalla** (OCR de Windows) y **simula teclado y ratón**. No inyecta nada en el juego.

> Usar macros en GPO puede costarte un baneo. Si no quieres arriesgar tu cuenta principal, úsalo en una secundaria.

## Qué hace solo
- Toca cada puerta de tu ruta con E y lee el resultado:
  - **Caramelos ganados (de 1 a 15) o robados**: cualquier cambio en el contador cuenta como puerta tocada y la marca como en recarga.
  - **"You already visited… Come back in 124s"**: anota esos 124 s y no la vuelve a tocar hasta que pasen.
- Lee el contador **"X/500 Candies"**. Cuando la bolsa está llena (o sale *"Your candy basket is full!"*), deja de tocar puertas y termina la vuelta hasta la bruja.
- **Compra solo:** abre la Halloween Shop, hace scroll hasta el artículo, lo compra (todas las veces que alcancen los caramelos) y cierra la tienda.
- Si todas las puertas están en recarga, espera junto a la bruja.
- **Cada 5 minutos usa la habilidad C:** saca la fruta (slot 3), pulsa C y vuelve a la bolsa (slot 2).
  Lo hace al empezar y luego en la siguiente parada (una puerta o el caldero), nunca caminando.
  Se ajusta en `HABILIDAD_CADA_MIN`, `SLOT_HABILIDAD`, `TECLA_HABILIDAD` y `ESPERA_HABILIDAD`; con `HABILIDAD_CADA_MIN := 0` se desactiva.
- **Corrige la cámara al Norte** antes de cada vuelta: busca la "N" blanca de la brújula (`Lib/norte.png`) y la centra. Solo corrige desvíos pequeños; si no ve la N, no gira.
- Si Roblox se desconecta, pulsa "Reconnect" si aparece y se detiene.

Lo único que tienes que hacer tú es **grabar la ruta una vez**, porque un macro externo no puede saber en qué coordenadas está tu personaje.

## Requisitos
- Windows 10/11 y **AutoHotkey v2** (https://www.autohotkey.com).
- La carpeta completa: `GPO_Halloween.ahk` **y la carpeta `Lib`** (dentro va `OCR.ahk`, el lector de pantalla).
- Roblox en **pantalla completa a 1920×1080**.
- La **bolsa de caramelos equipada**.

## Teclas
| Tecla | Acción |
|---|---|
| F1 | Grabar / terminar la **ruta** de puertas |
| F2 | Grabar / terminar una compra manual (plan B, solo si la compra automática falla) |
| F3 | Iniciar / parar |
| F4 | Probar solo la compra (ponte junto a la bruja) |
| F6 | Probar el alineado de cámara al Norte |
| F7 | Diagnóstico: muestra qué lee de la pantalla y lo guarda en `diagnostico.txt` |
| F8 | Cerrar el macro |

## Primeros pasos
1. **Prueba la lectura:** mirando al Norte, pulsa **F7** en el juego. Debe mostrar tu contador (por ejemplo `219/500`) y "N en x=…".
   Si dice "NO LEÍDO", mándame el `diagnostico.txt`.
2. **Prueba la cámara:** gira la cámara **un poco** (la N tiene que seguir cerca del centro) y pulsa **F6**. Debe volver a centrar la N.
   Si se pasa de largo o gira muy lento, cambia `FACTOR_GIRO`.
3. **Graba la ruta (F1):**
   - Empieza **pegado al caldero de la bruja**, con la cámara en Norte (pulsa F6 antes).
   - Camina a cada puerta y pulsa **E** delante de ella (cada E es una puerta).
   - **No muevas la cámara** mientras grabas.
   - Termina **chocando otra vez contra el caldero** y pulsa F1.
   - Chocar contra paredes y esquinas en el camino ayuda a que el personaje no se desvíe.
4. **Prueba la compra:** junto a la bruja, pulsa **F4**.
5. Abre el `.ahk` con el Bloc de notas y elige en **CONFIGURACIÓN**:
   - `ARTICULO`: el artículo, escrito igual que en la tienda (por ejemplo `"Blood Scythe"`). Si lo dejas como `""`, solo recolecta.
   - `PARAR_TRAS_COMPRAR`: `true` compra y se detiene; `false` sigue en bucle.
   - `COMPRAR_TODO`: `true` gasta todos los caramelos en el artículo; `false` compra solo uno cada vez.
6. Vuelve al caldero y pulsa **F3**. Si cambias de ventana, se detiene solo.

## Si algo falla
- **No lee el contador o los mensajes:** pulsa F7 en esa situación y mándame `diagnostico.txt` junto con una captura.
- **No encuentra el artículo o no confirma la compra:** mándame una captura justo después de hacer clic en el artículo.
- **El personaje se desvía con las vueltas:** graba una ruta más corta o con más choques contra paredes.

Créditos: lectura de pantalla con [OCR de Descolada](https://github.com/Descolada/OCR) (licencia MIT, `Lib/OCR-LICENSE.txt`).
