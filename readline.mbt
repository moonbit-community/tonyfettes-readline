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
/// An interactive terminal line editor.
///
/// `Readline` owns the terminal session state, input history, and live composer
/// rows. Values are created by `with_readline` and are intended to be used only
/// while that callback is running.
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
  // Last frame drawn into the live composer rows. Redraw uses this to diff the
  // new layout against the current terminal contents and skip unchanged rows.
  mut composer_frame : Frame?
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
/// Open a readline session, switch the terminal into raw mode, and run `f`.
///
/// The terminal is restored before this function returns or re-raises an error.
/// `esc_timeout_ms` controls how long the underlying terminal reader waits to
/// disambiguate escape sequences such as Alt-key input; it defaults to 50 ms.
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
    composer_frame: None,
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
fn Frame::line_at_terminal_row(
  self : Frame,
  row~ : Int,
  top~ : Int,
  height~ : Int,
) -> Line? {
  let index = row - top
  if index >= 0 && index < height {
    self.lines.get(index)
  } else {
    None
  }
}

///|
// Diff two composer frames after they have already been laid out to terminal
// rows. The diff unit is a physical terminal row, not a span or grapheme:
//
//   old_frame at old_top      new_frame at new_top
//   row 5: "header"           row 5: "header"       unchanged, skip
//   row 6: "> abc"            row 6: "> abcd"       changed, redraw row 6
//   row 7: "footer"           row 7: "footer"       unchanged, skip
//
// The scan range is the union of the old and new composer footprints. Rows
// that existed only in the old footprint map to `None` in the new frame, so
// drawing them clears stale terminal content. On resize, terminal-owned reflow
// can make old physical rows untrustworthy; callers pass `old_frame=None`, and
// this function redraws the whole affected region instead of comparing against
// stale model data.
async fn Readline::draw_frame_diff(
  self : Readline,
  size~ : TerminalSize,
  old_top~ : Int,
  old_height~ : Int,
  old_frame? : Frame,
  new_top~ : Int,
  new_height~ : Int,
  new_frame~ : Frame,
) -> Unit {
  let has_old_region = old_top > 0 && old_height > 0
  let old_content_unknown = has_old_region && old_frame is None
  let old_bottom = if has_old_region {
    old_top + old_height - 1
  } else {
    new_top - 1
  }
  let new_bottom = new_top + new_height - 1
  let draw_top = if has_old_region && old_top < new_top {
    old_top
  } else {
    new_top
  }
  let draw_bottom = if old_bottom > new_bottom {
    old_bottom
  } else {
    new_bottom
  }
  let draw_bottom = if old_content_unknown { size.rows } else { draw_bottom }
  let draw_top = if draw_top < 1 { 1 } else { draw_top }
  let draw_bottom = if draw_bottom > size.rows {
    size.rows
  } else {
    draw_bottom
  }
  if draw_top <= draw_bottom {
    for row in draw_top..<=draw_bottom {
      let old_line = if old_frame is Some(frame) {
        frame.line_at_terminal_row(row~, top=old_top, height=old_height)
      } else {
        None
      }
      let new_line = new_frame.line_at_terminal_row(
        row~,
        top=new_top,
        height=new_height,
      )
      if old_content_unknown || !Line::same_optional(old_line, new_line) {
        self.draw_line_at(row, new_line)
      }
    }
  }
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
async fn Readline::redraw_input_area(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
  force_full? : Bool = false,
) -> Unit {
  let size = self.terminal_size()
  let rendered = self.layout(size~, header?, prompt?, footer?)
  let old_height = self.composer_height
  let old_frame = if force_full { None } else { self.composer_frame }
  let next_height = size.visible_frame_height(rendered.frame)
  let growth = if next_height > old_height {
    next_height - old_height
  } else {
    0
  }
  let old_top = if self.composer_top > 0 { self.composer_top } else { 0 }
  let planned_top = if old_height == 0 {
    self.initial_composer_top(size~, height=next_height)
  } else {
    self.next_composer_top(size~, height=next_height)
  }
  let new_top = if force_full && old_height > 0 && growth > 0 {
    size.normalize_composer_top(height=next_height, top=planned_top - growth)
  } else {
    planned_top
  }
  if !force_full && old_height > 0 && new_top < old_top {
    self.scroll_history_up_for_growth(old_top~, new_top~)
  }
  let diff_old_top = if force_full && old_height > 0 && growth > 0 {
    let top = old_top - growth
    if top < 1 {
      1
    } else {
      top
    }
  } else {
    old_top
  }
  let diff_old_height = old_height + (old_top - diff_old_top)
  // Frame diffing can still move through several terminal rows when the
  // composer wraps, shrinks, or changes header/footer rows. Hiding the cursor
  // during that sweep avoids a visible cursor jumping through intermediate
  // positions.
  self.tty.hide_cursor()
  self.draw_frame_diff(
    size~,
    old_top=diff_old_top,
    old_height=diff_old_height,
    old_frame?,
    new_top~,
    new_height=next_height,
    new_frame=rendered.frame,
  )
  let cursor_row = if rendered.cursor_row < 0 {
    0
  } else if rendered.cursor_row >= next_height {
    next_height - 1
  } else {
    rendered.cursor_row
  }
  self.composer_top = new_top
  self.composer_height = next_height
  self.composer_frame = Some(rendered.frame)
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
async fn Readline::accept_current_line(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
  echo_input? : Bool = true,
) -> String {
  let text = self.state.text()
  let size = self.terminal_size()
  if echo_input {
    self.commit_input(size~, prompt?)
  }
  self.history.push(text)
  self.state.reset()
  self.redraw_input_area(header?, prompt?, footer?)
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
    self.redraw_input_area(header?, prompt?, footer?)
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
    self.redraw_input_area(header?, prompt?, footer?)
  }
}

///|
/// Return the current editable text without accepting or clearing it.
pub fn Readline::text(self : Readline) -> String {
  self.state.text()
}

///|
/// Accept the current editable line and reset the editor state.
///
/// The accepted line is added to readline's input recall history for Up/Down
/// navigation. `accept` does not write the submitted prompt line into the
/// output transcript; callers that own a higher-level transcript can render it
/// themselves.
pub async fn Readline::accept(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> String {
  self.accept_current_line(header?, prompt?, footer?, echo_input=false)
}

///|
/// Read until an event is available for the caller to interpret.
///
/// `header` is rendered above the editable input area, `prompt` is rendered
/// before the editable text, and `footer` is rendered below it. The editor
/// consumes common line-editing keys, history navigation, paste input, and
/// terminal resize redraws. Keys that readline does not consume are returned so
/// application code can decide what they mean. `None` means the input stream
/// ended, or the user pressed Ctrl+D on an empty line.
pub async fn Readline::read_event(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Event? {
  self.redraw_input_area(header?, prompt?, footer?)
  for ;; {
    let event = self.tty.read_event(esc_timeout_ms=self.config.esc_timeout_ms) catch {
      @async/io.ReaderClosed => {
        self.state.reset()
        self.history.reset_navigation(draft="")
        self.redraw_input_area(header?, prompt?, footer?)
        break None
      }
      error => raise error
    }
    match event {
      Input(Key(key)) =>
        match key.code {
          Char('a') if key.modifiers.ctrl() => {
            self.state.move_home()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Char('b') if key.modifiers.ctrl() => {
            self.state.move_left()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Char('c') if key.modifiers.ctrl() => {
            self.state.reset()
            self.history.reset_navigation(draft="")
            self.redraw_input_area(header?, prompt?, footer?)
            break Some(Key(key))
          }
          Char('d') if key.modifiers.ctrl() =>
            if self.state.text().length() == 0 {
              break None
            } else {
              self.state.delete_after()
              self.redraw_input_area(header?, prompt?, footer?)
            }
          Char('e') if key.modifiers.ctrl() => {
            self.state.move_end()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Char('f') if key.modifiers.ctrl() => {
            self.state.move_right()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Char('j') if key.modifiers.ctrl() => break Some(Key(key))
          Char('k') if key.modifiers.ctrl() => {
            self.state.kill_after()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Char('n') if key.modifiers.ctrl() =>
            self.recall_next_history(header?, prompt?, footer?)
          Char('p') if key.modifiers.ctrl() =>
            self.recall_previous_history(header?, prompt?, footer?)
          Char('u') if key.modifiers.ctrl() => {
            self.state.kill_before()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Enter => break Some(Key(key))
          Tab => break Some(Key(key))
          Backspace => {
            self.state.delete_before()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Delete => {
            self.state.delete_after()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Left => {
            self.state.move_left()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Right => {
            self.state.move_right()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Home => {
            self.state.move_home()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          End => {
            self.state.move_end()
            self.redraw_input_area(header?, prompt?, footer?)
          }
          Up => self.recall_previous_history(header?, prompt?, footer?)
          Down => self.recall_next_history(header?, prompt?, footer?)
          _ =>
            if key.text is Some(text) {
              self.state.insert_text(text)
              self.redraw_input_area(header?, prompt?, footer?)
            } else {
              break Some(Key(key))
            }
        }
      Input(Paste(text)) => {
        self.state.insert_text(text)
        self.redraw_input_area(header?, prompt?, footer?)
      }
      Input(_) => ()
      Resize(_) =>
        self.redraw_input_area(header?, prompt?, footer?, force_full=true)
    }
  }
}

///|
/// Read one line of user input from the terminal.
///
/// This convenience wrapper echoes submitted input into the output area and
/// treats only Enter and Ctrl-J as line submissions. It returns `None` when the
/// input stream ends or Ctrl+D is pressed on an empty line, and raises
/// `Interrupted` when the user presses Ctrl+C.
pub async fn Readline::read_line(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> String? {
  self.state.reset()
  self.history.reset_navigation(draft="")
  for ;; {
    match self.read_event(header?, prompt?, footer?) {
      Some(Key(key)) =>
        match key.code {
          Char('c') if key.modifiers.ctrl() => raise Interrupted
          Char('j') if key.modifiers.ctrl() => {
            let text = self.accept_current_line(
              header?,
              prompt?,
              footer?,
              echo_input=true,
            )
            break Some(text)
          }
          Enter => {
            let text = self.accept_current_line(
              header?,
              prompt?,
              footer?,
              echo_input=true,
            )
            break Some(text)
          }
          _ => ()
        }
      None => break None
    }
  }
}

///|
/// Write a document to the terminal without corrupting the active input area.
///
/// If a prompt is currently visible, the document is inserted above it and the
/// input cursor is restored afterwards.
pub async fn Readline::write_doc(self : Readline, doc : Doc) -> Unit {
  let size = self.terminal_size()
  self.write_output_frame(doc.layout(width=size.cols), size~)
}

///|
/// Redraw the currently visible input area, if one is active.
///
/// This lets higher-level adapters update header/footer state, such as queued
/// input previews or status text, while `read_event` or `read_line` is waiting
/// for input. If no input area has been drawn yet, this is a no-op.
pub async fn Readline::redraw(
  self : Readline,
  header? : Doc,
  prompt? : Span,
  footer? : Doc,
) -> Unit {
  if self.composer_height > 0 && self.composer_top > 0 {
    self.redraw_input_area(header?, prompt?, footer?, force_full=true)
  }
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
    self.composer_frame = None
    self.composer_cursor_row = 0
    self.composer_cursor_col = 0
  }
}
