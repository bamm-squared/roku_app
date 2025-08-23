sub init()
  m.img   = m.top.findNode("img")
  m.lbl   = m.top.findNode("lbl")
  m.focus = m.top.findNode("focus")
end sub

sub onItemContent()
  c = m.top.itemContent
  title = "-"
  if c <> invalid and c.title <> invalid then title = c.title

  ' Caption: base name (no extension)
  base = tt_stripExt(title)
  m.lbl.text = base

  ' Choose the best image URL provided by MainScene
  urlCand = ""
  if c <> invalid then
    if c.hdPosterUrl <> invalid and c.hdPosterUrl <> "" then
      urlCand = c.hdPosterUrl
    else if c.posterUrl <> invalid and c.posterUrl <> "" then
      urlCand = c.posterUrl
    else if c.hdimg <> invalid and c.hdimg <> "" then
      urlCand = c.hdimg
    else if c.url <> invalid and c.url <> "" then
      ' absolute fallback if you ever set .url
      urlCand = c.url
    end if
  end if

  if urlCand <> "" then
    m.img.uri = urlCand
  else
    ' packaged fallback (optional, if you want local posters loaded on the roku)
    m.img.uri = "pkg:/images/" + base + ".png"
  end if
end sub

sub onFocusedChanged()
  m.focus.visible = (m.top.focused = true)
end sub

' local helper (separate name from MainScene’s to avoid collisions)
function tt_stripExt(s as Dynamic) as String
  if s = invalid then return ""
  t = s
  if Type(t) <> "String" and Type(t) <> "roString" then t = FormatJson(t)
  dot = 0 : i = 1
  while i <= Len(t)
    if Mid(t, i, 1) = "." then dot = i
    i = i + 1
  end while
  if dot > 0 then return Left(t, dot - 1)
  return t
end function
