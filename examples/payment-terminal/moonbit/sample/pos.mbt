///|
/// The scenarios that the POS runs. Each language runs the same steps.
pub let scenarios : Array[String] = [
  "payment", "errors", "cancellation", "refusals",
]

///|
/// A failed check of a scenario.
pub(all) suberror ScenarioError {
  ScenarioError(String)
}

///|
fn check(condition : Bool, message : String) -> Unit raise ScenarioError {
  if !condition {
    raise ScenarioError(message)
  }
}

///|
/// The POS side of a scenario: it answers the terminal's callbacks and, in the
/// cancellation scenario, cancels the payment on its first progress.
pub struct Pos {
  priv scenario : String
  priv mut cancel_sent : Bool
  priv phases : Array[String]
  priv messages : Array[String]
}

///|
pub fn Pos::new(scenario : String) -> Pos {
  { scenario, cancel_sent: false, phases: [], messages: [], }
}

///|
pub impl @pos.PointOfSaleHandler for Pos with fn payment_progress(
  self,
  input,
  context,
) {
  self.phases.push(input.phase.to_json().stringify())
  if self.scenario == "cancellation" && !self.cancel_sent {
    self.cancel_sent = true
    let client = @pos.PaymentTerminalClient::new(context.peer())
    client.cancel_request({ id: input.request_id, })
  }
}

///|
pub impl @pos.PointOfSaleHandler for Pos with fn confirm_tip(
  _self,
  _input,
  _context,
) {
  true
}

///|
pub impl @pos.PointOfSaleHandler for Pos with fn request_signature(
  _self,
  _input,
  _context,
) {
  b"test-signature"
}

///|
pub impl @pos.PointOfSaleHandler for Pos with fn display(self, input, _context) {
  self.messages.push(input.message)
}

///|
fn pos_usd(text : String) -> @pos.Money {
  { amount: @pos_rpc.Decimal::parse(text).unwrap(), currency: Usd, }
}

///|
fn card() -> @pos.TestCard {
  { masked_number: "**** 4242", }
}

///|
fn start(
  payment_id : String,
  amount : String,
  entry : @pos.EntryMethod,
) -> @pos.StartPaymentInput {
  { payment_id, amount: pos_usd(amount), entry, }
}

///|
async fn initialize(
  client : @pos.PaymentTerminalClient,
  pos_name : String,
) -> @pos.InitializeOutput {
  let output = client.initialize({ protocol_version: V1, pos_name, })
  client.initialized()
  output
}

///|
async fn finish(client : @pos.PaymentTerminalClient) -> Unit {
  client.shutdown()
  client.exit()
}

///|
/// Run `body` and give the code of the RpcError that it raises.
async fn refused_code(body : async () -> Unit) -> Int32? {
  body() catch {
    @pos_rpc.RpcError(code~, ..) => return Some(code)
    _ => return None
  }
  None
}

///|
/// Run a scenario with the client of a connected POS peer.
pub async fn run_scenario(
  pos : Pos,
  client : @pos.PaymentTerminalClient,
) -> Unit {
  match pos.scenario {
    "payment" => payment(pos, client)
    "errors" => errors(client)
    "cancellation" => cancellation(pos, client)
    "refusals" => refusals(client)
    other => raise ScenarioError("I do not know the scenario `\{other}`.")
  }
}

///|
async fn payment(pos : Pos, client : @pos.PaymentTerminalClient) -> Unit {
  client.ping()
  let output = initialize(client, "test checkout")
  check(output.capabilities.payment == Some(true), "I expected payment.")
  let paid = client.start_payment(start("test-1", "20.00", Chip(card())))
  check(
    paid.outcome is Approved({ authorization_code: "TEST-OK", }),
    "I expected an approved payment, found \{paid.outcome.to_json().stringify()}.",
  )
  check(
    pos.phases == ["\"insertCard\"", "\"enterPin\"", "\"authorizing\""],
    "I expected three progress phases, found \{pos.phases.join(", ")}.",
  )
  check(
    pos.messages == ["I am checking the test payment."],
    "I expected one display message, found \{pos.messages.join(", ")}.",
  )
  let status = client.payment_status({ payment_id: "test-1", })
  check(status is Approved(_), "I expected the approved status.")
  let receipt = client.get_receipt({ payment_id: "test-1", })
  let lines = receipt.lines.map(line => {
    "\{line.label}=\{line.amount.amount.to_string()}"
  })
  check(
    receipt.payment_id == "test-1" &&
    receipt.merchant.name == "Test shop" &&
    receipt.merchant.address == Some("Test street") &&
    lines == ["Test item=20.00", "Test tip=2.50"] &&
    receipt.total.amount.to_string() == "22.50" &&
    receipt.customer_copy == Some(true),
    "I expected the receipt of test-1 with 20.00 and 2.50 and the total 22.50, found \{lines.join(", ")} and the total \{receipt.total.amount.to_string()}.",
  )
  let first = client.list_transactions({
    next_token: None,
    since: Some(
      @pos_rpc.Timestamp::epoch_seconds(@pos_rpc.Decimal::parse("0").unwrap()),
    ),
  })
  check(
    first.next_token == Some("test-page-2"),
    "I expected the next page token.",
  )
  let second = client.list_transactions({
    next_token: Some("test-page-2"),
    since: None,
  })
  check(second.transactions.is_empty(), "I expected an empty second page.")
  let refund = client.refund_payment({
    payment_id: "test-1",
    amount: pos_usd("2.50"),
  })
  check(
    refund.amount.amount.to_string() == "2.50",
    "I expected the exact refund amount 2.50, found \{refund.amount.amount.to_string()}.",
  )
  client.void_payment({ payment_id: "test-1", })
  finish(client)
}

///|
async fn errors(client : @pos.PaymentTerminalClient) -> Unit {
  let _ = initialize(client, "test checkout")
  let expect_error = async fn(
    amount : String,
    entry : @pos.EntryMethod,
    what : String,
    matches : (Error) -> Bool,
  ) -> Unit {
    let result = client.start_payment(start("test-error", amount, entry)) catch {
      error => {
        check(
          matches(error),
          "I expected \{what} for \{amount}, found another error.",
        )
        return
      }
    }
    raise ScenarioError(
      "I expected \{what} for \{amount}, found \{result.to_json().stringify()}.",
    )
  }
  expect_error("1.13", Swipe(card()), "CardDeclined", error => {
    error is @pos.ServiceError::CardDeclined({ reason: "test decline", })
  })
  expect_error("1.14", Contactless(card()), "CardRemoved", error => {
    error is @pos.ServiceError::CardRemoved(_)
  })
  expect_error("1.15", ManualEntry(card()), "TerminalBusy", error => {
    error is @pos.ServiceError::TerminalBusy({ retry_after_seconds: 1, })
  })
  expect_error("1.16", Chip(card()), "Timeout", error => {
    error is @pos.ServiceError::Timeout(_)
  })
  let declined = client.start_payment(
    start("test-declined", "1.21", Chip(card())),
  )
  check(
    declined.outcome is Declined({ reason: "test decline", }),
    "I expected a declined outcome.",
  )
  let partial = client.start_payment(
    start("test-partial", "1.22", Chip(card())),
  )
  guard partial.outcome is PartiallyApproved({ authorized_amount, }) else {
    raise ScenarioError("I expected a partially approved outcome.")
  }
  check(
    authorized_amount.amount.to_string() == "1.00",
    "I expected the authorized amount 1.00.",
  )
  let big = client.start_payment(
    start("test-big", "12345678901234567.00", Chip(card())),
  )
  check(big.outcome is Approved(_), "I expected the big payment approved.")
  let mut maximum_text = ""
  let _ = client.refund_payment({
    payment_id: "test-big",
    amount: pos_usd("12345678901234568.00"),
  }) catch {
    @pos.ServiceError::RefundExceedsAmount({ maximum, .. }) => {
      maximum_text = maximum.amount.to_string()
      { refund_id: "", amount: maximum, }
    }
    _ => raise ScenarioError("I expected RefundExceedsAmount for test-big.")
  }
  check(
    maximum_text == "12345678901234567.00",
    "I expected the exact maximum 12345678901234567.00, found `\{maximum_text}`.",
  )
  let mut missing = ""
  client.void_payment({ payment_id: "test-missing", }) catch {
    @pos.ServiceError::PaymentNotFound({ payment_id, }) => missing = payment_id
    _ => raise ScenarioError("I expected PaymentNotFound for test-missing.")
  }
  check(missing == "test-missing", "I expected PaymentNotFound.")
  finish(client)
}

///|
async fn cancellation(pos : Pos, client : @pos.PaymentTerminalClient) -> Unit {
  let _ = initialize(client, "test checkout")
  let code = refused_code(async fn() {
    let _ = client.start_payment(
      start("test-cancel", "12345678901234567.17", Chip(card())),
    )
  })
  check(
    code == Some(-32800),
    "I expected the cancel code -32800, found \{code.map(c => c.to_string()).unwrap_or("no error")}.",
  )
  check(pos.cancel_sent, "I expected that the POS sent a cancel.")
  finish(client)
}

///|
async fn refusals(client : @pos.PaymentTerminalClient) -> Unit {
  let status = async fn(checked : Bool) -> Unit {
    let _ = client.payment_status({ payment_id: "test-1", }, checked~)
  }
  check(
    refused_code(async fn() { status(true) }) == Some(1007),
    "I expected a local state refusal before initialize.",
  )
  check(
    refused_code(async fn() { status(false) }) == Some(1007),
    "I expected the terminal to refuse payment.status before initialize.",
  )
  let output = initialize(client, "test checkout (no payment)")
  check(
    output.capabilities.payment == Some(false),
    "I expected payment to be off.",
  )
  let pay = async fn(checked : Bool) -> Unit {
    let _ = client.start_payment(
      start("test-1", "20.00", Chip(card())),
      checked~,
    )
  }
  check(
    refused_code(async fn() { pay(true) }) == Some(1008),
    "I expected a local capability refusal.",
  )
  check(
    refused_code(async fn() { pay(false) }) == Some(1008),
    "I expected the terminal to refuse payment.start without the capability.",
  )
  client.shutdown()
  check(
    refused_code(async fn() { status(true) }) == Some(1007),
    "I expected a local state refusal after shutdown.",
  )
  check(
    refused_code(async fn() { status(false) }) == Some(1007),
    "I expected the terminal to refuse payment.status after shutdown.",
  )
  client.exit()
}

///|
/// A short text for an error of a scenario.
pub fn describe(error : Error) -> String {
  match error {
    ScenarioError(text) => text
    @pos_rpc.RpcError(code~, message~, ..) => "error \{code}: \{message}"
    _ => "an unexpected error"
  }
}

///|
/// The port of `--port`, or -1 when the text is not a port number.
pub fn parse_port(text : String) -> Int32 {
  let mut value = 0
  if text.is_empty() || text.length() > 5 {
    return -1
  }
  for c in text {
    if !c.is_ascii_digit() {
      return -1
    }
    value = value * 10 + (c.to_int() - '0'.to_int())
  }
  if value > 65535 {
    -1
  } else {
    value
  }
}

///|
/// Write a diagnostic line to stderr. Stdout can be the stdio transport.
pub async fn note(text : String) -> Unit {
  @stdio.stderr.write(text + "\n")
}
