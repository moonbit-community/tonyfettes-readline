///|
priv struct Config {
  esc_timeout_ms : Int
}

///|
fn Config::new(esc_timeout_ms? : Int = 50) -> Config {
  { esc_timeout_ms, }
}
