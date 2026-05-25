///|
fn prompt() -> @rl.Span {
  @rl.Span::new(
    "readline> ",
    style=@rl.Style::new(foreground=@tty_color.Basic(@tty_color.BrightGreen)),
  )
}

///|
fn header() -> @rl.Doc {
  @rl.Doc([
    @rl.Text::new([
      @rl.Span::new(
        "readline demo",
        style=@rl.Style::new(
          foreground=@tty_color.Basic(@tty_color.BrightCyan),
          underline=true,
        ),
      ),
    ]),
    @rl.Text::plain("Enter submits. Ctrl-C interrupts. Ctrl-D exits."),
  ])
}

///|
fn footer(round : Int) -> @rl.Doc {
  @rl.Doc([
    @rl.Text::new([
      @rl.Span::new(
        "round \{round}",
        style=@rl.Style::new(
          foreground=@tty_color.Basic(@tty_color.BrightBlack),
        ),
      ),
    ]),
  ])
}

///|
async fn run(readline : @rl.Readline) -> Unit {
  let mut round = 1
  readline.write_doc(@rl.Doc::plain("Type something to echo it back."))
  for ;; {
    match
      readline.read_line(header=header(), prompt=prompt(), footer=footer(round)) {
      @rl.Line(text) => {
        readline.write_doc(@rl.Doc::plain("submitted: " + text))
        round += 1
      }
      @rl.Interrupted => {
        readline.write_doc(@rl.Doc::plain("interrupted"))
        round += 1
      }
      @rl.Eof => {
        readline.write_doc(@rl.Doc::plain("bye"))
        break
      }
    }
  }
}

///|
async fn main {
  @rl.with_readline(esc_timeout_ms=50, readline => run(readline))
}
