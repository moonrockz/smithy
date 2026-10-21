///|
priv struct Budget {
  limits : Limits
  mut used : Int32
  mut complete : Bool
  findings : Array[Finding]
}

///|
fn Budget::new(limits : Limits) -> Budget {
  { limits, used: 0, complete: true, findings: [], }
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
