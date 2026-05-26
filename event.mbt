///|
/// The result of a `Readline::read_line` interaction.
pub(all) enum Event {
  /// The user submitted a complete input line.
  Line(String)
  /// The user pressed Ctrl+C.
  Interrupted
  /// The input stream ended, or the user pressed Ctrl+D on an empty line.
  Eof
}
