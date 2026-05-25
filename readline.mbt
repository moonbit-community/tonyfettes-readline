///|
struct Readline {
  tty : @tty.Tty
  config : Config
  state : State
}

///|
pub async fn[T] with_readline(
  esc_timeout_ms? : Int,
  f : async (Readline) -> T,
) -> T {
  let config = Config(esc_timeout_ms?)
  let tty = @tty.Tty::open()
  let readline = { tty, config }
  tty.with_raw_mode() <| () => {  }
}

///|
pub async fn Readline::read_line(
  self : Readline,
  header? : Frame,
  prompt? : Span,
  footer? : Frame,
) -> Event {
  for ;; {
    let event = self.tty.read_event(esc_timeout_ms=self.config.esc_timeout_ms) catch {
      @async/io.ReaderClosed => break Eof
      error => raise error
    }
    match event {
      Input(Key(key)) =>
        match key.code {
          Char('c') if key.modifiers.ctrl() => break Interrupted
          Char('d') if key.modifiers.ctrl() => break Eof
          Enter => break Line(self.state.text)
        }
    }
  }
}

///|
pub async fn Readline::write_line(self : Readline, text : Line) -> Unit {

}
