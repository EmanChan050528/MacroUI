#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; MacroUI: a small dark control panel for toggle-style macros.
; Each macro has a rebindable hotkey (click the hotkey box, then press a key or a
; middle/side mouse button).
; Settings are saved to MacroUI.ini next to this script.

SendMode("Input")
SetMouseDelay(-1)
SetKeyDelay(-1, -1)

; ── Theme ───────────────────────────────────────────────────────────────
global C := {
    bg: "13131A", card: "1D1D28", input: "2A2A3A", inputHover: "363649",
    text: "ECECF4", muted: "8C8CA6", accent: "7C5CFF", accentHover: "957BFF",
    green: "3DDC97", red: "E5486A", redHover: "F86685", amber: "FFB547"
}

; ── State ───────────────────────────────────────────────────────────────
global INI := A_ScriptDir "\MacroUI.ini"
global Order := ["hold", "auto", "keys"]
global Hotkeys := Map("hold", "z", "auto", "F6", "keys", "F7", "stop", "F12")
global Macros := Map(
    "hold", {title: "Hold Click", desc: "Holds a mouse button down until you toggle it off.", btn: "Left"},
    "auto", {title: "Auto Clicker", desc: "Clicks repeatedly at the speed you choose.", btn: "Left", cps: 20, gen: 0},
    "keys", {title: "Hold Keys", desc: "Holds every key you pick on the on-screen keyboard.", keys: "w", held: []}
)
for id, m in Macros
    m.active := false, m.countdown := 0, m.ui := {}, m.tick := Tick.Bind(id)

global G := "", CurGui := "", FocusSink := "", NotifyText := ""
global HkBtns := Map()
global KeyIsDown := Map()
global Capturing := false

LoadSettings()
BuildGui()
for id, hk in Hotkeys
    if hk != "" && !RegisterHotkey(id, hk)
        Notify("Couldn't register " PrettyHotkey(hk), C.red)

SetTimer(HoverTrack, 40)
OnMessage(0x20, WM_SETCURSOR)
OnMessage(0x201, WM_LBUTTONDOWN)
OnExit((*) => (StopAll(), 0))
SetupTray()
UpdateTray()

; ── Macros ──────────────────────────────────────────────────────────────
ToggleMacro(id, fromGui := false) {
    m := Macros[id]
    if m.countdown
        return CancelCountdown(id)
    if m.active
        return StopMacro(id)
    ; Starting from the window gives you 3 seconds to move to the target.
    if fromGui
        return BeginCountdown(id)
    StartMacro(id)
}

StartMacro(id) {
    m := Macros[id]
    if m.active
        return
    switch id {
    case "hold":
        Click(m.btn " Down")
    case "auto":
        m.gen += 1
        SetTimer(AutoClickLoop.Bind(m.gen), -1)
    case "keys":
        keys := ParseKeys(m.keys)
        if !keys.Length {
            Notify("Add at least one valid key to hold", C.amber)
            return UpdateCard(id)
        }
        m.held := keys
        for k in keys
            Send("{" k " down}")
    }
    m.active := true
    UpdateCard(id)
}

StopMacro(id) {
    m := Macros[id]
    if !m.active
        return
    m.active := false
    switch id {
    case "hold":
        Click(m.btn " Up")
    case "auto":
        m.gen += 1
    case "keys":
        for k in m.held
            Send("{" k " up}")
        m.held := []
    }
    UpdateCard(id)
}

StopAll(*) {
    for id in Order {
        if Macros[id].countdown
            CancelCountdown(id)
        StopMacro(id)
    }
}

AutoClickLoop(gen) {
    m := Macros["auto"]
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    last := Now()                       ; scheduled time of the previous click
    while m.active && m.gen = gen {
        Click(m.btn)
        ; m.cps is re-read while waiting so speed edits apply live, even mid-wait
        ; on slow settings like 1 click every 100 s.
        while m.gen = gen && (remaining := last + 1000 / m.cps - Now()) > 0 {
            if remaining > 30
                Sleep(Min(remaining - 20, 100))   ; AHK sleep keeps hotkeys/GUI responsive
            else
                DllCall("Sleep", "UInt", remaining > 1.5 ? 1 : 0)
        }
        last += 1000 / m.cps
        if last < Now() - 250           ; fell far behind (e.g. system stall): resync
            last := Now()
        Sleep(-1)
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}

Now() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    count := 0
    DllCall("QueryPerformanceCounter", "Int64*", &count)
    return count * 1000 / freq
}

ParseKeys(text) {
    keys := [], seen := Map()
    seen.CaseSense := false
    for raw in StrSplit(Trim(RegExReplace(text, "\s+", " ")), " ") {
        if raw = ""
            continue
        if !(GetKeyVK(raw) || GetKeySC(raw)) {
            Notify('Unknown key "' raw '"', C.red)
            continue
        }
        name := GetKeyName(raw)
        if !seen.Has(name)
            seen[name] := true, keys.Push(name)
    }
    return keys
}

BeginCountdown(id) {
    Macros[id].countdown := 3
    SetTimer(Macros[id].tick, 1000)
    UpdateCard(id)
}

CancelCountdown(id) {
    SetTimer(Macros[id].tick, 0)
    Macros[id].countdown := 0
    UpdateCard(id)
}

Tick(id) {
    m := Macros[id]
    m.countdown -= 1
    if m.countdown > 0
        return UpdateCard(id)
    SetTimer(m.tick, 0)
    StartMacro(id)
}

; ── Hotkeys ─────────────────────────────────────────────────────────────
RegisterHotkey(id, hk) {
    static current := Map()
    ok := true
    HotIf(HotkeysAllowed)
    if current.Get(id, "") != "" {
        try Hotkey("*$" current[id], "Off")
        try Hotkey("*$" current[id] " up", "Off")
    }
    current[id] := ""
    if hk != "" {
        try {
            Hotkey("*$" hk, HotkeyDown.Bind(id), "On")
            current[id] := hk
            Hotkey("*$" hk " up", HotkeyUp.Bind(id), "On")
        } catch
            ok := false
    }
    HotIf()
    return ok
}

; Ignore keyboard auto-repeat so holding the hotkey toggles only once.
HotkeyDown(id, *) {
    if KeyIsDown.Get(id, false)
        return
    KeyIsDown[id] := true
    if id = "stop"
        StopAll()
    else
        ToggleMacro(id)
}

HotkeyUp(id, *) => KeyIsDown[id] := false

; Don't fire hotkeys while you're typing in one of this window's text boxes.
HotkeysAllowed(*) {
    try {
        if WinActive("ahk_id " G.Hwnd)
            return !(G.FocusedCtrl is Gui.Edit)
    }
    return true
}

BindHotkey(id) {
    b := HkBtns[id], old := Hotkeys[id]
    b.Text := "Press a key"
    b.SetColors(C.accent, C.accentHover)
    hk := CaptureKey()
    if hk != "<cancel>" && hk != old {
        owner := HotkeyOwner(hk)
        if hk != "" && owner != "" {
            Notify(PrettyHotkey(hk) " is already used by " TitleOf(owner), C.red)
        } else if RegisterHotkey(id, hk) {
            Hotkeys[id] := hk
            IniWrite(hk, INI, "Hotkeys", id)
            Notify(hk = "" ? "Hotkey cleared" : TitleOf(id) " → " PrettyHotkey(hk), C.green)
        } else {
            RegisterHotkey(id, old)
            Notify("Can't use " PrettyHotkey(hk) " as a hotkey", C.red)
        }
    }
    b.Text := PrettyHotkey(Hotkeys[id])
    b.SetColors(C.input, C.inputHover)
}

; Waits for one key press or a middle/side mouse button click, with any held
; modifiers. Esc cancels; Backspace/Delete clears the hotkey.
CaptureKey() {
    global Capturing
    static mouseButtons := ["MButton", "XButton1", "XButton2"]
    if Capturing
        return "<cancel>"
    Capturing := true
    wasSuspended := A_IsSuspended
    Suspend(true)

    ih := InputHook("L0 T6")
    ih.KeyOpt("{All}", "ES")
    ; Modifiers combine with the next key instead of ending the capture.
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-ES")

    ; InputHook can't see the mouse, so listen for mouse buttons with temporary
    ; suspend-exempt hotkeys. Left/right click are left alone so the UI stays usable.
    mouse := {key: "", mods: ""}
    onMouse := (name) => (mouse.key := LTrim(name, "*"), mouse.mods := HeldModifiers(), ih.Stop())
    HotIf()
    for b in mouseButtons
        Hotkey("*" b, onMouse, "On S")

    ih.Start()
    ih.Wait()
    for b in mouseButtons
        Hotkey("*" b, "Off")
    Suspend(wasSuspended)
    Capturing := false

    if mouse.key != ""
        return mouse.mods mouse.key
    if ih.EndReason != "EndKey" || ih.EndKey = "Escape"
        return "<cancel>"
    key := StrLen(ih.EndKey) = 1 ? StrLower(ih.EndKey) : ih.EndKey
    if key = "Backspace" || key = "Delete"
        return ""
    mods := ""
    for sym in ["^", "!", "+", "#"]
        if InStr(ih.EndMods, sym)
            mods .= sym
    return mods key
}

HeldModifiers() {
    mods := ""
    for sym, key in Map("^", "Ctrl", "!", "Alt", "+", "Shift")
        if GetKeyState(key)
            mods .= sym
    if GetKeyState("LWin") || GetKeyState("RWin")
        mods .= "#"
    return mods
}

HotkeyOwner(hk) {
    for id, h in Hotkeys
        if h = hk
            return id
    return ""
}

TitleOf(id) => id = "stop" ? "Stop all" : Macros[id].title

PrettyHotkey(hk) {
    static names := Map("^", "Ctrl", "!", "Alt", "+", "Shift", "#", "Win")
    static mouseNames := Map("MButton", "Middle Click", "XButton1", "Mouse 4", "XButton2", "Mouse 5")
    if hk = ""
        return "None"
    out := ""
    while StrLen(hk) > 1 && names.Has(SubStr(hk, 1, 1)) {
        out .= names[SubStr(hk, 1, 1)] "+"
        hk := SubStr(hk, 2)
    }
    if mouseNames.Has(hk)
        return out mouseNames[hk]
    return out (StrLen(hk) = 1 ? StrUpper(hk) : hk)
}

; ── Settings ────────────────────────────────────────────────────────────
LoadSettings() {
    for id in ["hold", "auto", "keys", "stop"]
        Hotkeys[id] := IniRead(INI, "Hotkeys", id, Hotkeys[id])
    Macros["hold"].btn := ValidButton(IniRead(INI, "Hold", "button", "Left"))
    Macros["auto"].btn := ValidButton(IniRead(INI, "Auto", "button", "Left"))
    Macros["auto"].cps := ClampCps(IniRead(INI, "Auto", "cps", 20))
    Macros["keys"].keys := IniRead(INI, "Keys", "keys", "w")
}

ValidButton(b) => (b = "Left" || b = "Right" || b = "Middle") ? b : "Left"
ClampCps(v) => IsNumber(v) && v > 0 ? Max(0.01, Min(1000, v + 0)) : 20

; Shortest plain decimal for display (0.2, not 0.20000000000000001).
FormatNum(v) => RegExReplace(Format("{:.4f}", v), "\.?0+$")

; Describes a clicks-per-second rate in human terms, e.g. 0.2 → "1 click per 5 seconds".
DescribeCps(cps) {
    plural(n, word) => n " " word (n = 1 ? "" : "s")
    ; Look for a whole number of seconds that holds a whole number of clicks.
    loop 100 {
        clicks := cps * A_Index
        if Abs(clicks - Round(clicks)) < 0.0001
            return plural(Round(clicks), "click") " per " (A_Index = 1 ? "second" : A_Index " seconds")
    }
    return "1 click every " FormatNum(1 / cps) " seconds"
}

PickHoldButton(value) {
    m := Macros["hold"]
    if m.btn = value
        return
    wasActive := m.active
    StopMacro("hold")
    m.btn := value
    IniWrite(value, INI, "Hold", "button")
    if wasActive
        StartMacro("hold")
}

PickAutoButton(value) {
    Macros["auto"].btn := value
    IniWrite(value, INI, "Auto", "button")
}

CpsChanged(e, *) {
    m := Macros["auto"]
    if !IsNumber(e.Value) || e.Value <= 0 {
        m.ui.cpsHint.SetFont("c" C.amber)
        m.ui.cpsHint.Text := "Enter a number above 0"
        return
    }
    m.cps := ClampCps(e.Value)
    IniWrite(FormatNum(m.cps), INI, "Auto", "cps")
    UpdateCpsHint()
}

UpdateCpsHint() {
    m := Macros["auto"]
    m.ui.cpsHint.SetFont("c" C.muted)
    m.ui.cpsHint.Text := DescribeCps(m.cps)
}

; ── Key picker (on-screen keyboard for Hold Keys) ───────────────────────
; Row tokens are "name:label:width" (label and width optional, width in key
; units); "_n" is an empty gap of n units.
global KbMain := [
    "Escape:Esc _1 F1 F2 F3 F4 _0.5 F5 F6 F7 F8 _0.5 F9 F10 F11 F12",
    "`` 1 2 3 4 5 6 7 8 9 0 - = Backspace::2",
    "Tab::1.5 q w e r t y u i o p [ ] \::1.5",
    "CapsLock:Caps:1.75 a s d f g h j k l `; ' Enter::2.25",
    "LShift:Shift:2.25 z x c v b n m , . / RShift:Shift:2.75",
    "LControl:Ctrl:1.25 LWin:Win:1.25 LAlt:Alt:1.25 Space::6.25 RAlt:Alt:1.25 RWin:Win:1.25 AppsKey:Menu:1.25 RControl:Ctrl:1.25"
]
global KbNav := [
    "PrintScreen:PrtSc ScrollLock:ScrLk Pause",
    "Insert:Ins Home PgUp",
    "Delete:Del End PgDn",
    "",
    "_1 Up:↑",
    "Left:← Down:↓ Right:→"
]
global KbMouse := [["LButton", "Left Click"], ["RButton", "Right Click"], ["MButton", "Middle Click"], ["XButton1", "Mouse 4"], ["XButton2", "Mouse 5"]]
global KB := "", KeyCaps := Map(), KbSummary := "", KbNote := ""

OpenKeyPicker(*) {
    if !KB
        BuildKeyPicker()
    PaintKeyCaps()
    KbNote.Text := Macros["keys"].active ? "Hold Keys is running. Changes apply the next time it starts." : ""
    G.GetPos(&gx, &gy, &gw)
    KB.GetPos(, , &kw)
    KB.Show(Format("x{} y{}", Max(0, gx + (gw - kw) // 2), gy + 80))
}

BuildKeyPicker() {
    global KB, KbSummary, KbNote, CurGui
    u := 38, x0 := 20, y0 := 70          ; key unit size, keyboard origin
    KB := Gui("+Owner" G.Hwnd " -MinimizeBox -MaximizeBox", "Choose keys to hold")
    KB.BackColor := C.bg
    KB.MarginX := KB.MarginY := 0
    KB.OnEvent("Close", (*) => KB.Hide())
    KB.OnEvent("Escape", (*) => KB.Hide())
    CurGui := KB

    Font("s13 w600")
    KB.AddText("x20 y14 w400 h28 Background" C.bg, "Choose keys to hold")
    Font("s9 c" C.muted)
    KB.AddText("x20 y42 w600 h18 Background" C.bg, "Click keys to select them. Everything selected is held down together.")

    Font("s9")
    for i, row in KbMain
        AddKeyRow(row, x0, y0 + (i - 1) * u + (i > 1 ? 8 : 0), u)
    for i, row in KbNav
        AddKeyRow(row, x0 + 15.5 * u, y0 + (i - 1) * u + (i > 1 ? 8 : 0), u)

    y := y0 + 6 * u + 8 + 14
    Font("s8 w600 c" C.muted)
    KB.AddText(Format("x{} y{} w200 h14 Background{}", x0, y, C.bg), "MOUSE")
    Font("s9")
    for i, b in KbMouse
        AddKeyCap(b[1], b[2], x0 + (i - 1) * 2 * u, y + 20, 2 * u - 4, u - 4)

    y += 20 + u + 16
    Font("s9 c" C.muted)
    KbSummary := KB.AddText(Format("x{} y{} w440 h18 Background{}", x0, y, C.bg))
    Font("s9 c" C.amber)
    KbNote := KB.AddText(Format("x{} y{} w440 h18 Background{}", x0, y + 18, C.bg))
    w := x0 * 2 + 18.5 * u - 4
    Font("s10 w600")
    Btn(Format("x{} y{} w80 h32", w - 20 - 168, y), "Clear", (*) => SetHeldKeys([]), C.input, C.inputHover)
    Btn(Format("x{} y{} w80 h32", w - 20 - 80, y), "Done", (*) => KB.Hide(), C.accent, C.accentHover, "FFFFFF")

    CurGui := G
    DarkTitleBar(KB.Hwnd)
    KB.Show(Format("Hide w{} h{}", w, y + 52))
}

AddKeyRow(row, x, y, u) {
    for tok in StrSplit(row, " ") {
        if tok = ""
            continue
        if SubStr(tok, 1, 1) = "_" && StrLen(tok) > 1 {
            x += SubStr(tok, 2) * u
            continue
        }
        parts := StrSplit(tok, ":")
        name := parts[1]
        label := parts.Length >= 2 && parts[2] != "" ? parts[2] : (StrLen(name) = 1 ? StrUpper(name) : name)
        width := parts.Length >= 3 ? parts[3] * u : u
        AddKeyCap(name, label, x, y, width - 4, u - 4)
        x += width
    }
}

AddKeyCap(name, label, x, y, w, h) {
    key := GetKeyName(name)
    b := Btn(Format("x{} y{} w{} h{}", Round(x), Round(y), Round(w), h), label, (*) => ToggleHeldKey(key), C.input, C.inputHover)
    KeyCaps[StrLower(key)] := b
}

ToggleHeldKey(key) {
    keys := ParseKeys(Macros["keys"].keys)
    for i, k in keys
        if k = key
            return (keys.RemoveAt(i), SetHeldKeys(keys))
    keys.Push(key)
    SetHeldKeys(keys)
}

SetHeldKeys(keys) {
    text := ""
    for k in keys
        text .= (text = "" ? "" : " ") k
    Macros["keys"].keys := text
    IniWrite(text, INI, "Keys", "keys")
    PaintKeyCaps()
    Macros["keys"].ui.pick.Text := KeysSummary(keys, 26)
}

PaintKeyCaps() {
    if !KB
        return
    selected := Map()
    selected.CaseSense := false
    keys := ParseKeys(Macros["keys"].keys)
    for k in keys
        selected[k] := true
    for name, b in KeyCaps {
        if selected.Has(name)
            b.SetColors(C.accent, C.accentHover, "FFFFFF")
        else
            b.SetColors(C.input, C.inputHover, C.text)
    }
    KbSummary.Text := keys.Length ? "Selected: " KeysSummary(keys, 70) : "No keys selected"
}

KeysSummary(keys, maxLen) {
    if !keys.Length
        return "Choose keys…"
    text := ""
    for k in keys
        text .= (text = "" ? "" : " + ") (StrLen(k) = 1 ? StrUpper(k) : k)
    return StrLen(text) > maxLen ? SubStr(text, 1, maxLen - 1) "…" : text
}

; ── GUI ─────────────────────────────────────────────────────────────────
BuildGui() {
    global G, CurGui, FocusSink, NotifyText
    G := Gui("-MaximizeBox", "MacroUI")
    CurGui := G
    G.BackColor := C.bg
    G.MarginX := G.MarginY := 0
    G.OnEvent("Close", (*) => ExitApp())
    G.OnEvent("Size", (g, minMax, *) => minMax = -1 ? HideToTray() : 0)
    FocusSink := G.AddButton("x0 y0 w0 h0")   ; parks keyboard focus away from text boxes

    Font("s20 w700")
    G.AddText("x20 y12 w240 h38 Background" C.bg, "MacroUI")
    Font("s9 c" C.muted)
    G.AddText("x22 y52 w220 h18 Background" C.bg, "Toggle macros with hotkeys or buttons.")
    NotifyText := G.AddText("x230 y52 w230 h18 Right Background" C.bg)

    y := 84
    for id in Order {
        AddCard(id, y)
        y += 144
    }
    AddFooter(y)

    DarkTitleBar(G.Hwnd)
    G.Show("w480 h" (y + 76))
}

AddCard(id, y) {
    m := Macros[id], x := 20, w := 440
    G.AddText(Format("x{} y{} w{} h132 Background{}", x, y, w, C.card))

    Font("s11 w600")
    G.AddText(Format("x{} y{} w260 h22 Background{}", x + 16, y + 14, C.card), m.title)
    Font("s8 w600")
    m.ui.status := G.AddText(Format("x{} y{} w160 h20 Right Background{} c{}", x + w - 176, y + 17, C.card, C.muted))
    Font("s9 c" C.muted)
    G.AddText(Format("x{} y{} w408 h18 Background{}", x + 16, y + 38, C.card), m.desc)

    Label(x + 16, y + 66, "HOTKEY")
    Font("s9")
    HkBtns[id] := Btn(Format("x{} y{} w90 h32", x + 16, y + 84), PrettyHotkey(Hotkeys[id]), (*) => BindHotkey(id), C.input, C.inputHover)

    switch id {
    case "hold":
        Label(x + 118, y + 66, "BUTTON")
        AddSegmented(x + 118, y + 84, 56, m.btn, PickHoldButton)
    case "auto":
        Label(x + 118, y + 66, "BUTTON")
        AddSegmented(x + 118, y + 84, 44, m.btn, PickAutoButton)
        Label(x + 264, y + 66, "CLICKS / SEC")
        e := AddInput(x + 264, y + 84, 68, FormatNum(m.cps), "Limit7 Center")
        Font("s8 c" C.muted)
        m.ui.cpsHint := CurGui.AddText(Format("x{} y{} w200 h14 Right Background{}", x + 132, y + 117, C.card))
        UpdateCpsHint()
        e.OnEvent("Change", CpsChanged)
        e.OnEvent("LoseFocus", (e, *) => (e.Value := FormatNum(Macros["auto"].cps), UpdateCpsHint()))
    case "keys":
        Label(x + 118, y + 66, "KEYS TO HOLD")
        Font("s9")
        m.ui.pick := Btn(Format("x{} y{} w214 h32", x + 118, y + 84), KeysSummary(ParseKeys(m.keys), 26), OpenKeyPicker, C.input, C.inputHover)
    }

    Font("s10 w600")
    m.ui.start := Btn(Format("x{} y{} w80 h32", x + w - 96, y + 84), "Start", (*) => ToggleMacro(id, true), C.accent, C.accentHover, "FFFFFF")
    UpdateCard(id)
}

AddFooter(y) {
    x := 20, w := 440
    G.AddText(Format("x{} y{} w{} h56 Background{}", x, y, w, C.card))
    Font("s10 w600")
    G.AddText(Format("x{} y{} w150 h32 +0x200 Background{}", x + 16, y + 12, C.card), "Stop all macros")
    Font("s9")
    HkBtns["stop"] := Btn(Format("x{} y{} w90 h32", x + w - 194, y + 12), PrettyHotkey(Hotkeys["stop"]), (*) => BindHotkey("stop"), C.input, C.inputHover)
    Font("s10 w600")
    Btn(Format("x{} y{} w80 h32", x + w - 96, y + 12), "Stop all", (*) => StopAll(), C.red, C.redHover, "FFFFFF")
}

Font(opts := "") {
    CurGui.SetFont("norm s10 c" C.text " " opts, "Segoe UI")
    CurGui.SetFont(, "Segoe UI Variable Text")   ; Windows 11 font; silently ignored if missing
}

Label(x, y, text) {
    Font("s8 w600 c" C.muted)
    G.AddText(Format("x{} y{} w140 h14 Background{}", x, y, C.card), text)
}

AddInput(x, y, w, text, opts := "") {
    G.AddText(Format("x{} y{} w{} h32 Background{}", x, y, w, C.input))
    Font("s10")
    return G.AddEdit(Format("x{} y{} w{} h20 -E0x200 Background{} c{} {}", x + 10, y + 6, w - 20, C.input, C.text, opts), text)
}

AddSegmented(x, y, w, current, onPick) {
    segs := []
    Font("s9")
    for name in ["Left", "Right", "Middle"] {
        b := Btn(Format("x{} y{} w{} h32", x + (A_Index - 1) * (w + 2), y, w), name, SegClick.Bind(segs, name, onPick), C.input, C.inputHover)
        b.value := name
        segs.Push(b)
    }
    PaintSegments(segs, current)
}

SegClick(segs, value, onPick, *) {
    PaintSegments(segs, value)
    onPick(value)
}

PaintSegments(segs, value) {
    for b in segs {
        if b.value = value
            b.SetColors(C.accent, C.accentHover, "FFFFFF")
        else
            b.SetColors(C.input, C.inputHover, C.text)
    }
}

UpdateCard(id) {
    m := Macros[id], ui := m.ui
    if m.countdown {
        SetStatus(ui.status, "STARTING IN " m.countdown, C.amber)
        ui.start.Text := "Cancel " m.countdown
        ui.start.SetColors(C.input, C.inputHover)
    } else if m.active {
        SetStatus(ui.status, "RUNNING", C.green)
        ui.start.Text := "Stop"
        ui.start.SetColors(C.red, C.redHover)
    } else {
        SetStatus(ui.status, "IDLE", C.muted)
        ui.start.Text := "Start"
        ui.start.SetColors(C.accent, C.accentHover)
    }
    UpdateTray()
}

SetStatus(ctrl, text, color) {
    ctrl.SetFont("c" color)
    ctrl.Text := "●  " text
}

; Minimizing hides the window to the tray; hotkeys keep working. Click the
; tray icon to bring it back.
SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Show MacroUI", ShowFromTray)
    A_TrayMenu.Add("Stop all macros", (*) => StopAll())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Show MacroUI"
    A_TrayMenu.ClickCount := 1
}

HideToTray() {
    static told := false
    G.Hide()
    if KB
        KB.Hide()
    if !told {
        told := true
        TrayTip("Hotkeys still work. Click the tray icon to open it again.", "MacroUI is running in the background", "Mute")
    }
}

ShowFromTray(*) {
    G.Show()
    G.Restore()
    WinActivate(G)
}

UpdateTray() {
    n := 0
    for id in Order
        n += Macros[id].active
    A_IconTip := "MacroUI: " (n ? n " running" : "idle")
}

Notify(msg, color := "") {
    NotifyText.SetFont("c" (color = "" ? C.muted : color))
    NotifyText.Text := msg
    SetTimer(ClearNotify, -3500)
}

ClearNotify() => NotifyText.Text := ""

DarkTitleBar(hwnd) {
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 20, "Int*", 1, "Int", 4)
    bgr := Integer("0x" SubStr(C.bg, 5, 2) SubStr(C.bg, 3, 2) SubStr(C.bg, 1, 2))
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 35, "Int*", bgr, "Int", 4)   ; Win11 caption color
}

; Hover highlight for custom buttons.
HoverTrack() {
    static cur := 0
    MouseGetPos(, , , &h, 2)
    if h = cur
        return
    if Btn.All.Has(cur)
        Btn.All[cur].SetHot(false)
    cur := h
    if Btn.All.Has(h)
        Btn.All[h].SetHot(true)
}

WM_SETCURSOR(wParam, *) {
    if Btn.All.Has(wParam) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32649, "Ptr"))   ; IDC_HAND
        return true
    }
}

; Clicking anywhere except a text box takes focus out of the text boxes.
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    try {
        if DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = G.Hwnd   ; main window only
            && !(GuiCtrlFromHwnd(hwnd) is Gui.Edit)
            FocusSink.Focus()
    }
}

; A flat, colored, clickable label used for every button in the window.
class Btn {
    static All := Map()

    __New(opts, label, onClick, bg, hoverBg, fg := C.text) {
        this.bg := bg, this.hoverBg := hoverBg, this.hot := false
        this.ctrl := CurGui.AddText(opts " +0x100 +0x200 Center Background" bg " c" fg, label)
        fn := (*) => onClick(this)
        this.ctrl.OnEvent("Click", fn)
        this.ctrl.OnEvent("DoubleClick", fn)
        Btn.All[this.ctrl.Hwnd] := this
    }

    Text {
        get => this.ctrl.Text
        set => this.ctrl.Text := value
    }

    SetColors(bg, hoverBg, fg := "") {
        this.bg := bg, this.hoverBg := hoverBg
        if fg != ""
            this.ctrl.SetFont("c" fg)
        this.Paint()
    }

    SetHot(on) {
        this.hot := on
        this.Paint()
    }

    Paint() {
        this.ctrl.Opt("Background" (this.hot ? this.hoverBg : this.bg))
        this.ctrl.Redraw()
    }
}
