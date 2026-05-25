///|
struct Frame {
  lines : Array[Line]
}

///|
struct Line {
  spans : Array[Span]
}

///|
struct Span {
  text : String
  style : Style
}

///|
struct Style {
  foreground : @tty/color.Color
  background : @tty/color.Color
  underline : Bool
}
