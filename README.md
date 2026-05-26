# readline

A native-terminal line editor for MoonBit async command-line programs.

`tonyfettes/readline` manages raw terminal mode, redraws a live prompt, keeps
input history, wraps Unicode text by display width, and lets programs write
styled output without overwriting the current input area.

## Requirements

This package supports the native target and expects to run in an interactive
TTY. It depends on `moonbitlang/async`, `moonbit-community/tty`,
`kawaz/grapheme`, and `rami3l/unicodewidth`.

## Usage

Add the package to your module and import it from a native executable package:

```moonbit
import {
  "moonbitlang/async",
  "tonyfettes/readline" @rl,
  "moonbit-community/tty/color" @tty_color,
}

supported_targets = "native"
```

Create a session with `with_readline`, then call `read_line` in a loop:

```moonbit
///|
fn prompt() -> @rl.Span {
  @rl.Span(
    "demo> ",
    style=@rl.Style::new(foreground=@tty_color.Basic(@tty_color.BrightGreen)),
  )
}

///|
async fn run(readline : @rl.Readline) -> Unit {
  readline.write_doc(@rl.Doc::plain("Type a line. Ctrl-D exits."))
  for ;; {
    match readline.read_line(prompt=prompt()) {
      @rl.Line(text) =>
        readline.write_doc(@rl.Doc::plain("submitted: " + text))
      @rl.Interrupted =>
        readline.write_doc(@rl.Doc::plain("interrupted"))
      @rl.Eof => break
    }
  }
}

///|
async fn main {
  @rl.with_readline(esc_timeout_ms=50, readline => run(readline))
}
```

`with_readline` opens the terminal, enables raw mode, passes a `Readline`
session to the callback, and restores the terminal before returning or
re-raising an error. The optional `esc_timeout_ms` value controls how long the
terminal reader waits to disambiguate escape sequences.

## Rendering Model

Text output is built as `Doc -> Text -> Span`:

- `Span` is a string fragment plus a `Style`.
- `Text` is a logical block made of spans. It wraps by display width and treats
  newline characters as forced row breaks.
- `Doc` is a sequence of text blocks used for headers, footers, and output.

Use `Readline::write_doc` for application output while the prompt is active.
It inserts the document above the live input area and restores the input cursor.

## Input Behavior

`Readline::read_line` returns:

- `Line(text)` when the user submits input.
- `Interrupted` when the user presses Ctrl-C.
- `Eof` when the input stream closes or the user presses Ctrl-D on an empty
  line.

Supported editing keys include:

- Enter or Ctrl-J: submit the current line.
- Ctrl-A / Ctrl-E, Home / End: move to start or end.
- Ctrl-B / Ctrl-F, Left / Right: move by one grapheme.
- Backspace / Delete: delete before or after the cursor.
- Ctrl-U / Ctrl-K: delete before or after the cursor.
- Up / Down, Ctrl-P / Ctrl-N: navigate input history.
- Paste and terminal resize events are handled by redrawing the composer.

## Examples

Run the basic demo:

```sh
moon run examples/readline
```

Run the symbolic-math demo:

```sh
moon run examples/symbit
```
