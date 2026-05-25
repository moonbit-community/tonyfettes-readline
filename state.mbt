///|
/// We believe that most input is in one single line, so we use a simple
/// model contains only a String for the text, and a Int for the cursor
/// position
priv struct State {
  mut text : String
  mut cursor : Int
}

///|
fn State::new() -> State {
  { text: "", cursor: 0 }
}

///|
fn State::text(self : State) -> String {
  self.text
}

///|
fn State::reset(self : State) -> Unit {
  self.text = ""
  self.cursor = 0
}

///|
fn State::replace(self : State, text : String) -> Unit {
  self.text = text
  self.cursor = self.length()
}

///|
fn State::length(self : State) -> Int {
  @grapheme.graphemes(self.text).length()
}

///|
fn State::cursor(self : State) -> Int {
  let length = self.length()
  if self.cursor < 0 {
    0
  } else if self.cursor > length {
    length
  } else {
    self.cursor
  }
}

///|
fn State::slice(self : State, start : Int, end : Int) -> String {
  let graphemes = @grapheme.graphemes(self.text)
  let length = graphemes.length()
  let start = if start < 0 {
    0
  } else if start > length {
    length
  } else {
    start
  }
  let end = if end < start {
    start
  } else if end > length {
    length
  } else {
    end
  }
  graphemes[start:end].to_string()
}

///|
/// Inserts given text behind the cursor. Since this is the only
/// reasonable way to insert a piece of text, we simplify the
/// function name to be `insert_text`.
fn State::insert_text(self : State, text : String) -> Unit {
  let cursor = self.cursor()
  let prefix = self.slice(0, cursor)
  let suffix = self.slice(cursor, self.length())
  self.text = prefix + text + suffix
  self.cursor = cursor + @grapheme.graphemes(text).length()
}

///|
fn State::delete_before(self : State) -> Unit {
  let cursor = self.cursor()
  if cursor > 0 {
    let prefix = self.slice(0, cursor - 1)
    let suffix = self.slice(cursor, self.length())
    self.text = prefix + suffix
    self.cursor = cursor - 1
  } else {
    self.cursor = 0
  }
}

///|
fn State::delete_after(self : State) -> Unit {
  let cursor = self.cursor()
  if cursor < self.length() {
    let prefix = self.slice(0, cursor)
    let suffix = self.slice(cursor + 1, self.length())
    self.text = prefix + suffix
  }
  self.cursor = cursor
}

///|
fn State::kill_before(self : State) -> Unit {
  let cursor = self.cursor()
  self.text = self.slice(cursor, self.length())
  self.cursor = 0
}

///|
fn State::kill_after(self : State) -> Unit {
  let cursor = self.cursor()
  self.text = self.slice(0, cursor)
  self.cursor = cursor
}

///|
fn State::move_left(self : State) -> Unit {
  let cursor = self.cursor()
  self.cursor = if cursor > 0 { cursor - 1 } else { 0 }
}

///|
fn State::move_right(self : State) -> Unit {
  let cursor = self.cursor()
  let length = self.length()
  self.cursor = if cursor < length { cursor + 1 } else { length }
}

///|
fn State::move_home(self : State) -> Unit {
  self.cursor = 0
}

///|
fn State::move_end(self : State) -> Unit {
  self.cursor = self.length()
}

///|
fn State::before_cursor(self : State) -> String {
  self.slice(0, self.cursor())
}
