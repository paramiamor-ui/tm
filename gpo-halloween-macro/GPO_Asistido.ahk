#Requires AutoHotkey v2.0
#SingleInstance Force
#Include <OCR>   ; Lib\OCR.ahk (Descolada, MIT) - lee texto de la pantalla
; ============================================================
;  GPO Halloween - MODO ASISTIDO
;  Tú caminas por las calles; el macro toca cada puerta en cuanto aparece
;  "E Knock", mantiene la bolsa en la mano, usa la habilidad C cada X minutos
;  y compra en la tienda de la bruja cuando pulsas F4.
;
;  F3 = activar / pausar
;  F4 = comprar ahora (ponte junto a la bruja)
;  F7 = diagnóstico (qué está viendo)
;  F8 = salir
; ============================================================

; ---------------- AJUSTES ----------------
MANTENER_E := 400            ; ms que se mantiene E para tocar o abrir la tienda
SLOT_BOLSA := "2"
SLOT_HABILIDAD := "3"
TECLA_HABILIDAD := "c"
MANTENER_HABILIDAD := 300    ; ms que se mantiene C
ESPERA_HABILIDAD := 2500     ; ms de animación antes de volver a la bolsa
; ------------------------------------------

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
CONFIG := A_ScriptDir "\config.ini"
IMG_KNOCK := A_ScriptDir "\Lib\knock.png"

; Zonas de la pantalla (1920x1080, pantalla completa)
ZONA_CONTADOR := [820, 850, 280, 55]          ; "219/500 Candies"
ZONA_MENSAJES := [450, 155, 1020, 90]         ; "You got +5 Candies!" / "Come back in 124s"
ZONA_KNOCK := [450, 250, 1000, 500]           ; "E Knock"
ZONA_TITULO_TIENDA := [450, 215, 500, 70]     ; "Halloween Shop"
ZONA_CARAMELOS_TIENDA := [1300, 250, 120, 45] ; caramelos arriba a la derecha de la tienda
ZONA_ITEMS := [500, 290, 920, 580]            ; tarjetas de la tienda

; Colores de la ventana
C_NOCHE := "15121F", C_MURO := "221E33", C_TEJA := "2F2A46"
C_CALABAZA := "FF7A1A", C_CALDERO := "7CDB5A", C_HUESO := "F2E9DC"
C_NIEBLA := "8E88A8", C_SANGRE := "E0475B"

CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
CoordMode "ToolTip", "Screen"
SetKeyDelay 10, 30   ; Roblox ignora pulsaciones demasiado rápidas

; Opciones (compartidas con config.ini del macro completo)
articulo := IniRead(CONFIG, "opciones", "articulo", "Rare Fruit Chest")
if !PRECIOS.Has(articulo)
    articulo := "Rare Fruit Chest"
comprarTodo := Integer(IniRead(CONFIG, "asistido", "comprar_todo", 1))
habActiva := Integer(IniRead(CONFIG, "opciones", "habilidad", 1))
habMin := Integer(IniRead(CONFIG, "opciones", "habilidad_min", 5))

activo := false, ocupado := false
armado := true, tUltimoToque := 0, escaneos := 0
proximaHabilidad := 0, lleno := false
puertasTocadas := 0, caramelosGanados := 0

CrearVentana()
OnMessage(0x201, ArrastrarVentana)
Estado("Pulsa F3 (o Activar) y camina por las calles.")
SetTimer Vigilar, 120

F3:: Alternar()
F4:: ComprarAhora()
F7:: Diagnostico()
F8:: Salir()

; ================= BUCLE =================

; Cada 120 ms: ¿hay una puerta a la vista? Si sí, la toca.
Vigilar() {
    global activo, ocupado, armado, tUltimoToque, escaneos, habActiva, proximaHabilidad, lleno
    local visto
    if (!activo || ocupado || !WinActive(ROBLOX))
        return
    ocupado := true
    try {
        if (habActiva && A_TickCount >= proximaHabilidad)
            UsarHabilidad()
        escaneos++
        if (Mod(escaneos, 20) = 0)
            LeerContador()
        if lleno
            return
        ; por imagen siempre; cada 4 vueltas también leyendo el texto "Knock"
        visto := KnockPorImagen()
        if (!visto && Mod(escaneos, 4) = 0)
            visto := RegExMatch(LeerTexto(ZONA_KNOCK, 1), "i)kn[o0]ck") > 0
        if !visto {
            armado := true
        } else if (armado || A_TickCount - tUltimoToque > 2500) {
            Tocar()
            armado := false
            tUltimoToque := A_TickCount
        }
    } finally {
        ocupado := false
    }
}

Tocar() {
    global puertasTocadas, caramelosGanados, lleno
    local antes, c, dif, fin, m, msg, msgAntes, resultado
    if !EquiparSlot(SLOT_BOLSA)
        return
    antes := LeerContador()
    msgAntes := LeerTexto(ZONA_MENSAJES)
    Estado("Tocando puerta...")
    SendEvent "{e down}"
    Sleep MANTENER_E
    SendEvent "{e up}"

    resultado := ""
    fin := A_TickCount + 2500
    while (A_TickCount < fin && resultado = "") {
        c := LeerContador()
        if (IsObject(c) && IsObject(antes) && c[1] != antes[1]) {
            dif := c[1] - antes[1]
            resultado := dif > 0 ? "+" dif " caramelos" : "te robaron " (-dif)
            caramelosGanados += dif
            puertasTocadas++
            break
        }
        msg := LeerTexto(ZONA_MENSAJES)
        if (msg != msgAntes) {
            if RegExMatch(msg, "i)full|reached")
                resultado := "bolsa llena", lleno := true
            else if RegExMatch(msg, "i)back\s*in\s*(\d+)", &m)
                resultado := "ya visitada (vuelve en " m[1] " s)"
            else if RegExMatch(msg, "i)you\s*got\s*\+?\s*(\d+)", &m)
                resultado := "+" m[1] " caramelos", puertasTocadas++
            else if RegExMatch(msg, "i)(\d+)\s*candies\s*were\s*stolen", &m)
                resultado := "te robaron " m[1], puertasTocadas++
        }
        if (resultado = "")
            Sleep 150
    }
    ActualizarStats()
    Estado("Puerta: " (resultado = "" ? "sin respuesta" : resultado))
}

UsarHabilidad() {
    global proximaHabilidad, habMin
    proximaHabilidad := A_TickCount + habMin * 60000
    Estado("Usando la habilidad " StrUpper(TECLA_HABILIDAD) "...")
    EquiparSlot(SLOT_HABILIDAD)
    Sleep 300
    SendEvent "{" TECLA_HABILIDAD " down}"
    Sleep MANTENER_HABILIDAD
    SendEvent "{" TECLA_HABILIDAD " up}"
    Sleep ESPERA_HABILIDAD
    ; de vuelta a la bolsa: con la fruta en la mano, E sería un ataque
    EquiparSlot(SLOT_BOLSA)
    Estado("Habilidad usada. Sigue caminando.")
}

Alternar() {
    global activo, proximaHabilidad, armado
    activo := !activo
    if activo {
        if !WinExist(ROBLOX) {
            activo := false
            MsgBox "Abre Roblox primero."
            return
        }
        WinActivate ROBLOX
        proximaHabilidad := A_TickCount + 2000   ; la primera habilidad, al empezar
        armado := true
        LeerContador()
        Estado("Activo: camina por las calles, yo toco las puertas.")
    } else {
        Estado("En pausa. F3 para seguir.")
    }
    PintarActivo()
}

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
    global lleno
    local a, b, m, texto
    texto := LeerTexto(ZONA_CONTADOR)
    texto := RegExReplace(texto, "i)c\s*a\s*n.*$")        ; quita "Candies"
    texto := RegExReplace(texto, "[oO]", "0")
    texto := RegExReplace(texto, "[lI|]", "1")
    texto := RegExReplace(texto, "[^\d/]")                  ; "5.00" -> "500"
    if RegExMatch(texto, "(\d+)/(\d+)", &m) {
        a := Integer(m[1]), b := Integer(m[2])
        if (b > 0 && a <= b) {
            MostrarCaramelos(a, b)
            if (a >= b && !lleno) {
                lleno := true
                SoundBeep 880, 150
                SoundBeep 1175, 200
                Estado("¡Bolsa llena! Ve con la bruja y pulsa F4 para comprar.")
            } else if (a < b) {
                lleno := false
            }
            return [a, b]
        }
    }
    return ""
}

LeerCaramelosTienda() {
    local texto := RegExReplace(LeerTexto(ZONA_CARAMELOS_TIENDA, 3), "[^\d]")
    return (texto = "") ? -1 : Integer(texto)
}

TiendaAbierta() => RegExMatch(LeerTexto(ZONA_TITULO_TIENDA), "i)hall[o0]ween|sh[o0]p")

; Aviso "E Knock" por imagen (Lib\knock.png, recortado de capturas reales).
KnockPorImagen() {
    local c, fx, fy, pt
    try {
        if !ImageSearch(&fx, &fy, 450, 250, 1450, 750, "*70 *TransFF00FF " IMG_KNOCK)
            return false
    } catch
        return false
    ; el interior del recuadro de la E tiene que ser oscuro (descarta zonas blancas)
    for pt in [[6, 8], [22, 8], [6, 24], [22, 24], [14, 26], [22, 16]] {
        c := PixelGetColor(fx + pt[1], fy + pt[2])
        if (Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) >= 150)
            return false
    }
    return true
}

; El slot equipado tiene el borde blanco (los demás, gris).
SlotEquipado(n) {
    local px, py, x0 := 618 + (n - 1) * 78
    return PixelSearch(&px, &py, x0 - 3, 1012, x0 + 3, 1062, 0xFFFFFF, 40)
        && PixelSearch(&px, &py, x0 + 55, 1012, x0 + 61, 1062, 0xFFFFFF, 40)
}

; Equipa el slot solo si no lo está (pulsar el número de un slot ya equipado lo guarda).
EquiparSlot(n) {
    loop 4 {
        if SlotEquipado(n)
            return true
        SendEvent "{" n "}"
        Sleep 500
    }
    return false
}

; ================= COMPRA =================

ComprarAhora() {
    global ocupado, lleno
    local ok
    if !WinExist(ROBLOX) {
        MsgBox "Abre Roblox primero."
        return
    }
    WinActivate ROBLOX
    WinWaitActive ROBLOX, , 2
    ; si está tocando una puerta o usando la habilidad, lo reintenta en un momento
    ; (esperar aquí bloquearía: esa tarea no continúa hasta que esta termine)
    if ocupado {
        SetTimer ComprarAhora, -300
        return
    }
    ocupado := true, ok := false
    try {
        ok := Comprar()
    } finally {
        ocupado := false
    }
    if ok
        lleno := false
}

Comprar() {
    global articulo, comprarTodo
    local abierta, caramelos, compradas, despues, fallos, fin, pos, precio
    precio := PRECIOS[articulo]
    EquiparSlot(SLOT_BOLSA)
    Estado("Abriendo la tienda...")
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
            Sleep 250
        }
    }
    if !abierta {
        Estado("No se abrió la tienda: ponte pegado a la bruja y vuelve a pulsar F4.")
        return false
    }
    compradas := 0, fallos := 0
    loop {
        caramelos := LeerCaramelosTienda()
        if (caramelos >= 0 && caramelos < precio)
            break
        pos := BuscarArticulo()
        if !IsObject(pos) {
            Estado("No encuentro '" articulo "' en la tienda.")
            break
        }
        RatonRoblox(pos[1], pos[2])
        Sleep 700
        ConfirmarCompra()
        Sleep 800
        despues := LeerCaramelosTienda()
        if (caramelos >= 0 && despues >= 0 && despues < caramelos) {
            compradas++, fallos := 0
            Estado("Comprado x" compradas " - quedan " despues " caramelos")
        } else if (++fallos >= 2) {
            break
        }
        if (!comprarTodo && compradas >= 1)
            break
    }
    CerrarTienda()
    Estado("Compra terminada: " compradas " x " articulo ". F3 para seguir tocando puertas.")
    LeerContador()
    return compradas > 0
}

; Busca la tarjeta del artículo; hace scroll por la lista si no está a la vista.
BuscarArticulo() {
    global articulo
    local corto, linea, nombre, objetivo, r
    nombre := StrLower(StrReplace(articulo, " "))
    corto := CLAVES.Has(articulo) ? CLAVES[articulo] : nombre
    MouseMove 960, 600, 0
    loop 15 {
        Click "WheelUp"
        Sleep 30
    }
    Sleep 300
    loop 12 {
        r := LeerResultado(ZONA_ITEMS, 1)
        if IsObject(r)
            for objetivo in [nombre, corto]
                for linea in r.Lines
                    if InStr(StrLower(StrReplace(linea.Text, " ")), objetivo)
                        return [Round(linea.x + linea.w / 2), Round(linea.y + linea.h / 2)]
        MouseMove 960, 600, 0
        MouseMove 1, 0, 0, "R"
        Click "WheelDown"
        Sleep 400
    }
    return ""
}

; Si aparece un botón de confirmar, lo pulsa (ignora la ventana del macro).
ConfirmarCompra() {
    global ui
    local gh, gw, gx, gy, r, w
    r := LeerResultado([0, 0, 1920, 1080], 1)
    if !IsObject(r)
        return
    ui.GetPos(&gx, &gy, &gw, &gh)
    for w in r.Words
        if !(w.x >= gx && w.x <= gx + gw && w.y >= gy && w.y <= gy + gh)
        && RegExMatch(Trim(w.Text), "i)^(buy|purchase|confirm|yes|redeem|comprar|confirmar)!?$") {
            RatonRoblox(Round(w.x + w.w / 2), Round(w.y + w.h / 2))
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
    }
}

; Roblox no registra clics si el ratón no se mueve antes: se mueve 1 px.
RatonRoblox(x, y) {
    MouseMove x, y, 0
    Sleep 30
    MouseMove 1, 0, 0, "R"
    Sleep 30
    Click
    Sleep 50
}

; ================= DIAGNÓSTICO =================

Diagnostico() {
    local c, porImagen, porTexto, slot, texto
    c := LeerContador()
    porImagen := KnockPorImagen()
    porTexto := RegExMatch(LeerTexto(ZONA_KNOCK, 1), "i)kn[o0]ck") > 0
    slot := ""
    loop 9
        if SlotEquipado(A_Index)
            slot .= A_Index " "
    texto := "Contador: " (IsObject(c) ? c[1] "/" c[2] : "NO LEÍDO")
        . "`n'E Knock' por imagen: " (porImagen ? "sí" : "no") "   ·   por texto: " (porTexto ? "sí" : "no")
        . "`nSlot equipado: " (slot = "" ? "ninguno detectado" : slot)
        . "`nTienda abierta: " (TiendaAbierta() ? "sí" : "no")
    try FileDelete A_ScriptDir "\diagnostico.txt"
    try FileAppend texto "`n", A_ScriptDir "\diagnostico.txt", "UTF-8"
    ToolTip texto, 20, 300, 2
    SetTimer () => ToolTip(, , , 2), -8000
}

; ================= VENTANA =================

CrearVentana() {
    global
    local i, lista, sel
    ui := Gui("-Caption +AlwaysOnTop", "GPO Halloween (asistido)")
    ui.BackColor := C_NOCHE
    ui.MarginX := 14, ui.MarginY := 12

    ui.SetFont("s13 c" C_CALABAZA, "Bahnschrift SemiBold")
    ui.Add("Text", "xm ym w200", "GPO HALLOWEEN")
    ui.SetFont("s9 c" C_NIEBLA, "Segoe UI")
    ui.Add("Text", "x+0 yp+4 w44 Right", "asistido")
    BotonPlano("x+8 yp-4 w24 h24", "s10", "✕", C_TEJA, C_HUESO, Salir)

    ui.SetFont("s30 c" C_HUESO, "Bahnschrift")
    txtCaramelos := ui.Add("Text", "xm y+6 w290", "— / —")
    barra := ui.Add("Progress", "xm y+4 w290 h6 c" C_CALABAZA " Background" C_TEJA, 0)

    btnActivar := BotonPlano("xm y+14 w290 h44", "s12 bold", "", C_CALDERO, C_NOCHE, Alternar)

    ui.SetFont("s8 bold c" C_NIEBLA, "Segoe UI")
    ui.Add("Text", "xm y+14 w290", "QUÉ COMPRAR (F4 JUNTO A LA BRUJA)")
    ui.SetFont("s10 norm c" C_HUESO, "Segoe UI")
    lista := []
    for i, a in ARTICULOS {
        lista.Push(a[1] "  —  " a[2])
        if (a[1] = articulo)
            sel := i
    }
    ddlArticulo := ui.Add("DropDownList", "xm y+6 w290 R18", lista)
    ddlArticulo.Value := sel
    ddlModo := ui.Add("DropDownList", "xm y+6 w290", ["Comprar todos los que alcancen", "Comprar solo 1"])
    ddlModo.Value := comprarTodo ? 1 : 2
    BotonPlano("xm y+8 w290 h30", "s9", "Comprar ahora  ·  F4", C_TEJA, C_HUESO, ComprarAhora)

    ui.SetFont("s10 norm c" C_HUESO, "Segoe UI")
    ui.Add("Text", "xm y+14 w150 h26 0x200", "Habilidad C cada")
    BotonPlano("x+4 yp w24 h26", "s11 bold", "−", C_TEJA, C_HUESO, () => CambiarMinutos(-1))
    ui.SetFont("s10 c" C_HUESO, "Bahnschrift")
    txtMin := ui.Add("Text", "x+2 yp w46 h26 Center 0x200 Background" C_MURO, "")
    BotonPlano("x+2 yp w24 h26", "s11 bold", "+", C_TEJA, C_HUESO, () => CambiarMinutos(1))
    pillHab := BotonPlano("x+6 yp w30 h26", "s8 bold", "", C_TEJA, C_HUESO, AlternarHabilidad)

    ui.SetFont("s9 c" C_NIEBLA, "Segoe UI")
    txtStats := ui.Add("Text", "xm y+14 w290", "")
    ui.SetFont("s9 c" C_CALDERO, "Segoe UI")
    txtEstado := ui.Add("Text", "xm y+6 w290 h34", "")
    ui.SetFont("s8 c" C_NIEBLA, "Segoe UI")
    ui.Add("Text", "xm y+2 w290", "F3 activar · F4 comprar · F7 diagnóstico · F8 salir")

    ddlArticulo.OnEvent("Change", CambiarCompra)
    ddlModo.OnEvent("Change", CambiarCompra)
    for ctrl in [ddlArticulo, ddlModo]
        try DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", ui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

    PintarActivo()
    PintarHabilidad()
    ActualizarStats()
    ui.Show("x1600 y30 AutoSize NoActivate")
}

; Botón plano: un Text con fondo de color que responde al clic.
BotonPlano(pos, fuente, texto, fondo, colorTexto, accion) {
    global ui
    local b
    ui.SetFont(fuente " c" colorTexto, "Segoe UI")
    b := ui.Add("Text", pos " Center 0x200 Background" fondo, texto)
    b.OnEvent("Click", (*) => accion())
    return b
}

Pintar(ctrl, fondo, colorTexto, texto) {
    if (ctrl.Text != texto)
        ctrl.Text := texto
    ctrl.Opt("Background" fondo)
    ctrl.SetFont("c" colorTexto)
    ctrl.Redraw()
}

PintarActivo() {
    global activo, btnActivar
    if activo
        Pintar(btnActivar, C_SANGRE, C_HUESO, "❚❚   Pausar   ·   F3")
    else
        Pintar(btnActivar, C_CALDERO, C_NOCHE, "▶   Activar   ·   F3")
}

PintarHabilidad() {
    global habActiva, habMin, txtMin, pillHab
    txtMin.Value := habMin " min"
    Pintar(pillHab, habActiva ? C_CALDERO : C_TEJA, habActiva ? C_NOCHE : C_NIEBLA, habActiva ? "ON" : "OFF")
}

CambiarCompra(*) {
    global articulo, comprarTodo, ddlArticulo, ddlModo
    articulo := ARTICULOS[ddlArticulo.Value][1]
    comprarTodo := (ddlModo.Value = 1)
    try {
        IniWrite articulo, CONFIG, "opciones", "articulo"
        IniWrite comprarTodo ? 1 : 0, CONFIG, "asistido", "comprar_todo"
    }
}

CambiarMinutos(d) {
    global habMin
    habMin := Max(1, Min(60, habMin + d))
    try IniWrite habMin, CONFIG, "opciones", "habilidad_min"
    PintarHabilidad()
}

AlternarHabilidad() {
    global habActiva
    habActiva := !habActiva
    try IniWrite habActiva ? 1 : 0, CONFIG, "opciones", "habilidad"
    PintarHabilidad()
}

ActualizarStats() {
    global txtStats, puertasTocadas, caramelosGanados
    if IsSet(txtStats)
        txtStats.Value := "Puertas tocadas: " puertasTocadas "    ·    Caramelos ganados: " caramelosGanados
}

MostrarCaramelos(a, b) {
    global txtCaramelos, barra
    if !IsSet(txtCaramelos)
        return
    txtCaramelos.Value := a " / " b
    barra.Value := Round(a * 100 / b)
}

Estado(texto) {
    global txtEstado
    if IsSet(txtEstado)
        txtEstado.Value := texto
}

ArrastrarVentana(wParam, lParam, msg, hwnd) {
    global ui
    if (hwnd = ui.Hwnd) {
        PostMessage 0xA1, 2, 0, , "ahk_id " hwnd   ; arrastrar como si fuera la barra de título
        return 0
    }
}

Salir(*) {
    for k in ["w", "a", "s", "d", "e", "c", "Space", "LShift"]
        SendEvent "{" k " up}"
    ExitApp
}
