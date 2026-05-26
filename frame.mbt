///|
/// A renderable document made of logical text blocks.
///
/// `Doc` is used for headers, footers, and output written through
/// `Readline::write_doc`. Each `Text` block is wrapped independently when the
/// document is laid out for the current terminal width.
struct Doc {
  texts : Array[Text]
}

///|
/// Build a document from a sequence of text blocks.
pub fn Doc::Doc(texts : Array[Text]) -> Doc {
  { texts, }
}

///|
/// Build a document containing one unstyled text block.
pub fn Doc::plain(text : String) -> Doc {
  Doc([Text::plain(text)])
}

///|
/// A logical text block made of styled spans.
///
/// Text wraps by terminal display width and treats newline characters as forced
/// row breaks.
struct Text {
  spans : Array[Span]
}

///|
/// Build a text block from a sequence of styled spans.
pub fn Text::Text(spans : Array[Span]) -> Text {
  { spans, }
}

///|
/// Build a text block containing one unstyled span.
pub fn Text::plain(text : String) -> Text {
  Text([Span::plain(text)])
}

///|
/// A string fragment with an associated terminal style.
struct Span {
  text : String
  style : Style
}

///|
/// Build a styled span.
///
/// If `style` is omitted, the span uses `Style::default`.
pub fn Span::Span(text : String, style? : Style = Style::default()) -> Span {
  { text, style }
}

///|
/// Build an unstyled span.
pub fn Span::plain(text : String) -> Span {
  Span(text)
}

///|
/// Terminal styling applied while a span is written.
///
/// A style can set foreground color, background color, and underline. Terminal
/// styling is reset after each span is emitted.
struct Style {
  foreground : @tty/color.Color
  background : @tty/color.Color
  underline : Bool
} derive(Eq)

///|
/// Return the default terminal style.
pub fn Style::default() -> Style {
  { foreground: Default, background: Default, underline: false }
}

///|
/// Build a terminal style.
///
/// Omitted color arguments use the terminal default, and `underline` defaults
/// to `false`.
pub fn Style::new(
  foreground? : @tty/color.Color = Default,
  background? : @tty/color.Color = Default,
  underline? : Bool = false,
) -> Style {
  { foreground, background, underline }
}

///|
async fn Style::apply(self : Style, tty : @tty.Tty) -> Unit {
  if self.foreground != Default {
    tty.set_foreground(self.foreground)
  }
  if self.background != Default {
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
fn Span::same_as(self : Span, other : Span) -> Bool {
  self.text == other.text && self.style == other.style
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
fn Line::same_as(self : Line, other : Line) -> Bool {
  if self.spans.length() != other.spans.length() {
    return false
  }
  for index, span in self.spans {
    if other.spans.get(index) is Some(other_span) {
      if !span.same_as(other_span) {
        return false
      }
    } else {
      return false
    }
  }
  true
}

///|
fn Line::same_optional(left : Line?, right : Line?) -> Bool {
  if left is Some(left) {
    if right is Some(right) {
      left.same_as(right)
    } else {
      false
    }
  } else {
    right is None
  }
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
        spans.push(Span(text, style=span.style))
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
