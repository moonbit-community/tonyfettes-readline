///|
priv struct History {
  entries : Array[String]
  // Cursor is in the inclusive range [0, entries.length()].
  // entries.length() means the user is editing the fresh, not-yet-submitted
  // draft line rather than a stored history item.
  mut cursor : Int
  mut draft : String
}

///|
fn History::new() -> History {
  { entries: [], cursor: 0, draft: "" }
}

///|
fn History::reset_navigation(self : History, draft~ : String) -> Unit {
  self.cursor = self.entries.length()
  self.draft = draft
}

///|
fn History::push(self : History, text : String) -> Unit {
  if text.length() > 0 {
    if self.entries.last() != Some(text) {
      self.entries.push(text)
    }
  }
  self.reset_navigation(draft="")
}

///|
fn History::previous(self : History, current : String) -> String? {
  if self.entries.length() == 0 {
    return None
  }
  if self.cursor == self.entries.length() {
    self.draft = current
  }
  if self.cursor > 0 {
    self.cursor -= 1
  }
  self.entries.get(self.cursor)
}

///|
fn History::next(self : History) -> String? {
  if self.cursor >= self.entries.length() {
    return None
  }
  self.cursor += 1
  if self.cursor == self.entries.length() {
    Some(self.draft)
  } else {
    self.entries.get(self.cursor)
  }
}
