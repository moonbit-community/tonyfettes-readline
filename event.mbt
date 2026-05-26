///|
/// Raised by `Readline::read_line` when the user presses Ctrl+C.
pub(all) suberror Interrupted {
  Interrupted
}

///|
/// An event that readline did not consume as line editing.
pub(all) enum Event {
  /// A key that application code can interpret.
  Key(@tty/input.KeyEvent)
}
