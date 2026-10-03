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
; ============================================================

; ---------------- CONFIGURACIÓN ----------------
; Artículo a comprar cuando la bolsa se llena ("" = no comprar, solo recolectar).
; Escríbelo igual que en la tienda: "Rare Fruit Chest", "Blood Scythe", "Fruit Bag"...
ARTICULO := "Rare Fruit Chest"
; true  = compra y se detiene ("1x")   |  false = compra y sigue recolectando ("inf")
PARAR_TRAS_COMPRAR := false
; true = gasta todos los caramelos en el artículo | false = compra solo 1 cada vez
COMPRAR_TODO := true
; Cuánto tiempo (ms) se mantiene E para tocar una puerta o hablar con la bruja.
MANTENER_E := 400
; Espera (ms) tras tocar una puerta, para que se acabe el aturdimiento.
ESPERA_TRAS_TOCAR := 1500
; Recarga de una puerta (s) si el juego no dice "Come back in Xs".
RECARGA_PUERTA := 180
; Sensibilidad del giro de cámara al alinear al Norte (bájalo si se pasa de largo).
FACTOR_GIRO := 0.5
; Alinear la cámara al Norte antes de cada vuelta.
ALINEAR_CAMARA := true
; ------------------------------------------------

PRECIOS := Map(
    "SP Reset Essence", 10, "Devil Fruit Remover", 25, "Race Reroll x5", 25,
    "Custom Spirit Color", 50, "Lantern", 50, "Trading Sign", 100,
    "Joker Costume", 100, "Ghost Face Costume", 100, "Plague Doctor Costume", 100,
    "Legendary Fruit Chest Blueprint", 100, "Mummy Wrappings", 100, "Devil Fruit Journal", 125,
    "Wizard Costume", 175, "Frankenstein Costume", 175, "Shark Costume", 175,
    "Fruit Bag", 250, "Rare Fruit Chest", 250, "Blood Scythe", 500)

; Nombres que en la tienda ocupan dos líneas o que el OCR puede leer mal.
CLAVES := Map("Plague Doctor Costume", "plaguedoctor", "Legendary Fruit Chest Blueprint", "legendaryfruitchest",
    "Race Reroll x5", "racereroll")

ROBLOX := "ahk_exe RobloxPlayerBeta.exe"
TECLAS := ["w", "a", "s", "d", "Space", "e", "q", "LShift", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
ARCHIVO_RUTA := A_ScriptDir "\ruta.txt"
ARCHIVO_COMPRA := A_ScriptDir "\compra.txt"

; Zonas de la pantalla (1920x1080, pantalla completa)
ZONA_CONTADOR := [820, 850, 280, 55]      ; "219/500 Candies"
ZONA_MENSAJES := [450, 155, 1020, 90]     ; "You got +5 Candies!" / "Come back in 124s" / "basket is full"
ZONA_KNOCK    := [450, 250, 1250, 500]    ; "E Knock"
ZONA_TITULO_TIENDA := [450, 215, 500, 70] ; "Halloween Shop"
ZONA_CARAMELOS_TIENDA := [1300, 250, 120, 45] ; "500" arriba a la derecha de la tienda
ZONA_ITEMS    := [500, 290, 920, 580]     ; tarjetas de la tienda
ZONA_BRUJULA  := [500, 5, 920, 50]        ; N / NE / E ...

CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
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

MostrarEstado("Listo - F1 grabar ruta, F3 iniciar, F7 diagnóstico")

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
    texto := StrReplace(LeerTexto(ZONA_CONTADOR), " ")
    if RegExMatch(texto, "(\d+)/(\d+)", &m) {
        a := Integer(m[1]), b := Integer(m[2])
        if (b > 0 && a <= b)
            return [a, b]
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
    MostrarEstado("Guardado: " Round(t / 1000, 1) " s, " puertas " pulsaciones de E")
}

#HotIf estado = "grabando"
~LButton:: GrabarRaton("click")
~WheelUp:: GrabarRaton("wheelup")
~WheelDown:: GrabarRaton("wheeldown")
#HotIf

GrabarRaton(tipo) {
    global
    MouseGetPos &x, &y
    eventos.Push((A_TickCount - inicioGrabacion) "|" tipo "|" x "," y)
}

; ================= CONTROLES =================

F3:: {
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
    if (ARTICULO != "" && !PRECIOS.Has(ARTICULO)) {
        MsgBox "No conozco el artículo '" ARTICULO "'. Revisa cómo está escrito en la CONFIGURACIÓN."
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
    vueltas := 0, compras := 0
    lleno := false
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
            lleno := false
            if PARAR_TRAS_COMPRAR {
                estado := "parado"
                MostrarEstado("Terminado: compra hecha (" vueltas " vueltas)")
                return
            }
        } else if lleno {
            estado := "parado"
            MostrarEstado("Bolsa llena y no hay ARTICULO configurado - parado")
            return
        }

        ; Si todas las puertas están en recarga, espera en la bruja.
        espera := EsperaMinima()
        if (espera > 5000) {
            MostrarEstado("Todas las puertas en recarga - espero " Ceil(espera / 1000) " s")
            if !Esperar(espera)
                break
        }

        if (ALINEAR_CAMARA && !AlinearCamara())
            break
        MostrarEstado("Vuelta " (vueltas + 1) " - recorriendo puertas")
        if !Reproducir(ARCHIVO_RUTA, true)
            break
        vueltas++
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
        if (c != "" && antes != "" && c[1] > antes[1]) {
            resultado := "+" (c[1] - antes[1]) " caramelos"
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
    if (resultado = "") {
        resultado := "sin respuesta"
        listoEn[n] := A_TickCount + 20000   ; reintenta en la próxima vuelta pasados 20 s
    }
    MostrarEstado("Puerta " n " - " resultado)
    return Esperar(ESPERA_TRAS_TOCAR)
}

; ================= CÁMARA =================

; Gira la cámara (clic derecho + movimiento del ratón) hasta que la brújula marca N en el centro.
AlinearCamara() {
    global
    MostrarEstado("Alineando la cámara al Norte")
    factor := FACTOR_GIRO
    ultimoSigno := 0
    loop 25 {
        if !SeguirJugando()
            return false
        r := LeerResultado(ZONA_BRUJULA, 2)
        cx := ""
        if IsObject(r)
            for w in r.Words
                if (Trim(w.Text) = "N") {
                    cx := w.x + w.w / 2
                    break
                }
        if (cx = "") {
            GirarCamara(250)   ; el Norte no está a la vista: gira un buen trozo
            continue
        }
        dif := cx - 960
        if (Abs(dif) <= 15)
            return true
        signo := dif > 0 ? 1 : -1
        if (ultimoSigno && signo != ultimoSigno)
            factor /= 2        ; se pasó de largo: gira más fino
        ultimoSigno := signo
        paso := Round(dif * factor)
        if (Abs(paso) < 2)
            paso := 2 * signo
        GirarCamara(Max(-400, Min(400, paso)))
    }
    MostrarEstado("No pude alinear la cámara (sigo igual)")
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
    for w in r.Words
        if RegExMatch(Trim(w.Text), "i)^(buy|purchase|confirm|yes|redeem|comprar|confirmar)!?$") {
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

F7:: {
    c := LeerContador()
    msg := LeerTexto(ZONA_MENSAJES)
    knock := LeerTexto(ZONA_KNOCK, 1)
    r := LeerResultado(ZONA_BRUJULA, 2)
    brujula := ""
    if IsObject(r)
        for w in r.Words
            brujula .= w.Text "@" (w.x + w.w // 2) " "
    texto := "Contador: " (c = "" ? "NO LEÍDO (" LeerTexto(ZONA_CONTADOR) ")" : c[1] "/" c[2])
        . "`nMensajes: " StrReplace(msg, "`n", " | ")
        . "`n'Knock' visible: " (RegExMatch(knock, "i)kn[o0]ck") ? "sí" : "no")
        . "`nTienda abierta: " (TiendaAbierta() ? "sí (" LeerCaramelosTienda() " caramelos)" : "no")
        . "`nBrújula (letra@x, centro=960): " brujula
    try FileDelete A_ScriptDir "\diagnostico.txt"
    FileAppend texto "`n", A_ScriptDir "\diagnostico.txt"
    ToolTip texto, 20, 300, 2
    SetTimer () => ToolTip(, , , 2), -8000
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
    ToolTip "GPO Halloween: " texto, 1480, 940
}

F8:: {
    SoltarTodo()
    ExitApp
}
