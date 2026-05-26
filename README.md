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
    try {
      match readline.read_line(prompt=prompt()) {
        Some(text) =>
          readline.write_doc(@rl.Doc::plain("submitted: " + text))
        None => break
      }
    } catch {
      @rl.Interrupted =>
        readline.write_doc(@rl.Doc::plain("interrupted"))
      error => raise error
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
Use `Readline::redraw` to refresh the active header, prompt, or footer without
writing output.

## Input Behavior

`Readline::read_line` returns:

- `Some(text)` when the user submits input.
- `None` when the input stream closes or the user presses Ctrl-D on an empty
  line.
- It raises `Interrupted` when the user presses Ctrl-C.

Use `Readline::read_event` when callers need more control. It keeps normal
editing behavior inside readline, then returns unconsumed key events so
application code can decide whether Enter, Tab, or another key means submit,
queue, cancel, or something else. `None` means EOF.

Call `Readline::text` to inspect the current editable buffer without accepting
or clearing it.

After deciding to consume the current line, call `Readline::accept`. `accept`
returns the current text, adds it to readline's input recall history for
Up/Down navigation, clears the editor, and redraws the live input area. It does
not echo the submitted prompt line into output, so callers that own a
higher-level transcript can render it themselves.

Supported editing keys include:

- Enter or Ctrl-J: submit the current line in `read_line`; returned to the
  caller by `read_event`.
- Tab: returned to the caller by `read_event`.
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
