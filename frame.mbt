///|
struct Doc {
  texts : Array[Text]
}

///|
pub fn Doc::Doc(texts : Array[Text]) -> Doc {
  { texts, }
}

///|
pub fn Doc::plain(text : String) -> Doc {
  Doc([Text::plain(text)])
}

///|
struct Text {
  spans : Array[Span]
}

///|
pub fn Text::Text(spans : Array[Span]) -> Text {
  { spans, }
}

///|
pub fn Text::plain(text : String) -> Text {
  Text([Span::plain(text)])
}

///|
struct Span {
  text : String
  style : Style
}

///|
pub fn Span::Span(text : String, style? : Style = Style::default()) -> Span {
  { text, style }
}

///|
pub fn Span::plain(text : String) -> Span {
  Span::Span(text)
}

///|
struct Style {
  foreground : @tty/color.Color
  background : @tty/color.Color
  underline : Bool
} derive(Eq)

///|
pub fn Style::default() -> Style {
  {
    foreground: @tty/color.Default,
    background: @tty/color.Default,
    underline: false,
  }
}

///|
pub fn Style::new(
  foreground? : @tty/color.Color = @tty/color.Default,
  background? : @tty/color.Color = @tty/color.Default,
  underline? : Bool = false,
) -> Style {
  { foreground, background, underline }
}

///|
async fn Style::apply(self : Style, tty : @tty.Tty) -> Unit {
  if self.foreground != @tty/color.Default {
    tty.set_foreground(self.foreground)
  }
  if self.background != @tty/color.Default {
    tty.set_background(self.background)
  }
  if self.underline {
    tty.underline()
  }
}

///|
fn Span::display_width(self : Span) -> Int {
  @unicodewidth.str_width(self.text)
}

///|
async fn Span::write_to(self : Span, tty : @tty.Tty) -> Unit {
  self.style.apply(tty)
  tty.write_string(self.text)
  tty.reset_style()
}

///|
priv struct Frame {
  lines : Array[Line]
}

///|
fn Frame::Frame(lines : Array[Line]) -> Frame {
  { lines, }
}

///|
async fn Frame::write_to(self : Frame, tty : @tty.Tty) -> Unit {
  for index, line in self.lines {
    if index > 0 {
      tty.write_string("\r\n")
    }
    line.write_to(tty)
  }
}

///|
priv struct Line {
  spans : Array[Span]
}

///|
fn Line::new(spans : Array[Span]) -> Line {
  { spans, }
}

///|
fn Line::display_width(self : Line) -> Int {
  let mut width = 0
  for span in self.spans {
    width += span.display_width()
  }
  width
}

///|
fn Text::wrap(self : Text, width~ : Int) -> Array[Line] {
  let rows : Array[Line] = []
  let mut spans : Array[Span] = []
  let mut used = 0
  let width = if width < 1 { 1 } else { width }
  for span in self.spans {
    for grapheme in @grapheme.grapheme_iter(span.text) {
      let text = grapheme.to_owned()
      if text == "\n" {
        rows.push(Line::new(spans))
        spans = []
        used = 0
      } else {
        let next = @unicodewidth.str_width(text)
        if used > 0 && used + next > width {
          rows.push(Line::new(spans))
          spans = []
          used = 0
        }
        spans.push(Span::Span(text, style=span.style))
        used += next
      }
    }
  }
  rows.push(Line::new(spans))
  rows
}

///|
async fn Line::write_to(self : Line, tty : @tty.Tty) -> Unit {
  for span in self.spans {
    span.write_to(tty)
  }
}

///|
fn Doc::layout(self : Doc, width~ : Int) -> Frame {
  let rows : Array[Line] = []
  for text in self.texts {
    for row in text.wrap(width~) {
      rows.push(row)
    }
  }
  Frame(rows)
}
