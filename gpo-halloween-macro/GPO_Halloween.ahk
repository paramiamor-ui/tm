#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================
;  GPO Halloween - macro de caramelos (graba y repite)
;  F1 = grabar / terminar RUTA de puertas
;  F2 = grabar / terminar COMPRA con la bruja
;  F3 = iniciar / parar el macro
;  F4 = probar solo la compra
;  F8 = cerrar el macro
; ============================================================

; ---------------- CONFIGURACIÓN ----------------
; Cada cuántas vueltas de la ruta se va a comprar (0 = nunca, solo recolectar).
; Ejemplo: si en una vuelta sacas ~60 caramelos y el máximo es 500, pon 8.
COMPRAR_CADA_VUELTAS := 0
; true  = compra una vez y se detiene  ("1x" del video)
; false = compra y sigue recolectando  ("inf" del video)
PARAR_TRAS_COMPRAR := false
; Espera extra (ms) al terminar cada vuelta, para que se recarguen las puertas.
ESPERA_ENTRE_VUELTAS := 2000
; ------------------------------------------------

ROBLOX := "ahk_exe RobloxPlayerBeta.exe"
TECLAS := ["w", "a", "s", "d", "Space", "e", "q", "LShift", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
ARCHIVO_RUTA := A_ScriptDir "\ruta.txt"
ARCHIVO_COMPRA := A_ScriptDir "\compra.txt"

CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
SetKeyDelay 10, 30   ; Roblox ignora pulsaciones demasiado rápidas

estado := "parado"   ; parado | grabando | jugando
eventos := []
pulsadas := Map()
inicioGrabacion := 0
archivoGrabando := ""
ih := ""

MostrarEstado("Listo - F1 grabar ruta, F2 grabar compra, F3 iniciar")

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
    if (estado != "parado")
        return
    if !WinExist(ROBLOX) {
        MsgBox "Abre Roblox primero."
        return
    }
    WinActivate ROBLOX
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
    for linea in eventos
        texto .= linea "`n"
    if FileExist(archivoGrabando)
        FileDelete archivoGrabando
    FileAppend texto, archivoGrabando
    estado := "parado"
    MostrarEstado("Guardado (" eventos.Length " acciones, " Round(t / 1000, 1) " s)")
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

; ================= REPRODUCCIÓN =================

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
    if (COMPRAR_CADA_VUELTAS > 0 && !FileExist(ARCHIVO_COMPRA)) {
        MsgBox "Primero graba la compra con F2 (o pon COMPRAR_CADA_VUELTAS := 0)."
        return
    }
    if !WinExist(ROBLOX) {
        MsgBox "Abre Roblox primero."
        return
    }
    WinActivate ROBLOX
    estado := "jugando"
    SetTimer Bucle, -1
}

F4:: {
    global
    if (estado != "parado")
        return
    if !FileExist(ARCHIVO_COMPRA) {
        MsgBox "Primero graba la compra con F2."
        return
    }
    if !WinExist(ROBLOX) {
        MsgBox "Abre Roblox primero."
        return
    }
    WinActivate ROBLOX
    estado := "jugando"
    SetTimer ProbarCompra, -1
}

Bucle() {
    global
    vueltas := 0
    loop {
        MostrarEstado("Vuelta " (vueltas + 1) " - recorriendo puertas  (F3 = parar)")
        if !Reproducir(ARCHIVO_RUTA)
            break
        vueltas++
        if (COMPRAR_CADA_VUELTAS > 0 && Mod(vueltas, COMPRAR_CADA_VUELTAS) = 0) {
            MostrarEstado("Vuelta " vueltas " - comprando con la bruja")
            if !Reproducir(ARCHIVO_COMPRA)
                break
            if PARAR_TRAS_COMPRAR {
                estado := "parado"
                MostrarEstado("Terminado: compra hecha tras " vueltas " vueltas")
                return
            }
        }
        MostrarEstado("Vuelta " vueltas " terminada - esperando")
        if !Esperar(ESPERA_ENTRE_VUELTAS)
            break
    }
    estado := "parado"
    MostrarEstado("Parado tras " vueltas " vueltas")
}

ProbarCompra() {
    global
    MostrarEstado("Probando compra...")
    ok := Reproducir(ARCHIVO_COMPRA)
    estado := "parado"
    MostrarEstado(ok ? "Prueba de compra terminada" : "Prueba de compra cancelada")
}

; Devuelve false si se paró (F3 o Roblox perdió el foco).
Reproducir(archivo) {
    lineas := StrSplit(Trim(FileRead(archivo), "`r`n"), "`n", "`r")
    inicio := A_TickCount
    for linea in lineas {
        if (linea = "")
            continue
        p := StrSplit(linea, "|")
        t := Integer(p[1])
        while (A_TickCount - inicio < t) {
            if !SeguirJugando() {
                SoltarTodo()
                return false
            }
            Sleep 10
        }
        switch p[2] {
            case "kd": SendEvent "{" p[3] " down}"
            case "ku": SendEvent "{" p[3] " up}"
            default:
                xy := StrSplit(p[3], ",")
                RatonRoblox(p[2], Integer(xy[1]), Integer(xy[2]))
        }
    }
    SoltarTodo()
    return SeguirJugando()
}

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
    return true
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
}

MostrarEstado(texto) {
    ToolTip "GPO Halloween: " texto, 20, 600
}

F8:: {
    SoltarTodo()
    ExitApp
}
