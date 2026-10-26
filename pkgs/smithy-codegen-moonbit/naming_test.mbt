///|
test "snake names" {
  assert_eq(@moonbit.snake_name("maskedNumber"), "masked_number")
  assert_eq(@moonbit.snake_name("StartPayment"), "start_payment")
  assert_eq(@moonbit.snake_name("HTTPServer"), "http_server")
  assert_eq(@moonbit.snake_name("retryAfterSeconds"), "retry_after_seconds")
  assert_eq(@moonbit.snake_name("type"), "type_")
  assert_eq(@moonbit.snake_name("member"), "member_")
  assert_eq(@moonbit.snake_name("2fa"), "n2fa")
  assert_eq(@moonbit.snake_name("ID"), "id")
}

///|
test "variant names" {
  assert_eq(@moonbit.variant_name("INSERT_CARD"), "InsertCard")
  assert_eq(@moonbit.variant_name("manualEntry"), "ManualEntry")
  assert_eq(@moonbit.variant_name("USD"), "Usd")
  assert_eq(@moonbit.variant_name("swipe"), "Swipe")
  assert_eq(@moonbit.variant_name("1x"), "V1x")
}

///|
test "type names" {
  assert_eq(@moonbit.type_name("Money"), "Money")
  assert_eq(@moonbit.type_name("receipt"), "Receipt")
  assert_eq(@moonbit.type_name("String"), "String_")
  assert_eq(@moonbit.type_name("Json"), "Json_")
}
