///|
fn Line::plain_text(self : Line) -> String {
  self.spans.map(span => span.text).join("")
}

///|
fn Text::wrapped_text(self : Text, width~ : Int) -> String {
  self.wrap(width~).map(line => line.plain_text()).join("|")
}

///|
fn Doc::layout_text(self : Doc, width~ : Int) -> String {
  self.layout(width~).lines.map(line => line.plain_text()).join("|")
}

///|
test "text wraps by display width" {
  inspect(Text::plain("abcdef").wrapped_text(width=3), content="abc|def")
  inspect(
    Text::plain("你好世界").wrapped_text(width=4),
    content="你好|世界",
  )
}

///|
test "text newline forces row break" {
  inspect(Text::plain("a\nb").wrapped_text(width=10), content="a|b")
}

///|
test "doc layout preserves logical text boundaries" {
  inspect(
    Doc([Text::plain("abcd"), Text::plain("ef")]).layout_text(width=2),
    content="ab|cd|ef",
  )
}
