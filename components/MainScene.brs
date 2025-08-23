'========================
' Lifecycle
'========================
sub init()
  ' ==== Load server URL (no trailing slash) ====
  ' If the server is on a different address, app will prompt on start
  m.server = regLoadServer()
  if m.server = "" then m.server = "http://192.168.1.100:8008"

  ' SceneGraph nodes
  m.lbl        = m.top.findNode("path")
  m.folders    = m.top.findNode("folders")
  m.filesGrid  = m.top.findNode("filesGrid")
  m.keyCatcher = m.top.findNode("keyCatcher")

  ' App state
  m.stack           = CreateObject("roArray", 0, true) ' [{id,name}]
  m.folderItems     = CreateObject("roArray", 0, true) ' left list items
  m.fileItems       = CreateObject("roArray", 0, true) ' right grid items
  m.fileItemsAlpha  = CreateObject("roArray", 0, true)
  m.alphaIndex      = CreateObject("roAssociativeArray") ' id->alpha index
  m.currentMediaKey = ""
  m.authToken       = ""
  m.video           = invalid
  m.task            = invalid
  m.pendingDir      = invalid

  ' Non-blocking PIN/auth dialog state
  m.pinDialog     = invalid
  m.pinPendingDir = invalid
  m.authTask      = invalid

  ' Non-blocking Settings dialog state
  m.settingsDialog = invalid
  m.settingsOpen   = false

  ' Observers
  m.folders.ObserveField("itemSelected", "onFolderSelect")
  m.filesGrid.ObserveField("itemSelected", "onFileSelect")

  ' Start at root
  if m.lbl <> invalid then m.lbl.text = "Loading..."
  m.top.setFocus(true)
  m.folders.setFocus(true)
  browseAsync(invalid)
end sub

'========================
' HTTP: browse
'========================
sub browseAsync(dirId as Dynamic)
  url = m.server + "/api/browse"
  if dirId <> invalid then
    url = url + "?dir_id=" + toQuery(dirId)
  end if

  if m.task <> invalid then m.task.control = "stop"

  t = CreateObject("roSGNode", "ApiTask")
  t.url = url
  ' include bearer token if present
  if m.authToken <> "" then
    h = CreateObject("roAssociativeArray")
    h.Authorization = "Bearer " + m.authToken
    t.headers = h
  end if
  t.ObserveField("response", "onBrowseResponse")
  m.top.AppendChild(t)
  m.task = t

  ' remember which folder we tried to browse (for PIN retry)
  m.pendingDir = dirId

  t.control = "run"
end sub

function toQuery(v as Dynamic) as String
  if v = invalid then return ""
  s = FormatJson(v)
  if Len(s) >= 2 then
    first = mid(s, 1, 1)
    lastc = mid(s, Len(s), 1)
    if first = Chr(34) and lastc = Chr(34) then
      return mid(s, 2, Len(s) - 2)
    end if
  end if
  return s
end function

sub onBrowseResponse()
  if m.task = invalid then return

  resp = m.task.response
  if resp = invalid or resp.ok <> true then
    if m.lbl <> invalid then m.lbl.text = "Cannot reach " + m.server
    ' Auto-prompt Settings once so user can change IP
    if not m.settingsOpen then
      showServerDialog(true)
    end if
    return
  end if

  j = resp.json
  if j = invalid then
    if m.lbl <> invalid then m.lbl.text = "Invalid JSON"
    return
  end if

  ' restricted folder: show non-blocking PIN dialog and return ---
  if j.DoesExist("authorized") and j.authorized = false then
    if m.keyCatcher <> invalid then m.keyCatcher.visible = false
    m.top.setFocus(true)
    showPinDialog(m.pendingDir)
    return
  end if

  data = normalizeBrowse(j)
  if data = invalid then
    if m.lbl <> invalid then m.lbl.text = "Unexpected JSON"
    return
  end if

  ' maintain visible path stack
  if m.stack.Count() = 0 or m.stack[m.stack.Count()-1].id <> data.dirId then
    e = { id: data.dirId, name: data.dirName }
    m.stack.Push(e)
  end if
  renderPath()

  ' left: folders (+Up if not root)
  m.folderItems = CreateObject("roArray", 0, true)
  if m.stack.Count() > 1 then m.folderItems.Push({ id: -1, title: ".. (Up)" })

  i = 0
  while i < data.folders.Count()
    f = data.folders[i]
    m.folderItems.Push({ id: f.id, title: f.name })
    i = i + 1
  end while

  renderFolders()

  ' right: files
  m.fileItems = CreateObject("roArray", 0, true)
  k = 0
  while k < data.videos.Count()
    v = data.videos[k]
    m.fileItems.Push({ id: v.id, title: v.name })
    k = k + 1
  end while
  renderFiles()

  rebuildAlphaIndex()
  m.folders.setFocus(true)
end sub


'========================
' Normalize server JSON
'========================
function normalizeBrowse(j as Object) as Dynamic
  if j = invalid then return invalid

  ' primary shape: {dir, subdirs, media}
  if j.DoesExist("dir") then
    out = {
      dirId: j.dir.id,
      dirName: pickName(j.dir),
      folders: CreateObject("roArray", 0, true),
      videos: CreateObject("roArray", 0, true)
    }
    if j.DoesExist("subdirs") then
      i = 0
      while i < j.subdirs.Count()
        d = j.subdirs[i]
        out.folders.Push({ id: d.id, name: pickName(d) })
        i = i + 1
      end while
    end if
    if j.DoesExist("media") then
      i = 0
      while i < j.media.Count()
        mrow = j.media[i]
        out.videos.Push({ id: mrow.id, name: pickName(mrow) })
        i = i + 1
      end while
    end if
    return out
  end if

  ' alternate shape: {folder, items}
  if j.DoesExist("folder") and j.DoesExist("items") then
    out = {
      dirId: j.folder.id,
      dirName: pickName(j.folder),
      folders: CreateObject("roArray", 0, true),
      videos: CreateObject("roArray", 0, true)
    }
    i = 0
    while i < j.items.Count()
      it = j.items[i]
      t = "" : if it.DoesExist("type") then t = LCase(it.type)
      if t = "folder" or t = "directory" then
        out.folders.Push({ id: it.id, name: pickName(it) })
      else if t = "video" or t = "file" then
        out.videos.Push({ id: it.id, name: pickName(it) })
      end if
      i = i + 1
    end while
    return out
  end if

  return invalid
end function

function pickName(o as Dynamic) as String
  if o = invalid then return "Untitled"
  n = ""
  if o.DoesExist("name") then n = o.name
  if n = "" and o.DoesExist("title") then n = o.title
  if n = "" and o.DoesExist("label") then n = o.label
  if n = "" and o.DoesExist("filename") then n = o.filename
  if n = "" and o.DoesExist("basename") then n = o.basename
  if n = "" then
    if o.DoesExist("id") then
      n = "ID " + toQuery(o.id)
    else
      n = "Untitled"
    end if
  end if
  return n
end function

'========================
' UI renderers
'========================
sub renderFolders()
  root = CreateObject("roSGNode", "ContentNode")
  i = 0
  while i < m.folderItems.Count()
    it = m.folderItems[i]
    n = CreateObject("roSGNode", "ContentNode")
    n.title = it.title
    root.AppendChild(n)
    i = i + 1
  end while
  m.folders.content = root
end sub

sub renderFiles()
  root = CreateObject("roSGNode", "ContentNode")
  i = 0
  while i < m.fileItems.Count()
    it = m.fileItems[i]
    n = CreateObject("roSGNode", "ContentNode")
    n.title = it.title

    ' Poster from server: /api/art?name=<base> (percent-encoded)
    base = ms_stripExt(it.title)
    safe = ms_urlEncode(base)
    artUrl = m.server + "/api/art?name=" + safe
    n.hdPosterUrl = artUrl

    root.AppendChild(n)
    i = i + 1
  end while
  m.filesGrid.content = root
end sub

sub renderPath()
  if m.stack.Count() = 0 then
    if m.lbl <> invalid then m.lbl.text = "/"
    return
  end if

  path = ""
  i = 0
  while i < m.stack.Count()
    e = m.stack[i]
    path = path + "/" + e.name
    i = i + 1
  end while

  if path = "" then path = "/"
  if m.lbl <> invalid then m.lbl.text = path
end sub

'========================
' Selection handlers
'========================
sub onFolderSelect()
  idx = m.folders.itemSelected
  if idx = invalid then return
  if idx < 0 or idx >= m.folderItems.Count() then return

  it = m.folderItems[idx]
  ' Handle Up
  if it.id = -1 then
    goUp()
    return
  end if

  ' No Settings special case anymore — just browse into folders
  browseInto(it.id, it.title)
end sub

sub onFileSelect()
  idx = m.filesGrid.itemSelected
  if idx = invalid then return
  if idx < 0 or idx >= m.fileItems.Count() then return

  it = m.fileItems[idx]
  playVideo(it.id, it.title)
end sub

sub browseInto(dirId as Dynamic, name as Dynamic)
  e = { id: dirId, name: name }
  m.stack.Push(e)
  renderPath()
  m.stack.Pop() ' server will re-confirm canonical name on response
  if m.lbl <> invalid then m.lbl.text = "Loading..."
  browseAsync(dirId)
end sub

'========================
' Key handling
'========================
function onKeyEvent(key as String, press as Boolean) as Boolean
  if not press then return false
  k = LCase(key)

  ' During playback, intercept keys so grid doesn’t move
  if m.video <> invalid then
    if k = "back" then
      m.video.control = "stop"
      m.video.visible = false
      if m.video.Lookup("close") <> invalid then m.video.close = true
      m.video = invalid
      if m.keyCatcher <> invalid then m.keyCatcher.visible = false
      if m.filesGrid <> invalid then m.filesGrid.setFocus(true)
      return true

    else if k = "ok" or k = "select" or k = "play" or k = "playpause" then
      s = m.video.state
      if s = "playing" then
        m.video.control = "pause"
      else if s = "paused" then
        m.video.control = "resume"
      end if
      return true

    else if k = "left" then
      seekBy(-10) : return true
    else if k = "right" then
      seekBy(10) : return true
    else if k = "rewind" or k = "rev" then
      seekBy(-60) : return true
    else if k = "fastforward" or k = "fwd" then
      seekBy(60) : return true
    else if k = "replay" or k = "instantreplay" then
      seekTo(0) : return true
    end if

    return true ' swallow other keys during playback
  end if

  ' Pane switching & back when not playing
  if k = "right" and m.folders.hasFocus() then
    m.filesGrid.setFocus(true)
    if m.fileItems.Count() > 0 and (m.filesGrid.itemFocused = invalid or m.filesGrid.itemFocused < 0) then
      m.filesGrid.jumpToItem = 0
    end if
    return true
  end if

  if k = "left" and m.filesGrid.hasFocus() then
    idx = m.filesGrid.itemFocused
    numCols = m.filesGrid.numColumns
    col = 0
    if idx <> invalid and numCols <> invalid and numCols > 0 then
      col = idx mod numCols
    end if
    if col = 0 then
      m.folders.setFocus(true)
      return true
    else
      return false
    end if
  end if

  if k = "back" then
    if goUp() then return true
    return confirmExit()
  end if

  return false
end function

'========================
' Seek helpers
'========================
sub seekBy(delta as Integer)
  if m.video = invalid then return
  curpos = m.video.position : if curpos = invalid then curpos = 0
  dur = m.video.duration
  newpos = curpos + delta
  if newpos < 0 then newpos = 0
  if dur <> invalid and newpos > dur - 1 then newpos = dur - 1
  m.video.seek = newpos
end sub

sub seekTo(p as Integer)
  if m.video = invalid then return
  if p < 0 then p = 0
  m.video.seek = p
end sub

'========================
' Nav helpers
'========================
function goUp() as Boolean
  if m.stack.Count() > 1 then
    m.stack.Pop()
    parent = m.stack[m.stack.Count()-1]
    m.stack.Pop()
    m.authToken = ""
    if m.lbl <> invalid then m.lbl.text = "Loading..."
    browseAsync(parent.id)
    return true
  end if
  return false
end function

function confirmExit() as Boolean
  d = CreateObject("roSGNode", "Dialog")
  d.title = "Exit?"
  d.message = "Leave the app?"
  d.buttons = ["Cancel", "Exit"]
  m.top.AppendChild(d)

  p = CreateObject("roMessagePort")
  d.ObserveField("buttonSelected", p)
  while true
    wait(0, p)
    if d.buttonSelected <> invalid then
      if d.buttonSelected = 1 then
        m.top.close = true
        return true
      else
        d.close = true
        return true
      end if
    end if
  end while
end function

'========================
' PIN / Auth (NON-BLOCKING)
'========================
sub showPinDialog(dirId as Integer)
  m.pinPendingDir = dirId

  if m.pinDialog <> invalid then
    m.pinDialog.close = true
    m.pinDialog = invalid
  end if

  dlg = CreateObject("roSGNode", "PinDialog")
  if dlg <> invalid then
    dlg.title   = "Restricted"
    dlg.message = "Enter PIN"
    if dlg.Lookup("pinLength") <> invalid then dlg.pinLength = 4
    if dlg.Lookup("numPinEntryFields") <> invalid then dlg.numPinEntryFields = 4
    dlg.buttons = ["OK","Cancel"]
    m.top.AppendChild(dlg)
    dlg.setFocus(true)
    dlg.ObserveField("buttonSelected", "onPinDialogButton")
    m.pinDialog = dlg
    return
  end if

  kd = CreateObject("roSGNode", "KeyboardDialog")
  kd.title         = "Restricted"
  kd.message       = "Enter PIN"
  kd.buttons       = ["OK","Cancel"]
  kd.obscureText   = true
  kd.maxTextLength = 12
  if kd.Lookup("keyboardMode") <> invalid then kd.keyboardMode = "number"
  kd.text = ""
  m.top.AppendChild(kd)
  kd.setFocus(true)
  kd.ObserveField("buttonSelected", "onPinDialogButton")
  m.pinDialog = kd
end sub

sub dismissPinDialog()
  if m.pinDialog <> invalid then
    m.pinDialog.visible = false
    m.top.removeChild(m.pinDialog)
    m.pinDialog = invalid
  end if
end sub

sub onPinDialogButton()
  if m.pinDialog = invalid then return
  sel = m.pinDialog.buttonSelected
  if sel = invalid then return

  if sel = 0 then ' OK
    pin = ""
    if m.pinDialog.Lookup("pin") <> invalid then pin = m.pinDialog.pin
    if (pin = "" or pin = invalid) and m.pinDialog.Lookup("text") <> invalid then pin = m.pinDialog.text

    dismissPinDialog()

    if pin <> invalid and pin <> "" then
      startAuthTask(m.pinPendingDir, pin)
    else
      if m.lbl <> invalid then m.lbl.text = "PIN required"
    end if
  else
    dismissPinDialog()
    if m.lbl <> invalid then m.lbl.text = "PIN cancelled"
  end if
end sub

sub startAuthTask(dirId as Integer, pin as String)
  if m.authTask <> invalid then m.authTask.control = "stop"

  t = CreateObject("roSGNode", "ApiTask")
  t.url = m.server + "/api/auth/folder"
  t.method = "POST"
  t.body = FormatJson({ dir_id: dirId, pin: pin })
  t.ObserveField("response", "onAuthResponse")
  m.top.AppendChild(t)
  m.authTask = t
  t.control = "run"
end sub

sub onAuthResponse()
  if m.authTask = invalid then return
  r = m.authTask.response
  if r = invalid then return

  ' ensure any dialog is gone
  dismissPinDialog()

  if r.ok = true and r.json <> invalid and r.json.token <> invalid and r.json.token <> "" then
    m.authToken = r.json.token
    if m.lbl <> invalid then m.lbl.text = "Loading..."
    browseAsync(m.pinPendingDir)
  else
    if m.lbl <> invalid then m.lbl.text = "Invalid PIN"
  end if

  m.authTask = invalid
end sub

'========================
' Settings dialog (NON-BLOCKING)
'========================
sub showServerDialog(autoLaunch as Boolean)
  if m.settingsOpen then return
  m.settingsOpen = true

  if m.settingsDialog <> invalid then
    m.top.removeChild(m.settingsDialog)
    m.settingsDialog = invalid
  end if

  d = CreateObject("roSGNode", "KeyboardDialog")
  d.title = "Settings"
  if autoLaunch then
    d.message = "Enter server IP or URL (current unreachable)"
  else
    d.message = "Enter server IP or URL"
  end if
  d.buttons = ["OK","Cancel"]
  d.text    = m.server  ' prefill current

  ' NOTE: do NOT set d.maxTextLength here — not present on some firmware
  ' If you ever want it and your device supports it, you can add it back.

  m.top.AppendChild(d)
  d.setFocus(true)
  d.ObserveField("buttonSelected", "onServerDialogButton")
  m.settingsDialog = d
end sub

sub onServerDialogButton()
  if m.settingsDialog = invalid then return
  sel = m.settingsDialog.buttonSelected
  if sel = invalid then return

  if sel = 0 then ' OK
    newText = m.settingsDialog.text
    m.top.removeChild(m.settingsDialog)
    m.settingsDialog = invalid
    m.settingsOpen = false

    newServer = normalizeServerUrl(newText)
    if newServer <> "" then
      m.server = newServer
      regSaveServer(m.server)
      ' reset state and retry from root
      m.stack = CreateObject("roArray", 0, true)
      m.authToken = ""
      if m.lbl <> invalid then m.lbl.text = "Loading..."
      browseAsync(invalid)
    else
      if m.lbl <> invalid then m.lbl.text = "Invalid server"
    end if
  else
    m.top.removeChild(m.settingsDialog)
    m.settingsDialog = invalid
    m.settingsOpen = false
  end if
end sub

function normalizeServerUrl(s as Dynamic) as String
  if s = invalid then return ""
  t = s
  if Type(t) <> "String" and Type(t) <> "roString" then
    t = FormatJson(t)
  end if
  t = ms_trim_str(t)
  if t = "" then return ""

  ' If it already has scheme, keep it (strip trailing slash)
  low = LCase(t)
  if Left(low, 7) = "http://" or Left(low, 8) = "https://" then
    if Right(t, 1) = "/" then t = Left(t, Len(t)-1)
    return t
  end if

  ' If it looks like ip:port, add http://
  if InStr(t, ":") > 0 then
    return "http://" + t
  end if

  ' Otherwise treat as bare IP/hostname, add default port 8000
  return "http://" + t + ":8000"
end function

function regLoadServer() as String
  sec = CreateObject("roRegistrySection", "chunkflix")
  if sec = invalid then return ""
  v = sec.Read("server")
  if v = invalid then return ""
  return v
end function

sub regSaveServer(v as String)
  sec = CreateObject("roRegistrySection", "chunkflix")
  if sec = invalid then return
  sec.Write("server", v)
  sec.Flush()
end sub

'========================
' Playback
'========================
sub playVideo(mediaId as Dynamic, title as Dynamic)
  baseUrl = m.server + "/api/stream?media_id=" + toQuery(mediaId)

  ' Also include token in the URL query (for range requests)
  if m.authToken <> "" then
    baseUrl = baseUrl + "&token=" + ms_urlEncode(m.authToken)
  end if

  v = CreateObject("roSGNode", "Video")
  if v.Lookup("enableUI") <> invalid then v.enableUI = false

  c = CreateObject("roSGNode", "ContentNode")
  c.url          = baseUrl
  c.title        = title
  c.streamFormat = "mp4"

  ' Send Authorization header too (best case)
  if m.authToken <> "" then
    hh = CreateObject("roAssociativeArray")
    hh.Authorization = "Bearer " + m.authToken
    c.HttpHeaders = hh
  end if

  ' No subtitleTracks to avoid PHY errors on some firmware

  v.content = c
  m.top.AppendChild(v)
  v.ObserveField("state", "onVideoState")
  v.ObserveField("errorCode", "onVideoError") ' small debug hook
  v.control = "play"
  m.video = v

  m.currentMediaKey = toQuery(mediaId)

  if m.keyCatcher <> invalid then
    m.keyCatcher.visible = true
    m.keyCatcher.setFocus(true)
  end if
  m.top.setFocus(true)
end sub

sub onVideoState()
  if m.video = invalid then return
  s = m.video.state

  if s = "finished" then
    nextItem = getNextAlpha(m.currentMediaKey)
    if nextItem <> invalid then
      m.video.control = "stop"
      m.video.visible = false
      if m.video.Lookup("close") <> invalid then m.video.close = true
      m.video = invalid

      playVideo(nextItem.id, nextItem.title)
      return
    end if
  end if

  if s = "finished" or s = "error" then
    m.video.control = "stop"
    m.video.visible = false
    if m.video.Lookup("close") <> invalid then m.video.close = true
    m.video = invalid
    if m.keyCatcher <> invalid then m.keyCatcher.visible = false
    if m.filesGrid <> invalid then m.filesGrid.setFocus(true)
    if m.lbl <> invalid then m.lbl.text = ""
  end if
end sub

sub onVideoError()
  if m.video = invalid then return
  ec = m.video.errorCode
  em = m.video.errorMsg
  if m.lbl <> invalid then
    m.lbl.text = "Video error " + toQuery(ec) + ": " + toQuery(em)
  end if
end sub

'========================
' Errors
'========================
sub showError(msg as Dynamic)
  s = ""
  if msg = invalid then
    s = "Error"
  else if Type(msg) = "String" or Type(msg) = "roString" then
    s = msg
  else
    s = FormatJson(msg)
  end if

  d = CreateObject("roSGNode", "Dialog")
  d.title = "Error"
  d.message = s
  d.buttons = ["OK"]
  m.top.AppendChild(d)
end sub

'========================
' Autoplay (alphabetical)
'========================
sub rebuildAlphaIndex()
  a = CreateObject("roArray", 0, true)
  if m.fileItems <> invalid then
    i = 0
    while i < m.fileItems.Count()
      it = m.fileItems[i]
      key = ""
      if it.title <> invalid then key = LCase(it.title)
      a.Push({ id: it.id, title: it.title, key: key })
      i = i + 1
    end while
  end if

  ' simple selection sort
  n = a.Count()
  i = 0
  while i < n - 1
    minIx = i
    j = i + 1
    while j < n
      if a[j].key < a[minIx].key then minIx = j
      j = j + 1
    end while
    if minIx <> i then
      tmp = a[i] : a[i] = a[minIx] : a[minIx] = tmp
    end if
    i = i + 1
  end while

  m.fileItemsAlpha = a
  m.alphaIndex = CreateObject("roAssociativeArray")
  idx = 0
  while idx < a.Count()
    m.alphaIndex[toQuery(a[idx].id)] = idx
    idx = idx + 1
  end while
end sub

function getNextAlpha(currKey as String) as Dynamic
  if currKey = invalid or currKey = "" then return invalid
  if m.alphaIndex = invalid then return invalid
  idx = m.alphaIndex.Lookup(currKey)
  if idx = invalid then return invalid
  ni = idx + 1
  if m.fileItemsAlpha <> invalid and ni < m.fileItemsAlpha.Count() then
    return m.fileItemsAlpha[ni]
  end if
  return invalid
end function

'========================
' Helpers for poster URLs
'========================
function ms_stripExt(s as Dynamic) as String
  if s = invalid then return ""
  t = s
  if Type(t) <> "String" and Type(t) <> "roString" then
    t = FormatJson(t)
  end if
  dot = 0
  i = 1
  while i <= Len(t)
    if Mid(t, i, 1) = "." then dot = i
    i = i + 1
  end while
  if dot > 0 then return Left(t, dot - 1)
  return t
end function

function ms_urlEncode(s as String) as String
  if s = invalid then return ""
  out = ""
  i = 1
  while i <= Len(s)
    ch = Mid(s, i, 1)
    code = Asc(ch)
    if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch = "-" or ch = "_" or ch = "." or ch = "~" then
      out = out + ch
    else
      out = out + "%" + ms_hex2(code)
    end if
    i = i + 1
  end while
  return out
end function

function ms_hex2(n as Integer) as String
  digits = "0123456789ABCDEF"
  hi = Int(n / 16)
  lo = n mod 16
  return Mid(digits, hi + 1, 1) + Mid(digits, lo + 1, 1)
end function

' safe trim (spaces, tabs, CR, LF) without using Trim()
function ms_trim_str(s as String) as String
  if s = invalid then return ""
  left = 1
  right = Len(s)
  ' leading
  while left <= right
    ch = Mid(s, left, 1)
    if ch <> " " and ch <> Chr(9) and ch <> Chr(10) and ch <> Chr(13) then exit while
    left = left + 1
  end while
  ' trailing
  while right >= left
    ch = Mid(s, right, 1)
    if ch <> " " and ch <> Chr(9) and ch <> Chr(10) and ch <> Chr(13) then exit while
    right = right - 1
  end while
  if right < left then return ""
  return Mid(s, left, right - left + 1)
end function

