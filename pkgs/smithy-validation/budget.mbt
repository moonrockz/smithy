///|
priv struct Budget {
  limits : Limits
  mut used : Int32
  mut complete : Bool
  findings : Array[Finding]
}

///|
fn Budget::new(limits : Limits, used~ : Int32 = 0) -> Budget {
  { limits, used, complete: true, findings: [], }
}

///|
/// A request-scoped work allowance. Several phases of one request, such as parsing, projection and
/// validation, charge the same meter, so a later phase receives only the remaining work.
pub struct WorkMeter {
  priv limit : Int32
  priv mut used : Int32
  priv mut exhausted : Bool
}

///|
pub fn WorkMeter::new(limit : Int32) -> WorkMeter raise ConfigurationError {
  guard limit > 0 && limit <= 10000000 else {
    raise ConfigurationError("I expected a work limit of 1..10000000.")
  }
  { limit, used: 0, exhausted: false, }
}

///|
pub fn WorkMeter::limit(self : WorkMeter) -> Int32 {
  self.limit
}

///|
pub fn WorkMeter::used(self : WorkMeter) -> Int32 {
  self.used
}

///|
/// True after a charge was refused. An exhausted meter refuses every later charge.
pub fn WorkMeter::exhausted(self : WorkMeter) -> Bool {
  self.exhausted
}

///|
/// Charge `units` of work. Returns false, and charges nothing, when the meter has too little left.
pub fn WorkMeter::charge(self : WorkMeter, units : Int32) -> Bool {
  if self.exhausted || units < 0 || units > self.limit - self.used {
    self.exhausted = true
    return false
  }
  self.used += units
  true
}

///|
fn Budget::stop(
  self : Budget,
  path : InstancePath,
  shape : @smithy.ShapeId,
  reason : String,
) -> Unit {
  if !self.complete {
    return
  }
  self.complete = false
  let finding : Finding = {
    code: LimitExceeded,
    severity: Error,
    path,
    shape,
    message: "I reached the " +
    reason +
    " validation limit before completing the value.",
  }
  if self.findings.length() < self.limits.findings {
    self.findings.push(finding)
  }
}

///|
fn Budget::charge(
  self : Budget,
  path : InstancePath,
  shape : @smithy.ShapeId,
  units~ : Int32 = 1,
) -> Bool {
  if !self.complete {
    return false
  }
  if units > self.limits.work - self.used {
    self.stop(path, shape, "work")
    return false
  }
  self.used += units
  true
}

///|
fn Budget::room(
  self : Budget,
  path : InstancePath,
  shape : @smithy.ShapeId,
  children : Int32,
  pending~ : Int32 = 0,
) -> Bool {
  if pending > self.limits.work - self.used ||
    children > self.limits.work - self.used - pending {
    self.stop(path, shape, "work")
    false
  } else {
    self.complete
  }
}

///|
fn Budget::emit(
  self : Budget,
  code : FindingCode,
  path : InstancePath,
  shape : @smithy.ShapeId,
  message : String,
) -> Unit {
  if !self.complete {
    return
  }
  if self.findings.length() >= self.limits.findings - 1 {
    self.stop(path, shape, "findings")
    return
  }
  self.findings.push({ code, severity: Error, path, shape, message, })
}
