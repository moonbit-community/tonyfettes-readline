///|
/// We believe that most input is in one single line, so we use a simple
/// model contains only a String for the text, and a Int for the cursor
/// position
priv struct State {
  mut text : String
  mut cursor : Int
}

///|
fn State::get_text(self : State) -> String {
  self.text
}

///|
fn State::set_text(self : State, text : String) -> Unit {
  self.text = text
}

///|
/// Inserts given text behind the cursor. Since this is the only
/// reasonable way to insert a piece of text, we simplify the
/// function name to be `insert_text`.
fn State::insert_text(self : State, text : String) -> Unit {

}
