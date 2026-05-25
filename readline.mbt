///|
struct Readline {
  tty : @tty.Tty
  config : Config
  state : State
  mut rendered_height : Int
  mut rendered_cursor_row : Int
}

///|
priv struct Rendered {
  frame : Frame
  cursor_row : Int
  cursor_col : Int
}

///|
pub async fn[T] with_readline(
  esc_timeout_ms? : Int,
  f : async (Readline) -> T,
) -> T {
  let config = Config::new(esc_timeout_ms?)
  let tty = @tty.Tty::open()
  let readline = {
    tty,
    config,
    state: State::new(),
    rendered_height: 0,
    rendered_cursor_row: 0,
  }
  try tty.with_raw_mode(() => f(readline)) catch {
    error => {
      tty.close()
      raise error
    }
  } noraise {
    value => {
      tty.close()
      value
    }
  }
}

///|
fn Readline::terminal_width(self : Readline) -> Int {
  let width = try self.tty.window_size() catch {
    _ => 80
  } noraise {
    size => size.cols
  }
  if width < 1 {
    1
  } else {
    width
  }
}

///|
fn Readline::layout(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Rendered {
  let width = self.terminal_width()
  let rows : Array[Line] = []
  if header is Some(header) {
    for row in header.layout(width~).lines {
      rows.push(row)
    }
  }
  let prompt = prompt.unwrap_or(Span::plain("> "))
  let before_cursor = Text::new([
    prompt,
    Span::plain(self.state.before_cursor()),
  ]).wrap(width~)
  let cursor_row = rows.length() + before_cursor.length() - 1
  let cursor_col = if before_cursor.length() == 0 {
    0
  } else {
    let col = before_cursor[before_cursor.length() - 1].display_width()
    if col >= width {
      width - 1
    } else {
      col
    }
  }
  let input = Text::new([prompt, Span::plain(self.state.text())])
  for row in input.wrap(width~) {
    rows.push(row)
  }
  if footer is Some(footer) {
    for row in footer.layout(width~).lines {
      rows.push(row)
    }
  }
  { frame: Frame(rows), cursor_row, cursor_col }
}

///|
async fn Readline::draw_line(self : Readline, line : Line?) -> Unit {
  self.tty.write_string("\r")
  self.tty.erase_line_all()
  if line is Some(line) {
    line.write_to(self.tty)
  }
}

///|
async fn Readline::redraw(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Unit {
  if self.rendered_height > 0 && self.rendered_cursor_row > 0 {
    self.tty.cursor_up(self.rendered_cursor_row)
  }
  let rendered = self.layout(header?, prompt?, footer?)
  let next_height = rendered.frame.lines.length()
  let draw_height = Int::max(self.rendered_height, next_height)
  for row in 0..<draw_height {
    if row > 0 {
      self.tty.write_string("\r\n")
    }
    self.draw_line(rendered.frame.lines.get(row))
  }
  if draw_height > 0 {
    let rows_up = draw_height - 1 - rendered.cursor_row
    if rows_up > 0 {
      self.tty.cursor_up(rows_up)
    }
    self.tty.write_string("\r")
    if rendered.cursor_col > 0 {
      self.tty.cursor_forward(rendered.cursor_col)
    }
  }
  self.rendered_height = draw_height
  self.rendered_cursor_row = rendered.cursor_row
}

///|
async fn Readline::commit_live_frame(self : Readline) -> Unit {
  if self.rendered_height > 0 {
    for _ in self.rendered_cursor_row..<self.rendered_height {
      self.tty.write_string("\r\n")
    }
    self.rendered_height = 0
    self.rendered_cursor_row = 0
  }
}

///|
pub async fn Readline::read_line(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Event {
  self.state.reset()
  self.redraw(header?, prompt?, footer?)
  for ;; {
    let event = self.tty.read_event(esc_timeout_ms=self.config.esc_timeout_ms) catch {
      @async/io.ReaderClosed => {
        self.commit_live_frame()
        break Eof
      }
      error => raise error
    }
    match event {
      @tty.Input(@tty/input.Key(key)) =>
        match key.code {
          @tty/input.Char('c') if key.modifiers.ctrl() => {
            self.commit_live_frame()
            break Interrupted
          }
          @tty/input.Char('d') if key.modifiers.ctrl() =>
            if self.state.text().length() == 0 {
              self.commit_live_frame()
              break Eof
            } else {
              self.state.delete_after()
              self.redraw(header?, prompt?, footer?)
            }
          @tty/input.Enter => {
            let text = self.state.text()
            self.commit_live_frame()
            break Line(text)
          }
          @tty/input.Backspace => {
            self.state.delete_before()
            self.redraw(header?, prompt?, footer?)
          }
          @tty/input.Delete => {
            self.state.delete_after()
            self.redraw(header?, prompt?, footer?)
          }
          @tty/input.Left => {
            self.state.move_left()
            self.redraw(header?, prompt?, footer?)
          }
          @tty/input.Right => {
            self.state.move_right()
            self.redraw(header?, prompt?, footer?)
          }
          @tty/input.Home => {
            self.state.move_home()
            self.redraw(header?, prompt?, footer?)
          }
          @tty/input.End => {
            self.state.move_end()
            self.redraw(header?, prompt?, footer?)
          }
          _ =>
            if key.text is Some(text) {
              self.state.insert_text(text)
              self.redraw(header?, prompt?, footer?)
            }
        }
      @tty.Input(@tty/input.Paste(text)) => {
        self.state.insert_text(text)
        self.redraw(header?, prompt?, footer?)
      }
      @tty.Input(@tty/input.Unknown(_)) => ()
      @tty.Resize(_) => self.redraw(header?, prompt?, footer?)
    }
  }
}

///|
pub async fn Readline::write_doc(self : Readline, doc : Doc) -> Unit {
  self.commit_live_frame()
  doc.layout(width=self.terminal_width()).write_to(self.tty)
  self.tty.write_string("\r\n")
}
