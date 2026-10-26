///|
/// A payment that the terminal approved, kept for status, receipt, refund
/// and void.
priv struct StoredPayment {
  amount : @terminal.Money
  outcome : @terminal.PaymentOutcome
}

///|
/// The sample terminal. Its rules depend only on the input, so every language
/// gives the same messages. All card values are masked test data.
pub struct Terminal {
  priv payments : Map[String, StoredPayment]
  priv order : Array[String]
  priv exit_process : Bool
}

///|
/// With `exit_process`, the terminal process ends a short time after the
/// `terminal.exit` notification. A server needs this: an HTTP session does
/// not end by itself.
pub fn Terminal::new(exit_process~ : Bool = false) -> Terminal {
  { payments: Map([]), order: [], exit_process, }
}

///|
fn terminal_usd(text : String) -> @terminal.Money {
  { amount: @terminal_rpc.Decimal::parse(text).unwrap(), currency: Usd, }
}

///|
fn not_found(payment_id : String) -> Error {
  @terminal.ServiceError::PaymentNotFound({ payment_id, })
}

///|
fn Terminal::stored(
  self : Terminal,
  payment_id : String,
) -> StoredPayment raise {
  match self.payments.get(payment_id) {
    Some(payment) => payment
    None => raise not_found(payment_id)
  }
}

///|
/// The cents of an amount, such as `.13` for `1.13`.
fn cents(amount : @terminal_rpc.Decimal) -> String {
  let text = amount.to_string()
  match text.rev_find(".") {
    Some(at) => text[at:].to_owned()
    None => ""
  }
}

///|
async fn progress(
  pos : @terminal.PointOfSaleClient,
  context : @terminal_rpc.CallContext,
  phase : @terminal.PaymentPhase,
) -> Unit {
  pos.payment_progress({ request_id: context.id_json(), phase, })
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn initialize(
  _self,
  input,
  _context,
) {
  let capabilities : @terminal.Capabilities = if input.pos_name.has_suffix(
      "(no payment)",
    ) {
    {
      payment: Some(false),
      swipe: None,
      chip: None,
      contactless: None,
      pin: None,
      tips: None,
      signature: None,
      progress: None,
      cancellation: None,
    }
  } else {
    {
      payment: Some(true),
      swipe: Some(true),
      chip: Some(true),
      contactless: Some(true),
      pin: Some(true),
      tips: Some(true),
      signature: Some(true),
      progress: Some(true),
      cancellation: Some(true),
    }
  }
  { protocol_version: V1, terminal_id: "test-terminal", capabilities, }
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn initialized(
  _self,
  _context,
) {
  ()
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn ping(
  _self,
  _context,
) {
  ()
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn start_payment(
  self,
  input,
  context,
) {
  let pos = @terminal.PointOfSaleClient::new(context.peer())
  let payment_id = input.payment_id
  match cents(input.amount.amount) {
    ".13" =>
      raise @terminal.ServiceError::CardDeclined(@terminal.CardDeclined::{
        reason: "test decline",
      })
    ".14" =>
      raise @terminal.ServiceError::CardRemoved(@terminal.CardRemoved::{ })
    ".15" =>
      raise @terminal.ServiceError::TerminalBusy(@terminal.TerminalBusy::{
        retry_after_seconds: 1,
      })
    ".16" => raise @terminal.ServiceError::Timeout(@terminal.Timeout::{ })
    ".17" => {
      // Wait for the POS to cancel the call. The runtime answers it.
      progress(pos, context, InsertCard)
      @async.sleep(60000)
      raise @terminal.ServiceError::Timeout(@terminal.Timeout::{ })
    }
    ".21" => { payment_id, outcome: Declined({ reason: "test decline", }), }
    ".22" =>
      {
        payment_id,
        outcome: PartiallyApproved({ authorized_amount: terminal_usd("1.00"), }),
      }
    _ => {
      progress(pos, context, InsertCard)
      progress(pos, context, EnterPin)
      let _ = pos.confirm_tip({ payment_id, amount: terminal_usd("2.50"), })
      let _ = pos.request_signature({
        payment_id,
        prompt: "Sign the test receipt",
      })
      pos.display({ message: "I am checking the test payment.", })
      progress(pos, context, Authorizing)
      let outcome : @terminal.PaymentOutcome = Approved({
        authorization_code: "TEST-OK",
      })
      if !self.payments.contains(payment_id) {
        self.order.push(payment_id)
      }
      self.payments[payment_id] = { amount: input.amount, outcome, }
      { payment_id, outcome, }
    }
  }
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn payment_status(
  self,
  input,
  _context,
) {
  self.stored(input.payment_id).outcome
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn refund_payment(
  self,
  input,
  _context,
) {
  let stored = self.stored(input.payment_id)
  if input.amount.amount.compare_value(stored.amount.amount) > 0 {
    raise @terminal.ServiceError::RefundExceedsAmount({
      payment_id: input.payment_id,
      maximum: stored.amount,
    })
  }
  { refund_id: "test-refund", amount: input.amount, }
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn void_payment(
  self,
  input,
  _context,
) {
  let _ = self.stored(input.payment_id)
  self.payments.remove(input.payment_id)
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn get_receipt(
  self,
  input,
  _context,
) {
  let stored = self.stored(input.payment_id)
  let tip = terminal_usd("2.50")
  let total = add_decimal(stored.amount.amount.to_string(), "2.50")
  {
    payment_id: input.payment_id,
    merchant: { name: "Test shop", address: Some("Test street"), },
    lines: [
      { label: "Test item", amount: stored.amount, },
      { label: "Test tip", amount: tip, },
    ],
    total: {
      amount: @terminal_rpc.Decimal::parse(total).unwrap(),
      currency: stored.amount.currency,
    },
    customer_copy: Some(true),
    footer: None,
  }
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn list_transactions(
  self,
  input,
  _context,
) {
  if input.next_token is Some(_) {
    return { transactions: [], next_token: None, }
  }
  let transactions : Array[@terminal.Transaction] = []
  for payment_id in self.order {
    guard self.payments.get(payment_id) is Some(stored) else { continue }
    transactions.push({
      payment_id,
      created_at: @terminal_rpc.Timestamp::epoch_seconds(
        @terminal_rpc.Decimal::parse("1792886400").unwrap(),
      ),
      amount: stored.amount,
      labels: Some({ "checkout": "test", "card": "**** 4242" }),
    })
  }
  { transactions, next_token: Some("test-page-2"), }
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn shutdown(
  _self,
  _context,
) {
  ()
}

///|
pub impl @terminal.PaymentTerminalHandler for Terminal with fn exit(
  self,
  _context,
) {
  if self.exit_process {
    @async.sleep(200)
    @sys.exit(0)
  }
}

///|
/// The exact sum of two non-negative decimal texts, such as `20.00` and
/// `2.50`. The result has the larger number of fraction digits. No value goes
/// through a float.
pub fn add_decimal(a : String, b : String) -> String {
  let split = (text : String) => {
    match text.find(".") {
      Some(at) => (text[:at].to_owned(), text[at + 1:].to_owned())
      None => (text, "")
    }
  }
  let (a_int, a_frac) = split(a)
  let (b_int, b_frac) = split(b)
  let scale = if a_frac.length() > b_frac.length() {
    a_frac.length()
  } else {
    b_frac.length()
  }
  let pad = (frac : String) => {
    let out = StringBuilder()
    out.write_string(frac)
    for _ in frac.length()..<scale {
      out.write_char('0')
    }
    out.to_string()
  }
  let x = (a_int + pad(a_frac)).to_array()
  let y = (b_int + pad(b_frac)).to_array()
  let digits : Array[Char] = []
  let mut carry = 0
  let mut i = x.length() - 1
  let mut j = y.length() - 1
  while i >= 0 || j >= 0 || carry > 0 {
    let dx = if i >= 0 { x[i].to_int() - '0'.to_int() } else { 0 }
    let dy = if j >= 0 { y[j].to_int() - '0'.to_int() } else { 0 }
    let sum = dx + dy + carry
    digits.push(Int32::unsafe_to_char(sum % 10 + '0'.to_int()))
    carry = sum / 10
    i -= 1
    j -= 1
  }
  digits.rev_in_place()
  let text = String::from_array(digits)
  let point = text.length() - scale
  let int_part = if point <= 0 { "0" } else { text[:point].to_owned() }
  if scale == 0 {
    int_part
  } else {
    int_part + "." + text[point:].to_owned()
  }
}
