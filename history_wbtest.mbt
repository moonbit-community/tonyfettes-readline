///|
test "history recalls entries and restores draft" {
  let history = History::new()
  @debug.assert_eq(history.previous("draft"), None)
  history.push("one")
  history.push("two")
  @debug.assert_eq(history.previous("draft"), Some("two"))
  @debug.assert_eq(history.previous("ignored"), Some("one"))
  @debug.assert_eq(history.previous("ignored"), Some("one"))
  @debug.assert_eq(history.next(), Some("two"))
  @debug.assert_eq(history.next(), Some("draft"))
  @debug.assert_eq(history.next(), None)
}

///|
test "history skips empty and adjacent duplicate entries" {
  let history = History::new()
  history.push("")
  @debug.assert_eq(history.previous("draft"), None)
  history.push("same")
  history.push("same")
  @debug.assert_eq(history.previous("draft"), Some("same"))
  @debug.assert_eq(history.previous("ignored"), Some("same"))
}
