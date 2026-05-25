///|
pub(all) enum Event {
  Line(String)
  /// Ctrl+C
  Interrupted
  /// Ctrl+D
  Eof
}
