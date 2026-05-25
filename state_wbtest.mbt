///|
test "state edits by grapheme" {
  let state = State::new()
  state.insert_text("a👨‍👩‍👧‍👦b")
  state.move_left()
  state.delete_before()
  inspect(state.text(), content="ab")
  inspect(state.cursor(), content="1")
  state.insert_text("你")
  inspect(state.text(), content="a你b")
  inspect(state.cursor(), content="2")
}
