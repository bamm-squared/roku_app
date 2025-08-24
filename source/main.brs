sub Main()
  s = CreateObject("roSGScreen")
  p = CreateObject("roMessagePort")
  s.SetMessagePort(p)
  sc = s.CreateScene("MainScene")
  s.Show()
  while true
    msg = wait(0, p)
    if type(msg) = "roSGScreenEvent" then
      if msg.IsScreenClosed() then return
    else if type(msg) = "roSGNodeEvent" then
      if msg.GetNode() = s and msg.GetField() = "exit" then
        if s.exit = true then return
      end if
    end if
  end while
end sub
