///|
test "python names" {
  assert_eq(@python.snake_name("paymentId"), "payment_id")
  assert_eq(@python.snake_name("HTTPServer"), "http_server")
  assert_eq(@python.snake_name("class"), "class_")
  assert_eq(@python.snake_name("model_dump"), "model_dump_")
  assert_eq(@python.snake_name("2fa"), "n2fa")
  assert_eq(@python.method_name("Peer"), "peer_")
  assert_eq(@python.pascal_name("manualEntry"), "ManualEntry")
  assert_eq(@python.enum_member_name("insertCard"), "INSERT_CARD")
  assert_eq(@python.enum_member_name("USD"), "USD")
  assert_eq(@python.enum_member_name("1x"), "V_1X")
  assert_eq(@python.class_name("money"), "Money")
  assert_eq(@python.class_name("Peer"), "Peer_")
  assert_eq(@python.py_string("a\"b\\c\n\u{1}"), "\"a\\\"b\\\\c\\n\\x01\"")
}
