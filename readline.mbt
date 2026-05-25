///|
const DefaultTerminalRows : Int = 24

///|
const DefaultTerminalCols : Int = 80

///|
priv struct TerminalSize {
  rows : Int
  cols : Int
}

///|
fn TerminalSize::bottom_composer_top(self : TerminalSize, height : Int) -> Int {
  let top = self.rows - height + 1
  if top < 1 {
    1
  } else {
    top
  }
}

///|
fn TerminalSize::visible_frame_height(
  self : TerminalSize,
  frame : Frame,
) -> Int {
  let height = frame.lines.length()
  if height < 1 {
    1
  } else if height > self.rows {
    self.rows
  } else {
    height
  }
}

///|
struct Readline {
  tty : @tty.Tty
  config : Config
  state : State
  history : History
  // 1-based terminal row where the current composer starts. The composer is the
  // redrawable input area: header, prompt plus editable text, and footer.
  //
  // `0` means the composer has not been drawn yet; the first redraw anchors it
  // at the terminal cursor instead of forcing it to the bottom.
  mut composer_top : Int
  // Height of the composer from the last redraw. Once the composer exists,
  // output writes reserve these rows by setting the terminal scroll region
  // above `composer_top`.
  mut composer_height : Int
  // Cursor position inside the composer from the last redraw.
  // `write_doc` temporarily moves the terminal cursor into the output region,
  // then uses these fields to restore the input cursor without repainting the
  // composer.
  mut composer_cursor_row : Int
  mut composer_cursor_col : Int
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
    history: History::new(),
    composer_top: 0,
    composer_height: 0,
    composer_cursor_row: 0,
    composer_cursor_col: 0,
  }
  try tty.with_raw_mode(() => f(readline)) catch {
    error => {
      readline.leave()
      tty.close()
      raise error
    }
  } noraise {
    value => {
      readline.leave()
      tty.close()
      value
    }
  }
}

///|
fn Readline::terminal_size(self : Readline) -> TerminalSize {
  let size = try self.tty.window_size() catch {
    _ => { rows: DefaultTerminalRows, cols: DefaultTerminalCols }
  } noraise {
    size => { rows: size.rows, cols: size.cols }
  }
  {
    rows: if size.rows < 1 {
      DefaultTerminalRows
    } else {
      size.rows
    },
    cols: if size.cols < 1 {
      DefaultTerminalCols
    } else {
      size.cols
    },
  }
}

///|
fn TerminalSize::normalize_composer_top(
  self : TerminalSize,
  height~ : Int,
  top~ : Int,
) -> Int {
  let bottom_top = self.bottom_composer_top(height)
  if top < 1 {
    1
  } else if top > bottom_top {
    bottom_top
  } else {
    top
  }
}

///|
async fn Readline::initial_composer_top(
  self : Readline,
  size~ : TerminalSize,
  height~ : Int,
) -> Int {
  match self.tty.query_cursor_position(timeout_ms=self.config.esc_timeout_ms) {
    Some(position) => size.normalize_composer_top(height~, top=position.row)
    None => size.bottom_composer_top(height)
  }
}

///|
fn Readline::next_composer_top(
  self : Readline,
  size~ : TerminalSize,
  height~ : Int,
) -> Int {
  let top = size.normalize_composer_top(height~, top=self.composer_top)
  if self.composer_height == 0 {
    top
  } else if height > self.composer_height {
    let bottom = top + height - 1
    if bottom <= size.rows {
      top
    } else {
      size.bottom_composer_top(height)
    }
  } else {
    top
  }
}

///|
fn Readline::layout(
  self : Readline,
  size~ : TerminalSize,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Rendered {
  let width = size.cols
  let rows : Array[Line] = []
  if header is Some(header) {
    for row in header.layout(width~).lines {
      rows.push(row)
    }
  }
  let prompt = prompt.unwrap_or(Span::plain("> "))
  let before_cursor = Text([prompt, Span::plain(self.state.before_cursor())]).wrap(
    width~,
  )
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
  let input = Text([prompt, Span::plain(self.state.text())])
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
fn Readline::input_frame(
  self : Readline,
  size~ : TerminalSize,
  prompt? : Span,
) -> Frame {
  let prompt = prompt.unwrap_or(Span::plain("> "))
  Frame(Text([prompt, Span::plain(self.state.text())]).wrap(width=size.cols))
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
async fn Readline::draw_line_at(
  self : Readline,
  row : Int,
  line : Line?,
) -> Unit {
  self.tty.set_cursor_position(row, 1)
  self.draw_line(line)
}

///|
async fn Readline::scroll_history_up_for_growth(
  self : Readline,
  old_top~ : Int,
  new_top~ : Int,
) -> Unit {
  let rows = old_top - new_top
  let history_bottom = old_top - 1
  if rows > 0 && history_bottom >= 1 {
    self.tty.set_top_bottom_margins(1, history_bottom)
    self.tty.set_cursor_position(history_bottom, 1)
    for _ in 0..<rows {
      self.tty.write_string("\r\n")
    }
    self.tty.reset_top_bottom_margins()
  }
}

///|
async fn Readline::place_composer_cursor(self : Readline) -> Unit {
  if self.composer_top > 0 && self.composer_height > 0 {
    self.tty.show_cursor()
    self.tty.set_cursor_position(
      self.composer_top + self.composer_cursor_row,
      1 + self.composer_cursor_col,
    )
  }
}

///|
async fn Readline::redraw(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Unit {
  let size = self.terminal_size()
  let rendered = self.layout(size~, header?, prompt?, footer?)
  let old_height = self.composer_height
  let next_height = size.visible_frame_height(rendered.frame)
  let old_top = if self.composer_top > 0 { self.composer_top } else { 0 }
  let new_top = if old_height == 0 {
    self.initial_composer_top(size~, height=next_height)
  } else {
    self.next_composer_top(size~, height=next_height)
  }
  if old_height > 0 && new_top < old_top {
    self.scroll_history_up_for_growth(old_top~, new_top~)
  }
  // Redraw moves through multiple rows and clears/reprints each one. Hiding the
  // cursor during that sweep avoids a visible cursor jumping through history and
  // composer rows.
  self.tty.hide_cursor()
  let draw_top = if old_height > 0 && old_top > 0 && old_top < new_top {
    old_top
  } else {
    new_top
  }
  for row in draw_top..<=size.rows {
    let frame_row = row - new_top
    if frame_row >= 0 && frame_row < next_height {
      self.draw_line_at(row, rendered.frame.lines.get(frame_row))
    } else {
      self.draw_line_at(row, None)
    }
  }
  let cursor_row = if rendered.cursor_row < 0 {
    0
  } else if rendered.cursor_row >= next_height {
    next_height - 1
  } else {
    rendered.cursor_row
  }
  self.composer_top = new_top
  self.composer_height = next_height
  self.composer_cursor_row = cursor_row
  self.composer_cursor_col = rendered.cursor_col
  self.place_composer_cursor()
}

///|
async fn Readline::shift_composer_down_for_output(
  self : Readline,
  size~ : TerminalSize,
  lines~ : Int,
) -> Int {
  let old_top = self.composer_top
  let bottom = self.composer_top + self.composer_height - 1
  let space = size.rows - bottom
  let available = if space < 0 { 0 } else { space }
  let shift = if lines < available { lines } else { available }
  if shift > 0 {
    self.tty.set_top_bottom_margins(self.composer_top, size.rows)
    self.tty.set_cursor_position(self.composer_top, 1)
    for _ in 0..<shift {
      self.tty.reverse_index()
    }
    self.tty.reset_top_bottom_margins()
    self.composer_top += shift
  }
  old_top
}

///|
async fn Readline::write_output_frame(
  self : Readline,
  frame : Frame,
  size~ : TerminalSize,
) -> Unit {
  if self.composer_height <= 0 || self.composer_top <= 0 {
    frame.write_to(self.tty)
    self.tty.write_string("\r\n")
  } else {
    let old_top = self.shift_composer_down_for_output(
      size~,
      lines=frame.lines.length(),
    )
    let output_bottom = self.composer_top - 1
    if output_bottom < 1 {
      self.place_composer_cursor()
      return
    }
    self.tty.set_top_bottom_margins(1, output_bottom)
    let cursor_row = if old_top > 1 { old_top - 1 } else { 1 }
    self.tty.set_cursor_position(cursor_row, 1)
    for line in frame.lines {
      self.tty.write_string("\r\n")
      self.draw_line(Some(line))
    }
    self.tty.reset_top_bottom_margins()
    self.place_composer_cursor()
  }
}

///|
async fn Readline::commit_input(
  self : Readline,
  size~ : TerminalSize,
  prompt? : Span,
) -> Unit {
  self.write_output_frame(self.input_frame(size~, prompt?), size~)
}

///|
async fn Readline::submit_current_line(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> String {
  let text = self.state.text()
  let size = self.terminal_size()
  self.commit_input(size~, prompt?)
  self.history.push(text)
  self.state.reset()
  self.redraw(header?, prompt?, footer?)
  text
}

///|
async fn Readline::recall_previous_history(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Unit {
  if self.history.previous(self.state.text()) is Some(text) {
    self.state.replace(text)
    self.redraw(header?, prompt?, footer?)
  }
}

///|
async fn Readline::recall_next_history(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Unit {
  if self.history.next() is Some(text) {
    self.state.replace(text)
    self.redraw(header?, prompt?, footer?)
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
  self.history.reset_navigation(draft="")
  self.redraw(header?, prompt?, footer?)
  for ;; {
    let event = self.tty.read_event(esc_timeout_ms=self.config.esc_timeout_ms) catch {
      @async/io.ReaderClosed => {
        self.state.reset()
        self.history.reset_navigation(draft="")
        self.redraw(header?, prompt?, footer?)
        break Eof
      }
      error => raise error
    }
    match event {
      Input(Key(key)) =>
        match key.code {
          Char('a') if key.modifiers.ctrl() => {
            self.state.move_home()
            self.redraw(header?, prompt?, footer?)
          }
          Char('b') if key.modifiers.ctrl() => {
            self.state.move_left()
            self.redraw(header?, prompt?, footer?)
          }
          Char('c') if key.modifiers.ctrl() => {
            self.state.reset()
            self.history.reset_navigation(draft="")
            self.redraw(header?, prompt?, footer?)
            break Interrupted
          }
          Char('d') if key.modifiers.ctrl() =>
            if self.state.text().length() == 0 {
              break Eof
            } else {
              self.state.delete_after()
              self.redraw(header?, prompt?, footer?)
            }
          Char('e') if key.modifiers.ctrl() => {
            self.state.move_end()
            self.redraw(header?, prompt?, footer?)
          }
          Char('f') if key.modifiers.ctrl() => {
            self.state.move_right()
            self.redraw(header?, prompt?, footer?)
          }
          Char('j') if key.modifiers.ctrl() => {
            let text = self.submit_current_line(header?, prompt?, footer?)
            break Line(text)
          }
          Char('k') if key.modifiers.ctrl() => {
            self.state.kill_after()
            self.redraw(header?, prompt?, footer?)
          }
          Char('n') if key.modifiers.ctrl() =>
            self.recall_next_history(header?, prompt?, footer?)
          Char('p') if key.modifiers.ctrl() =>
            self.recall_previous_history(header?, prompt?, footer?)
          Char('u') if key.modifiers.ctrl() => {
            self.state.kill_before()
            self.redraw(header?, prompt?, footer?)
          }
          Enter => {
            let text = self.submit_current_line(header?, prompt?, footer?)
            break Line(text)
          }
          Backspace => {
            self.state.delete_before()
            self.redraw(header?, prompt?, footer?)
          }
          Delete => {
            self.state.delete_after()
            self.redraw(header?, prompt?, footer?)
          }
          Left => {
            self.state.move_left()
            self.redraw(header?, prompt?, footer?)
          }
          Right => {
            self.state.move_right()
            self.redraw(header?, prompt?, footer?)
          }
          Home => {
            self.state.move_home()
            self.redraw(header?, prompt?, footer?)
          }
          End => {
            self.state.move_end()
            self.redraw(header?, prompt?, footer?)
          }
          Up => self.recall_previous_history(header?, prompt?, footer?)
          Down => self.recall_next_history(header?, prompt?, footer?)
          _ =>
            if key.text is Some(text) {
              self.state.insert_text(text)
              self.redraw(header?, prompt?, footer?)
            }
        }
      Input(Paste(text)) => {
        self.state.insert_text(text)
        self.redraw(header?, prompt?, footer?)
      }
      Input(Unknown(_)) => ()
      Resize(_) => self.redraw(header?, prompt?, footer?)
    }
  }
}

///|
pub async fn Readline::write_doc(self : Readline, doc : Doc) -> Unit {
  let size = self.terminal_size()
  self.write_output_frame(doc.layout(width=size.cols), size~)
}

///|
async fn Readline::leave(self : Readline) -> Unit {
  self.tty.reset_top_bottom_margins()
  self.tty.reset_style()
  self.tty.show_cursor()
  if self.composer_height > 0 {
    let size = self.terminal_size()
    // Leave the terminal cursor just after the visible composer, not at the
    // absolute bottom of the screen. The composer remains on screen when
    // `read_line` returns; writing the next shell prompt on top of it would
    // overwrite live UI rows. Moving to the composer's last row and emitting one
    // CRLF places the prompt below the composer, scrolling only when the
    // composer already reaches the terminal bottom.
    let composer_bottom = self.composer_top + self.composer_height - 1
    let row = if composer_bottom < 1 {
      1
    } else if composer_bottom > size.rows {
      size.rows
    } else {
      composer_bottom
    }
    self.tty.set_cursor_position(row, 1)
    self.tty.write_string("\r\n")
    self.composer_top = 0
    self.composer_height = 0
    self.composer_cursor_row = 0
    self.composer_cursor_col = 0
  }
}
