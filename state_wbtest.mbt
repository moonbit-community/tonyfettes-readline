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

///|
test "state replaces text and kills around cursor" {
  let state = State::new()
  state.replace("abc")
  inspect(state.text(), content="abc")
  inspect(state.cursor(), content="3")
  state.move_left()
  state.kill_after()
  inspect(state.text(), content="ab")
  inspect(state.cursor(), content="2")
  state.replace("你好世界")
  state.move_left()
  state.move_left()
  state.kill_before()
  inspect(state.text(), content="世界")
  inspect(state.cursor(), content="0")
}
