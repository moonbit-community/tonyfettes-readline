///|
priv enum EvalMode {
  Simplify
  Raw
  Latex
}

///|
priv enum Command {
  Empty
  Quit
  Help
  Eval(EvalMode, String)
}

///|
fn prompt() -> @rl.Span {
  @rl.Span(
    "symbit> ",
    style=@rl.Style::new(foreground=@tty_color.Basic(@tty_color.BrightGreen)),
  )
}

///|
fn result_doc(text : String) -> @rl.Doc {
  @rl.Doc([
    @rl.Text([
      @rl.Span(
        "= ",
        style=@rl.Style::new(foreground=@tty_color.Basic(@tty_color.BrightBlue)),
      ),
      @rl.Span::plain(text),
    ]),
  ])
}

///|
fn error_doc(text : String) -> @rl.Doc {
  @rl.Doc([
    @rl.Text([
      @rl.Span(
        "error: ",
        style=@rl.Style::new(foreground=@tty_color.Basic(@tty_color.BrightRed)),
      ),
      @rl.Span::plain(text),
    ]),
  ])
}

///|
fn help_doc() -> @rl.Doc {
  @rl.Doc([
    @rl.Text::plain("Commands:"),
    @rl.Text::plain("  <expr>        parse, simplify, and pretty-print"),
    @rl.Text::plain("  :raw <expr>   parse and pretty-print without simplify"),
    @rl.Text::plain("  :latex <expr> render the parsed expression as LaTeX"),
    @rl.Text::plain("  :q            exit"),
  ])
}

///|
fn command(input : String) -> Command {
  let text = input.trim().to_owned()
  if text == "" {
    Empty
  } else if text == ":q" || text == ":quit" || text == ":exit" {
    Quit
  } else if text == ":h" || text == ":help" {
    Help
  } else if text is [.. ":raw ", .. expr] {
    Eval(Raw, expr.trim().to_owned())
  } else if text is [.. ":latex ", .. expr] {
    Eval(Latex, expr.trim().to_owned())
  } else if text is [.. ":simplify ", .. expr] {
    Eval(Simplify, expr.trim().to_owned())
  } else {
    Eval(Simplify, text)
  }
}

///|
fn parse_expr(text : String) -> @symcore.Expr raise @symparse.ParseError {
  @symparse.parse_expr_in_with_transformations(
    text,
    @symparse.relaxed_transformations(),
    @symparse.default_parse_context(),
  )
}

///|
fn eval(mode : EvalMode, text : String) -> String raise @symparse.ParseError {
  let expr = parse_expr(text)
  match mode {
    Simplify => @symcore.expr_display(@sym.simplify(expr))
    Raw => @symcore.expr_display(expr)
    Latex => @symprint.latex(expr)
  }
}

///|
fn parse_error_message(error : @symparse.ParseError) -> String {
  match error {
    UnexpectedChar(span~, ch) =>
      "unexpected character '" +
      ch.to_string() +
      "' at " +
      span.start.to_string()
    UnexpectedToken(span~, expected, actual) =>
      "expected " +
      expected +
      ", got " +
      actual +
      " at " +
      span.start.to_string()
    UnexpectedEof(span~, expected) =>
      "expected " + expected + " at end of input " + span.start.to_string()
    InvalidNumber(span~, text) =>
      "invalid number '" + text + "' at " + span.start.to_string()
    UnsupportedConstruct(span~, message) =>
      message + " at " + span.start.to_string()
  }
}

///|
fn eval_doc(mode : EvalMode, text : String) -> @rl.Doc {
  if text == "" {
    error_doc("missing expression")
  } else {
    try eval(mode, text) catch {
      error => error_doc(parse_error_message(error))
    } noraise {
      output => result_doc(output)
    }
  }
}

///|
async fn handle_line(readline : @rl.Readline, text : String) -> Bool {
  match command(text) {
    Empty => true
    Quit => false
    Help => {
      readline.write_doc(help_doc())
      true
    }
    Eval(mode, expr) => {
      readline.write_doc(eval_doc(mode, expr))
      true
    }
  }
}

///|
async fn run(readline : @rl.Readline) -> Unit {
  readline.write_doc(@rl.Doc::plain("Try: (x + 1)^2, sin(x)^2 + cos(x)^2"))
  for ;; {
    match readline.read_line(prompt=prompt()) {
      @rl.Line(text) => if !handle_line(readline, text) { break }
      @rl.Interrupted => readline.write_doc(@rl.Doc::plain("interrupted"))
      @rl.Eof => break
    }
  }
}

///|
async fn main {
  @rl.with_readline(esc_timeout_ms=50, readline => run(readline))
}
