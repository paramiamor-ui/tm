#Requires AutoHotkey v2.0
#SingleInstance Force
#Include <OCR>   ; Lib\OCR.ahk (Descolada, MIT) - lee texto de la pantalla
; ============================================================
;  GPO Halloween - macro automático de caramelos
;  F1 = grabar / terminar la RUTA de puertas (una sola vez)
;  F2 = grabar / terminar la COMPRA (opcional, plan B)
;  F3 = iniciar / parar el macro
;  F4 = probar solo la compra
;  F6 = probar el alineado de cámara al Norte
;  F7 = diagnóstico (qué está leyendo de la pantalla)
;  F8 = cerrar el macro
;  Todo esto también está en la ventana del macro (lo que elijas ahí se
;  guarda en config.ini).
; ============================================================

; ---------------- CONFIGURACIÓN ----------------
; El artículo, el modo de compra, la habilidad y la cámara se eligen en la ventana.
; Cuánto tiempo (ms) se mantiene E para tocar una puerta o hablar con la bruja.
MANTENER_E := 400
; Espera (ms) tras tocar una puerta, para que se acabe el aturdimiento.
ESPERA_TRAS_TOCAR := 1500
; Recarga de una puerta (s) si el juego no dice "Come back in Xs".
RECARGA_PUERTA := 180
; Sensibilidad del giro de cámara al alinear al Norte (bájalo si se pasa de largo).
FACTOR_GIRO := 0.5
; Habilidad periódica: saca la fruta (slot 3), usa C y vuelve a la bolsa (slot 2).
SLOT_HABILIDAD := "3"
TECLA_HABILIDAD := "c"
MANTENER_HABILIDAD := 300    ; ms que se mantiene C
ESPERA_HABILIDAD := 2500     ; ms de animación antes de volver a la bolsa
SLOT_BOLSA := "2"
; ------------------------------------------------

; Artículos de la Halloween Shop en el orden de la tienda: [nombre, precio]
ARTICULOS := [
    ["SP Reset Essence", 10], ["Devil Fruit Remover", 25], ["Race Reroll x5", 25],
    ["Custom Spirit Color", 50], ["Lantern", 50], ["Trading Sign", 100],
    ["Joker Costume", 100], ["Ghost Face Costume", 100], ["Plague Doctor Costume", 100],
    ["Legendary Fruit Chest Blueprint", 100], ["Mummy Wrappings", 100], ["Devil Fruit Journal", 125],
    ["Wizard Costume", 175], ["Frankenstein Costume", 175], ["Shark Costume", 175],
    ["Fruit Bag", 250], ["Rare Fruit Chest", 250], ["Blood Scythe", 500]]
PRECIOS := Map()
for a in ARTICULOS
    PRECIOS[a[1]] := a[2]

; Nombres que en la tienda ocupan dos líneas o que el OCR puede leer mal.
CLAVES := Map("Plague Doctor Costume", "plaguedoctor", "Legendary Fruit Chest Blueprint", "legendaryfruitchest",
    "Race Reroll x5", "racereroll")

ROBLOX := "ahk_exe RobloxPlayerBeta.exe"
TECLAS := ["w", "a", "s", "d", "Space", "e", "q", "c", "LShift", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
ARCHIVO_RUTA := A_ScriptDir "\ruta.txt"
ARCHIVO_COMPRA := A_ScriptDir "\compra.txt"
ARCHIVO_CONFIG := A_ScriptDir "\config.ini"

; Opciones de la ventana (se guardan en config.ini)
MODO := IniRead(ARCHIVO_CONFIG, "opciones", "modo", "inf")                 ; off | 1x | inf
ARTICULO_ELEGIDO := IniRead(ARCHIVO_CONFIG, "opciones", "articulo", "Rare Fruit Chest")
HABILIDAD_MIN := Integer(IniRead(ARCHIVO_CONFIG, "opciones", "habilidad_min", 5))
HABILIDAD_ACTIVA := Integer(IniRead(ARCHIVO_CONFIG, "opciones", "habilidad", 1))
ALINEAR_CAMARA := Integer(IniRead(ARCHIVO_CONFIG, "opciones", "camara", 1))
if !PRECIOS.Has(ARTICULO_ELEGIDO)
    ARTICULO_ELEGIDO := "Rare Fruit Chest"
ARTICULO := "", PARAR_TRAS_COMPRAR := false, COMPRAR_TODO := true, HABILIDAD_CADA_MIN := 0
AplicarOpciones()

; Zonas de la pantalla (1920x1080, pantalla completa)
ZONA_CONTADOR := [820, 850, 280, 55]      ; "219/500 Candies"
ZONA_MENSAJES := [450, 155, 1020, 90]     ; "You got +5 Candies!" / "Come back in 124s" / "basket is full"
ZONA_KNOCK    := [450, 250, 1000, 500]    ; "E Knock" (hasta x=1450: a la derecha va la ventana)
ZONA_TITULO_TIENDA := [450, 215, 500, 70] ; "Halloween Shop"
ZONA_CARAMELOS_TIENDA := [1300, 250, 120, 45] ; "500" arriba a la derecha de la tienda
ZONA_ITEMS    := [500, 290, 920, 580]     ; tarjetas de la tienda
; La letra del centro de la brújula es blanca pura; se busca la "N" como imagen.
IMG_NORTE := A_ScriptDir "\Lib\norte.png"   ; 17x21, fondo magenta = transparente
NORTE_W := 17, NORTE_H := 21

CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
CoordMode "Pixel", "Screen"
SetKeyDelay 10, 30   ; Roblox ignora pulsaciones demasiado rápidas

estado := "parado"   ; parado | grabando | jugando
eventos := []
pulsadas := Map()
inicioGrabacion := 0
archivoGrabando := ""
ih := ""
lleno := false
listoEn := Map()     ; puerta -> A_TickCount en que vuelve a estar disponible
teclasJugando := Map()
compradasUltima := 0
proximaHabilidad := 0
vueltas := 0, compras := 0, puertasTocadas := 0

CrearVentana()
MostrarEstado(FileExist(ARCHIVO_RUTA) ? "Listo. Ponte junto al caldero y pulsa Iniciar."
    : "Primero graba tu ruta de puertas (botón Grabar ruta o F1).")
SetTimer TimerContador, 3000

; ================= LECTURA DE PANTALLA =================

LeerTexto(zona, escala := 2) {
    try return OCR.FromRect(zona[1], zona[2], zona[3], zona[4], {scale: escala}).Text
    catch
        return ""
}

LeerResultado(zona, escala := 1) {
    try return OCR.FromRect(zona[1], zona[2], zona[3], zona[4], {scale: escala})
    catch
        return ""
}

; Devuelve [actuales, máximo] o "" si no se pudo leer.
LeerContador() {
    texto := LeerTexto(ZONA_CONTADOR)
    texto := RegExReplace(texto, "i)c\s*a\s*n.*$")        ; quita "Candies"
    texto := RegExReplace(texto, "[oO]", "0")
    texto := RegExReplace(texto, "[lI|]", "1")
    texto := RegExReplace(texto, "[^\d/]")                  ; quita puntos, comas, espacios ("5.00" -> "500")
    if RegExMatch(texto, "(\d+)/(\d+)", &m) {
        a := Integer(m[1]), b := Integer(m[2])
        if (b > 0 && a <= b) {
            MostrarCaramelos(a, b)
            return [a, b]
        }
    }
    return ""
}

LeerCaramelosTienda() {
    texto := RegExReplace(LeerTexto(ZONA_CARAMELOS_TIENDA, 3), "[^\d]")
    return (texto = "") ? -1 : Integer(texto)
}

TiendaAbierta() => RegExMatch(LeerTexto(ZONA_TITULO_TIENDA), "i)hall[o0]ween|sh[o0]p")

; ================= GRABACIÓN =================

F1:: AlternarGrabacion(ARCHIVO_RUTA, "RUTA")
F2:: AlternarGrabacion(ARCHIVO_COMPRA, "COMPRA")

AlternarGrabacion(archivo, nombre) {
    global
    if (estado = "grabando") {
        if (archivo = archivoGrabando)
            TerminarGrabacion()
        return
    }
    if (estado != "parado" || !ActivarRoblox())
        return
    eventos := []
    pulsadas := Map()
    archivoGrabando := archivo
    inicioGrabacion := A_TickCount
    ih := InputHook("V")
    for k in TECLAS
        ih.KeyOpt("{" k "}", "N")
    ih.OnKeyDown := GrabarTecla.Bind("kd")
    ih.OnKeyUp := GrabarTecla.Bind("ku")
    ih.Start()
    estado := "grabando"
    MostrarEstado("GRABANDO " nombre " - pulsa la misma tecla para terminar")
}

GrabarTecla(tipo, hook, vk, sc) {
    global
    nombre := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (tipo = "kd") {
        if pulsadas.Has(nombre)   ; ignora la auto-repetición al mantener la tecla
            return
        pulsadas[nombre] := true
    } else {
        if !pulsadas.Has(nombre)
            return
        pulsadas.Delete(nombre)
    }
    eventos.Push((A_TickCount - inicioGrabacion) "|" tipo "|" nombre)
}

TerminarGrabacion() {
    global
    ih.Stop()
    t := A_TickCount - inicioGrabacion
    for nombre in pulsadas
        eventos.Push(t "|ku|" nombre)
    texto := ""
    puertas := 0
    for linea in eventos {
        texto .= linea "`n"
        if InStr(linea, "|kd|e")
            puertas++
    }
    if FileExist(archivoGrabando)
        FileDelete archivoGrabando
    FileAppend texto, archivoGrabando
    estado := "parado"
    ActualizarRuta()
    MostrarEstado("Ruta guardada: " Round(t / 1000, 1) " s, " puertas " puertas")
}

#HotIf estado = "grabando"
~LButton:: GrabarRaton("click")
~WheelUp:: GrabarRaton("wheelup")
~WheelDown:: GrabarRaton("wheeldown")
#HotIf

GrabarRaton(tipo) {
    global
    MouseGetPos &x, &y, &ventana
    if (ventana = ui.Hwnd)   ; clic en la ventana del macro (p. ej. el botón de terminar)
        return
    eventos.Push((A_TickCount - inicioGrabacion) "|" tipo "|" x "," y)
}

; ================= CONTROLES =================

F3:: IniciarParar()

IniciarParar() {
    global
    if (estado = "jugando") {
        estado := "parado"
        return
    }
    if (estado != "parado")
        return
    if !FileExist(ARCHIVO_RUTA) {
        MsgBox "Primero graba la ruta con F1."
        return
    }
    if !ActivarRoblox()
        return
    estado := "jugando"
    SetTimer Bucle, -1
}

F4:: Lanzar(ProbarCompra)
F6:: Lanzar(ProbarCamara)

Lanzar(funcion) {
    global
    if (estado != "parado" || !ActivarRoblox())
        return
    estado := "jugando"
    SetTimer funcion, -1
}

ActivarRoblox() {
    if !WinExist(ROBLOX) {
        MsgBox "Abre Roblox primero."
        return false
    }
    WinActivate ROBLOX
    WinWaitActive ROBLOX, , 2
    return true
}

; ================= BUCLE PRINCIPAL =================

Bucle() {
    global
    vueltas := 0, compras := 0, puertasTocadas := 0
    ActualizarStats()
    lleno := false
    proximaHabilidad := A_TickCount
    loop {
        if Desconectado()
            break
        c := LeerContador()
        if (c != "" && c[1] >= c[2])
            lleno := true

        if (lleno && ARTICULO != "") {
            MostrarEstado("Bolsa llena - comprando con la bruja")
            if !Comprar()
                break
            if (compradasUltima = 0) {
                estado := "parado"
                MostrarEstado("La bolsa está llena pero no se pudo comprar - parado (usa F4 y F7 para revisar)")
                return
            }
            compras++
            ActualizarStats()
            lleno := false
            if PARAR_TRAS_COMPRAR {
                estado := "parado"
                MostrarEstado("Terminado: compra hecha (" vueltas " vueltas)")
                return
            }
        } else if lleno {
            estado := "parado"
            MostrarEstado("Bolsa llena (modo sin compras) - parado")
            return
        }

        ; Si todas las puertas están en recarga, espera en la bruja.
        espera := EsperaMinima()
        if (espera > 5000) {
            MostrarEstado("Todas las puertas en recarga - espero " Ceil(espera / 1000) " s")
            if !Esperar(espera)
                break
        }

        if !HabilidadSiToca()
            break
        if (ALINEAR_CAMARA && !AlinearCamara())
            break
        MostrarEstado("Vuelta " (vueltas + 1) " - recorriendo puertas")
        if !Reproducir(ARCHIVO_RUTA, true)
            break
        vueltas++
        ActualizarStats()
    }
    SoltarTodo()
    estado := "parado"
    MostrarEstado("Parado tras " vueltas " vueltas y " compras " compras")
}

; ms hasta que la primera puerta conocida vuelva a estar disponible (0 si alguna ya lo está).
EsperaMinima() {
    global
    if !FileExist(ARCHIVO_RUTA)
        return 0
    total := 0
    loop parse FileRead(ARCHIVO_RUTA), "`n", "`r"
        if InStr(A_LoopField, "|kd|e")
            total++
    if (total = 0)
        return 0
    minimo := ""
    loop total {
        resto := listoEn.Has(A_Index) ? listoEn[A_Index] - A_TickCount : 0
        if (resto <= 0)
            return 0
        minimo := (minimo = "" || resto < minimo) ? resto : minimo
    }
    return minimo
}

; ================= REPRODUCCIÓN =================

; Reproduce un archivo grabado. Con conPuertas, cada E de la ruta se convierte en
; TocarPuerta(n). Devuelve false si se paró (F3 o Roblox perdió el foco).
Reproducir(archivo, conPuertas := false) {
    global
    lineas := StrSplit(Trim(FileRead(archivo), "`r`n"), "`n", "`r")
    base := A_TickCount
    puerta := 0
    teclasJugando := Map()
    for linea in lineas {
        if (linea = "")
            continue
        p := StrSplit(linea, "|")
        t := Integer(p[1])
        while (A_TickCount - base < t) {
            if !SeguirJugando() {
                SoltarTodo()
                return false
            }
            Sleep 5
        }
        if (conPuertas && p[3] = "e" && (p[2] = "kd" || p[2] = "ku")) {
            if (p[2] = "kd") {
                puerta++
                antes := A_TickCount
                for k in teclasJugando
                    SendEvent "{" k " up}"
                if !TocarPuerta(puerta) {
                    SoltarTodo()
                    return false
                }
                for k in teclasJugando
                    SendEvent "{" k " down}"
                base += A_TickCount - antes   ; la ruta continúa donde se quedó
            }
            continue
        }
        switch p[2] {
            case "kd":
                SendEvent "{" p[3] " down}"
                teclasJugando[p[3]] := true
            case "ku":
                SendEvent "{" p[3] " up}"
                if teclasJugando.Has(p[3])
                    teclasJugando.Delete(p[3])
            default:
                xy := StrSplit(p[3], ",")
                RatonRoblox(p[2], Integer(xy[1]), Integer(xy[2]))
        }
    }
    SoltarTodo()
    return SeguirJugando()
}

TocarPuerta(n) {
    global
    if !HabilidadSiToca()
        return false
    if lleno {
        MostrarEstado("Puerta " n " - bolsa llena, volviendo a la bruja")
        return true
    }
    if (listoEn.Has(n) && A_TickCount < listoEn[n]) {
        MostrarEstado("Puerta " n " - en recarga (" Ceil((listoEn[n] - A_TickCount) / 1000) " s)")
        return true
    }
    visto := RegExMatch(LeerTexto(ZONA_KNOCK, 1), "i)kn[o0]ck")
    MostrarEstado("Puerta " n (visto ? " - tocando" : " - no veo 'Knock', intento igual"))
    antes := LeerContador()
    msgAntes := LeerTexto(ZONA_MENSAJES)
    SendEvent "{e down}"
    Sleep MANTENER_E
    SendEvent "{e up}"

    resultado := ""
    fin := A_TickCount + 3000
    while (A_TickCount < fin && resultado = "") {
        c := LeerContador()
        ; las puertas dan entre 1 y 15 caramelos, o te los roban: cualquier cambio cuenta
        if (c != "" && antes != "" && c[1] != antes[1]) {
            dif := c[1] - antes[1]
            resultado := dif > 0 ? "+" dif " caramelos" : "te robaron " (-dif) " caramelos"
            listoEn[n] := A_TickCount + RECARGA_PUERTA * 1000
            if (c[1] >= c[2])
                lleno := true
            break
        }
        msg := LeerTexto(ZONA_MENSAJES)
        if (msg = msgAntes) {
            if !Esperar(250)
                return false
        } else if RegExMatch(msg, "i)full|reached") {
            lleno := true
            resultado := "bolsa llena"
        } else if RegExMatch(msg, "i)(\d+)\s*candies\s*were\s*stolen", &m) {
            resultado := "te robaron " m[1] " caramelos"
            listoEn[n] := A_TickCount + RECARGA_PUERTA * 1000
        } else if RegExMatch(msg, "i)you\s*got\s*\+?\s*(\d+)", &m) {
            resultado := "+" m[1] " caramelos"
            listoEn[n] := A_TickCount + RECARGA_PUERTA * 1000
        } else if RegExMatch(msg, "i)back\s*in\s*(\d+)", &m) {
            ; puede haber varias líneas: la última es la más reciente
            pos := 1
            while (pos := RegExMatch(msg, "i)back\s*in\s*(\d+)", &m2, pos)) {
                m := m2
                pos += m2.Len
            }
            listoEn[n] := A_TickCount + Integer(m[1]) * 1000
            resultado := "ya visitada, vuelve en " m[1] " s"
        } else if !Esperar(250) {
            return false
        }
    }
    if InStr(resultado, "caramelos") {
        puertasTocadas++
        ActualizarStats()
    }
    if (resultado = "") {
        resultado := "sin respuesta"
        listoEn[n] := A_TickCount + 20000   ; reintenta en la próxima vuelta pasados 20 s
    }
    MostrarEstado("Puerta " n " - " resultado)
    return Esperar(ESPERA_TRAS_TOCAR)
}

; ================= HABILIDAD PERIÓDICA =================

; Si ya pasaron HABILIDAD_CADA_MIN minutos: slot 3, C, y de vuelta a la bolsa (slot 2).
HabilidadSiToca() {
    global
    if (HABILIDAD_CADA_MIN <= 0 || A_TickCount < proximaHabilidad)
        return true
    MostrarEstado("Usando la habilidad " StrUpper(TECLA_HABILIDAD) " (slot " SLOT_HABILIDAD ")")
    SendEvent "{" SLOT_HABILIDAD "}"
    if !Esperar(500)
        return false
    SendEvent "{" TECLA_HABILIDAD " down}"
    Sleep MANTENER_HABILIDAD
    SendEvent "{" TECLA_HABILIDAD " up}"
    if !Esperar(ESPERA_HABILIDAD)
        return false
    SendEvent "{" SLOT_BOLSA "}"
    proximaHabilidad := A_TickCount + HABILIDAD_CADA_MIN * 60000
    return Esperar(500)
}

; ================= CÁMARA =================

; x del centro de la "N" de la brújula si está cerca del centro de la pantalla; "" si no.
BuscarNorte() {
    global
    if !FileExist(IMG_NORTE)
        return ""
    try {
        if !ImageSearch(&fx, &fy, 760, 5, 1160, 60, "*70 *TransFF00FF " IMG_NORTE)
            return ""
    } catch
        return ""
    ; descarta "NE" / "NW": no debe haber otra letra blanca pegada a la N
    if PixelSearch(&px, &py, fx + NORTE_W + 1, fy + 4, fx + NORTE_W + 20, fy + NORTE_H - 4, 0xFFFFFF, 40)
        return ""
    if PixelSearch(&px, &py, fx - 20, fy + 4, fx - 1, fy + NORTE_H - 4, 0xFFFFFF, 40)
        return ""
    return fx + NORTE_W // 2
}

; Corrige la cámara hasta que la N quede en el centro de la brújula.
; Solo corrige desvíos pequeños: si no ve la N, no gira (empieza siempre mirando al Norte).
AlinearCamara() {
    global
    factor := FACTOR_GIRO
    ultimoPaso := 0
    loop 15 {
        if !SeguirJugando()
            return false
        cx := BuscarNorte()
        if (cx = "") {
            if (ultimoPaso = 0) {
                MostrarEstado("No veo la N de la brújula - no alineo la cámara")
                return true
            }
            GirarCamara(-ultimoPaso)   ; se pasó: deshace el último giro y prueba más fino
            factor /= 2
            ultimoPaso := 0
            continue
        }
        dif := cx - 960
        if (Abs(dif) <= 8)
            return true
        MostrarEstado("Alineando la cámara al Norte")
        paso := Round(dif * factor)
        if (Abs(paso) < 2)
            paso := dif > 0 ? 2 : -2
        if (ultimoPaso && (paso > 0) != (ultimoPaso > 0))
            factor /= 2
        ultimoPaso := Max(-200, Min(200, paso))
        GirarCamara(ultimoPaso)
    }
    return true
}

GirarCamara(dx) {
    SendEvent "{RButton down}"
    Sleep 40
    restante := dx
    while (restante != 0) {
        paso := Max(-20, Min(20, restante))
        DllCall("mouse_event", "UInt", 0x0001, "Int", paso, "Int", 0, "UInt", 0, "UPtr", 0)
        restante -= paso
        Sleep 5
    }
    Sleep 40
    SendEvent "{RButton up}"
    Sleep 150
}

ProbarCamara() {
    global
    ok := AlinearCamara()
    estado := "parado"
    MostrarEstado(ok ? "Prueba de cámara terminada" : "Prueba de cámara cancelada")
}

; ================= COMPRA =================

; La ruta termina pegado a la bruja, así que se compra desde ahí.
Comprar() {
    global
    compradasUltima := 0
    if (ARTICULO = "")
        return true
    precio := PRECIOS[ARTICULO]
    abierta := false
    loop 2 {
        SendEvent "{e down}"
        Sleep MANTENER_E
        SendEvent "{e up}"
        fin := A_TickCount + 3000
        while (A_TickCount < fin) {
            if TiendaAbierta() {
                abierta := true
                break 2
            }
            if !Esperar(250)
                return false
        }
    }
    if !abierta {
        if FileExist(ARCHIVO_COMPRA) {
            MostrarEstado("No pude abrir la tienda - uso la compra grabada (F2)")
            compradasUltima := -1   ; desconocido
            return Reproducir(ARCHIVO_COMPRA)
        }
        MostrarEstado("No pude abrir la tienda (¿estás junto a la bruja?)")
        return Esperar(2000)
    }

    compradas := 0, fallos := 0
    loop {
        caramelos := LeerCaramelosTienda()
        if (caramelos >= 0 && caramelos < precio)
            break
        pos := BuscarArticulo()
        if (pos = "") {
            MostrarEstado("No encuentro '" ARTICULO "' en la tienda")
            break
        }
        RatonRoblox("click", pos[1], pos[2])
        if !Esperar(700)
            return false
        ConfirmarCompra()
        if !Esperar(800)
            return false
        despues := LeerCaramelosTienda()
        if (caramelos >= 0 && despues >= 0 && despues < caramelos) {
            compradas++, fallos := 0
            MostrarEstado("Comprado x" compradas " - quedan " despues " caramelos")
        } else if (++fallos >= 2) {
            break
        }
        if !COMPRAR_TODO && compradas >= 1
            break
        if !SeguirJugando()
            return false
    }
    compradasUltima := compradas
    CerrarTienda()
    MostrarEstado("Compra terminada: " compradas " x " ARTICULO)
    return SeguirJugando()
}

; Busca la tarjeta del artículo; hace scroll por la lista si no está a la vista.
BuscarArticulo() {
    global
    nombre := StrLower(StrReplace(ARTICULO, " "))
    corto := CLAVES.Has(ARTICULO) ? CLAVES[ARTICULO] : nombre
    MouseMove 960, 600, 0
    loop 15 {
        Click "WheelUp"
        Sleep 30
    }
    Sleep 300
    loop 12 {
        r := LeerResultado(ZONA_ITEMS, 1)
        if IsObject(r) {
            ; primero el nombre completo; si no, la clave corta
            ; (nombres largos como "Plague Doctor Costume" ocupan dos líneas)
            for objetivo in [nombre, corto]
                for linea in r.Lines
                    if InStr(StrLower(StrReplace(linea.Text, " ")), objetivo)
                        return [Round(linea.x + linea.w / 2), Round(linea.y + linea.h / 2)]
        }
        MouseMove 960, 600, 0
        MouseMove 1, 0, 0, "R"
        Click "WheelDown"
        Sleep 400
        if !SeguirJugando()
            return ""
    }
    return ""
}

; Si aparece un botón de confirmar, lo pulsa.
ConfirmarCompra() {
    r := LeerResultado([0, 0, 1920, 1080], 1)
    if !IsObject(r)
        return
    ui.GetPos(&gx, &gy, &gw, &gh)
    for w in r.Words
        if !(w.x >= gx && w.x <= gx + gw && w.y >= gy && w.y <= gy + gh)
        && RegExMatch(Trim(w.Text), "i)^(buy|purchase|confirm|yes|redeem|comprar|confirmar)!?$") {
            RatonRoblox("click", Round(w.x + w.w / 2), Round(w.y + w.h / 2))
            return
        }
}

CerrarTienda() {
    SendEvent "{e down}"
    Sleep MANTENER_E
    SendEvent "{e up}"
    Sleep 600
    if TiendaAbierta() {     ; alejarse un poco también la cierra
        SendEvent "{s down}"
        Sleep 600
        SendEvent "{s up}"
        SendEvent "{w down}"
        Sleep 600
        SendEvent "{w up}"
    }
}

ProbarCompra() {
    global
    ok := Comprar()
    estado := "parado"
    MostrarEstado(ok ? "Prueba de compra terminada" : "Prueba de compra cancelada")
}

; ================= DESCONEXIÓN =================

Desconectado() {
    global
    r := LeerResultado([460, 300, 1000, 480], 1)
    if (!IsObject(r) || !RegExMatch(r.Text, "i)disconnect|lost connection|reconnect"))
        return false
    for w in r.Words
        if RegExMatch(w.Text, "i)^reconnect$") {
            RatonRoblox("click", Round(w.x + w.w / 2), Round(w.y + w.h / 2))
            break
        }
    estado := "parado"
    MostrarEstado("Desconectado de Roblox - macro parado")
    return true
}

; ================= DIAGNÓSTICO =================

F7:: Diagnostico()

Diagnostico() {
    c := LeerContador()
    msg := LeerTexto(ZONA_MENSAJES)
    knock := LeerTexto(ZONA_KNOCK, 1)
    norte := BuscarNorte()
    texto := "Contador: " (c = "" ? "NO LEÍDO (" LeerTexto(ZONA_CONTADOR) ")" : c[1] "/" c[2])
        . "`nMensajes: " StrReplace(msg, "`n", " | ")
        . "`n'Knock' visible: " (RegExMatch(knock, "i)kn[o0]ck") ? "sí" : "no")
        . "`nTienda abierta: " (TiendaAbierta() ? "sí (" LeerCaramelosTienda() " caramelos)" : "no")
        . "`nBrújula: " (norte = "" ? "no veo la N en el centro" : "N en x=" norte " (centro = 960)")
    try FileDelete A_ScriptDir "\diagnostico.txt"
    FileAppend texto "`n", A_ScriptDir "\diagnostico.txt"
    ToolTip texto, 20, 300, 2
    SetTimer () => ToolTip(, , , 2), -8000
}

; ================= VENTANA =================

COL_FONDO := "17171D", COL_PANEL := "24242E", COL_BOTON := "34343F"
COL_VERDE := "27AE60", COL_ROJO := "C0392B", COL_NARANJA := "FF8A1F"
COL_TEXTO := "EDEDF2", COL_GRIS := "9C9CA8"

CrearVentana() {
    global
    ui := Gui("+AlwaysOnTop -MaximizeBox", "GPO Halloween")
    ui.BackColor := COL_FONDO
    ui.MarginX := 16, ui.MarginY := 12
    ui.OnEvent("Close", (*) => Salir())

    ui.SetFont("s17 bold c" COL_NARANJA, "Segoe UI")
    ui.Add("Text", "xm w340", "GPO Halloween")
    ui.SetFont("s9 norm c" COL_GRIS)
    ui.Add("Text", "xm y+0 w340", "Macro de caramelos · Spooksville")

    ; --- contador de caramelos
    ui.SetFont("s24 bold c" COL_TEXTO)
    txtCaramelos := ui.Add("Text", "xm y+10 w340 Center", "— / —")
    ui.SetFont("s9 norm c" COL_GRIS)
    ui.Add("Text", "xm y+0 w340 Center", "caramelos")
    barra := ui.Add("Progress", "xm y+6 w340 h8 c" COL_NARANJA " Background" COL_PANEL, 0)

    ; --- compras
    ui.SetFont("s10 bold c" COL_TEXTO)
    ui.Add("Text", "xm y+16", "Compras")
    ui.SetFont("s10 norm c" COL_TEXTO)
    ddlModo := ui.Add("DropDownList", "xm y+6 w340",
        ["Sin compras (solo recolectar)", "1x · compra una vez y para", "inf · compra todo y sigue"])
    ddlModo.Value := MODO = "off" ? 1 : MODO = "1x" ? 2 : 3
    lista := []
    for a in ARTICULOS {
        lista.Push(a[1] "   —   " a[2] " caramelos")
        if (a[1] = ARTICULO_ELEGIDO)
            elegido := A_Index
    }
    ddlArticulo := ui.Add("DropDownList", "xm y+8 w340 R18", lista)
    ddlArticulo.Value := elegido
    txtPrecio := ui.Add("Text", "xm y+4 w340 c" COL_GRIS, "")

    ; --- opciones (casilla sin texto + etiqueta, para que el texto se vea en modo oscuro)
    ui.SetFont("s10 bold c" COL_TEXTO)
    ui.Add("Text", "xm y+12", "Opciones")
    ui.SetFont("s10 norm c" COL_TEXTO)
    chkHab := ui.Add("CheckBox", "xm y+8 w16 h20", "")
    chkHab.Value := HABILIDAD_ACTIVA
    lblHab := ui.Add("Text", "x+4 yp+1", "Usar habilidad C (slot 3) cada")
    edtMin := ui.Add("Edit", "x+6 yp-3 w42 h24 Number Center c" COL_TEXTO " Background" COL_PANEL, HABILIDAD_MIN)
    ui.Add("UpDown", "Range1-60", HABILIDAD_MIN)
    ui.Add("Text", "x+6 yp+3", "min")
    chkCam := ui.Add("CheckBox", "xm y+12 w16 h20", "")
    chkCam.Value := ALINEAR_CAMARA
    lblCam := ui.Add("Text", "x+4 yp+1", "Corregir la cámara al Norte en cada vuelta")
    lblHab.OnEvent("Click", (*) => (chkHab.Value := !chkHab.Value, CambiarOpciones()))
    lblCam.OnEvent("Click", (*) => (chkCam.Value := !chkCam.Value, CambiarOpciones()))

    ; --- botones
    btnIniciar := Boton("xm y+18 w340 h42", "s12", "▶   Iniciar   (F3)", COL_VERDE, IniciarParar)
    btnCompra := Boton("xm y+8 w166 h32", "s9", "Probar compra (F4)", COL_BOTON, () => Lanzar(ProbarCompra))
    btnRuta := Boton("x+8 yp w166 h32", "s9", "Grabar ruta (F1)", COL_BOTON, () => AlternarGrabacion(ARCHIVO_RUTA, "RUTA"))
    btnCamara := Boton("xm y+8 w166 h32", "s9", "Probar cámara (F6)", COL_BOTON, () => Lanzar(ProbarCamara))
    btnDiag := Boton("x+8 yp w166 h32", "s9", "Diagnóstico (F7)", COL_BOTON, () => (ActivarRoblox() && (Sleep(300), Diagnostico())))

    ; --- ruta, estadísticas y estado
    ui.SetFont("s9 norm c" COL_GRIS)
    txtRuta := ui.Add("Text", "xm y+12 w340", "")
    txtStats := ui.Add("Text", "xm y+2 w340", "")
    ui.SetFont("s10 norm c" COL_VERDE)
    txtEstado := ui.Add("Text", "xm y+8 w340 h40", "")

    for ctrl in [ddlModo, ddlArticulo]
        ctrl.OnEvent("Change", CambiarOpciones)
    for ctrl in [chkHab, chkCam]
        ctrl.OnEvent("Click", CambiarOpciones)
    edtMin.OnEvent("Change", CambiarOpciones)

    ; tema oscuro de Windows para la barra de título y las listas
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ui.Hwnd, "Int", 20, "Int*", 1, "Int", 4)
    for ctrl in [ddlModo, ddlArticulo, edtMin]
        try DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)

    ActualizarRuta()
    ActualizarStats()
    ActualizarOpcionesVisibles()
    ; a la derecha de la pantalla, fuera de las zonas que el macro lee
    ui.Show("x1525 y40 AutoSize NoActivate")
}

; Botón plano de color (un Text con fondo, como en el video).
Boton(pos, tam, texto, color, accion) {
    global
    ui.SetFont(tam " bold cFFFFFF")
    b := ui.Add("Text", pos " Center 0x200 Background" color, texto)   ; 0x200 = centrado vertical
    b.OnEvent("Click", (*) => accion())
    return b
}

PintarBoton(b, texto, color) {
    if (b.Text != texto)
        b.Text := texto
    b.Opt("+Background" color)
    b.Redraw()
}

ActualizarBotones() {
    global
    if !IsSet(btnIniciar)
        return
    if (estado = "jugando")
        PintarBoton(btnIniciar, "■   Parar   (F3)", COL_ROJO)
    else
        PintarBoton(btnIniciar, "▶   Iniciar   (F3)", COL_VERDE)
    if (estado = "grabando" && archivoGrabando = ARCHIVO_RUTA)
        PintarBoton(btnRuta, "●  Terminar ruta (F1)", COL_ROJO)
    else
        PintarBoton(btnRuta, "Grabar ruta (F1)", COL_BOTON)
}

CambiarOpciones(*) {
    global
    MODO := ["off", "1x", "inf"][ddlModo.Value]
    ARTICULO_ELEGIDO := ARTICULOS[ddlArticulo.Value][1]
    HABILIDAD_ACTIVA := chkHab.Value
    HABILIDAD_MIN := Max(1, Integer(edtMin.Value = "" ? 5 : edtMin.Value))
    ALINEAR_CAMARA := chkCam.Value
    AplicarOpciones()
    ActualizarOpcionesVisibles()
    try {
        IniWrite MODO, ARCHIVO_CONFIG, "opciones", "modo"
        IniWrite ARTICULO_ELEGIDO, ARCHIVO_CONFIG, "opciones", "articulo"
        IniWrite HABILIDAD_MIN, ARCHIVO_CONFIG, "opciones", "habilidad_min"
        IniWrite HABILIDAD_ACTIVA, ARCHIVO_CONFIG, "opciones", "habilidad"
        IniWrite ALINEAR_CAMARA, ARCHIVO_CONFIG, "opciones", "camara"
    }
}

; Traduce lo elegido en la ventana a lo que usa el macro.
AplicarOpciones() {
    global
    ARTICULO := (MODO = "off") ? "" : ARTICULO_ELEGIDO
    PARAR_TRAS_COMPRAR := (MODO = "1x")
    COMPRAR_TODO := (MODO = "inf")
    HABILIDAD_CADA_MIN := HABILIDAD_ACTIVA ? HABILIDAD_MIN : 0
}

ActualizarOpcionesVisibles() {
    global
    ddlArticulo.Enabled := (MODO != "off")
    precio := PRECIOS[ARTICULO_ELEGIDO]
    txtPrecio.Value := (MODO = "off") ? "Al llenar la bolsa, el macro se detiene."
        : (MODO = "1x") ? "Al llenar la bolsa compra 1 " ARTICULO_ELEGIDO " (" precio ") y se detiene."
        : "Al llenar la bolsa compra todos los " ARTICULO_ELEGIDO " que pueda (" precio " c/u)."
}

ActualizarRuta() {
    global
    if !FileExist(ARCHIVO_RUTA) {
        txtRuta.Value := "Ruta: sin grabar"
        return
    }
    n := 0
    loop parse FileRead(ARCHIVO_RUTA), "`n", "`r"
        if InStr(A_LoopField, "|kd|e")
            n++
    txtRuta.Value := "Ruta: grabada (" n " puertas)"
}

ActualizarStats() {
    global
    if IsSet(txtStats)
        txtStats.Value := "Vueltas: " vueltas "   ·   Puertas tocadas: " puertasTocadas "   ·   Compras: " compras
}

MostrarCaramelos(a, b) {
    global
    if !IsSet(txtCaramelos)
        return
    txt := a " / " b
    if (txtCaramelos.Value != txt) {
        txtCaramelos.Value := txt
        barra.Value := Round(a * 100 / b)
    }
}

; Con el macro parado, mantiene el contador al día mientras juegas.
TimerContador() {
    global
    if (estado = "parado" && WinActive(ROBLOX))
        LeerContador()
}

Salir() {
    SoltarTodo()
    ExitApp
}

; ================= UTILIDADES =================

; Roblox no registra clics si el ratón no se mueve antes: se mueve 1 px.
RatonRoblox(tipo, x, y) {
    MouseMove x, y, 0
    Sleep 30
    MouseMove 1, 0, 0, "R"
    Sleep 30
    switch tipo {
        case "click": Click
        case "wheelup": Click "WheelUp"
        case "wheeldown": Click "WheelDown"
    }
    Sleep 50
}

Esperar(ms) {
    fin := A_TickCount + ms
    while (A_TickCount < fin) {
        if !SeguirJugando()
            return false
        Sleep 10
    }
    return SeguirJugando()
}

SeguirJugando() {
    global
    if (estado != "jugando")
        return false
    if !WinActive(ROBLOX) {
        estado := "parado"
        MostrarEstado("Parado: Roblox dejó de estar en primer plano")
        return false
    }
    return true
}

SoltarTodo() {
    global
    for k in TECLAS
        SendEvent "{" k " up}"
    SendEvent "{RButton up}"
}

MostrarEstado(texto) {
    global
    txtEstado.Value := texto
    ActualizarBotones()
}

F8:: Salir()
