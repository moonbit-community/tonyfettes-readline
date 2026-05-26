///|
fn prompt() -> @rl.Span {
  Span("readline> ", style=@rl.Style::new(foreground=Basic(BrightGreen)))
}

///|
fn header() -> @rl.Doc {
  Doc([
    Text([
      Span(
        "readline demo",
        style=@rl.Style::new(foreground=Basic(BrightCyan), underline=true),
      ),
    ]),
    @rl.Text::plain("Enter submits. Up/Down recall. Ctrl-A/E/B/F/K edit."),
    @rl.Text::plain("Ctrl-C interrupts. Ctrl-D exits."),
  ])
}

///|
fn footer(round : Int) -> @rl.Doc {
  Doc([
    Text([
      Span(
        "round \{round}",
        style=@rl.Style::new(foreground=Basic(BrightBlack)),
      ),
    ]),
  ])
}

///|
async fn run(readline : @rl.Readline) -> Unit {
  let mut round = 1
  readline.write_doc(@rl.Doc::plain("Type something to echo it back."))
  for ;; {
    try {
      match
        readline.read_line(
          header=header(),
          prompt=prompt(),
          footer=footer(round),
        ) {
        Some(text) => {
          readline.write_doc(@rl.Doc::plain("submitted: " + text))
          round += 1
        }
        None => {
          readline.write_doc(@rl.Doc::plain("bye"))
          break
        }
      }
    } catch {
      @rl.Interrupted => {
        readline.write_doc(@rl.Doc::plain("interrupted"))
        round += 1
      }
      error => raise error
    }
  }
}

///|
async fn main {
  @rl.with_readline(esc_timeout_ms=50, readline => run(readline))
}
