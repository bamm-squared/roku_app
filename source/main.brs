sub Main()
  s = CreateObject("roSGScreen")
  p = CreateObject("roMessagePort")
  s.SetMessagePort(p)
  sc = s.CreateScene("MainScene")
  s.Show()
  while true
    msg = wait(0, p)
    if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
  end while
end sub
