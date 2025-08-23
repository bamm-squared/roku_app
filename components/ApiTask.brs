' ApiTask.brs — async HTTP task (no component Lookup calls)

sub init()
  m.top.functionName = "run"
end sub

function run() as void
  url     = m.top.url
  method  = LCase(m.top.method)
  if method = invalid or method = "" then method = "get"
  headers = m.top.headers
  body    = m.top.body
  if body = invalid then body = ""

  ' Default response shell
  res = {
    ok: false,
    status: -1,
    json: invalid,
    text: invalid,
    headers: invalid
  }

  if url = invalid or url = "" then
    m.top.response = res
    return
  end if

  x = CreateObject("roUrlTransfer")
  x.SetUrl(url)

  ' HTTPS certs (ok to set even if not https on most builds; guard anyway)
  if Left(LCase(url), 5) = "https" then
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
  end if

  ' Headers we actually use
  if headers <> invalid then
    if headers.Authorization <> invalid then
      x.AddHeader("Authorization", headers.Authorization)
    end if
  end if

  ' Ensure JSON Content-Type for POST
  if method = "post" then
    x.AddHeader("Content-Type", "application/json")
  end if

  ' Async request (read body from event; reliable across firmware)
  port = CreateObject("roMessagePort")
  x.SetMessagePort(port)

  if method = "post" then
    x.AsyncPostFromString(body)
  else
    x.AsyncGetToString()
  end if

  ' Wait for response event (single-shot)
  evt = wait(0, port)

  code = -1
  txt  = invalid
  hdrs = invalid

  if evt <> invalid
    ' roUrlEvent API
    code = evt.GetResponseCode()
    txt  = evt.GetString()
    ' headers may not be present on all builds
    if GetInterface(evt, "ifAssociativeArray") <> invalid and evt.Lookup("GetResponseHeaders") <> invalid then
      hdrs = evt.GetResponseHeaders()
    end if
  end if

  j = invalid
  if txt <> invalid and txt <> "" then
    j = ParseJson(txt)
  end if

  res.ok      = (code = 200 or code = 201)
  res.status  = code
  res.text    = txt
  res.json    = j
  res.headers = hdrs

  m.top.response = res
end function
