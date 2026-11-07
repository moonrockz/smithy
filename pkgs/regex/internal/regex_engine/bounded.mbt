// Added for moonrockz/regex.

///|
priv struct BooleanState {
  key : FixedArray[Int32]
  trans : FixedArray[Int32]
}

///|
/// A Boolean specialization of core's lazy tagged DFA. Capture tags are epsilon
/// moves; an accept anywhere proves existence, so registers and reuse are absent.
priv struct BooleanRun {
  program : Program
  work : Work
  states : Buffer[BooleanState]
  index : StateIndex
  visited : FixedArray[Int32]
  targeted : FixedArray[Int32]
  mut epoch : Int32
  stack : Buffer[Int32]
  out : Buffer[Int32]
}

///|
const BOOL_MATCH : Int32 = -3

///|
fn BooleanRun::new(
  program : Program,
  work : Work,
) -> BooleanRun raise WorkExhausted {
  work.spend(2 * program.nodes.length())
  {
    program,
    work,
    states: Buffer::new(),
    index: StateIndex::new(),
    visited: FixedArray::make(program.nodes.length(), 0),
    targeted: FixedArray::make(program.nodes.length(), 0),
    epoch: 0,
    stack: Buffer::new(),
    out: Buffer::new(),
  }
}

///|
fn BooleanRun::intern(
  self : BooleanRun,
  key : FixedArray[Int32],
) -> Int32 raise WorkExhausted {
  let (id, added) = self.index.intern(key, self.work)
  if added {
    let width = self.program.nsym + 1
    self.work.spend(width + 2)
    self.states.push(
      { key, trans: FixedArray::make(width, UNKNOWN), },
      self.work,
    )
  }
  id
}

///|
fn BooleanRun::build(
  self : BooleanRun,
  state : BooleanState,
  column : Int32,
) -> Int32 raise WorkExhausted {
  // A build consumes units, so the public 10M allowance prevents stamp overflow.
  self.epoch += 1
  let epoch = self.epoch
  let program = self.program
  let ctx = state.key[0]
  let at_end = column == program.nsym
  let category = program.col_cat[column]
  self.out.clear(self.work)
  for i in 1..<state.key.length() {
    self.stack.push(state.key[i], self.work)
  }
  while self.stack.pop(self.work) is Some(node) {
    self.work.spend(1)
    if self.visited[node] == epoch {
      continue
    }
    self.visited[node] = epoch
    match program.nodes[node] {
      Tag(_, next) => self.stack.push(next, self.work)
      After(bit, next) =>
        if (ctx & (1 << bit)) != 0 {
          self.stack.push(next, self.work)
        }
      Before(expected, next) =>
        if category.intersects(expected) {
          self.stack.push(next, self.work)
        }
      Union(alternatives) =>
        for next in alternatives {
          self.stack.push(next, self.work)
        }
      Char(set, next) =>
        if !at_end && self.targeted[next] != epoch {
          self.work.spend(set.lookup_bound())
          if set.contains(column) {
            self.targeted[next] = epoch
            self.out.push(next, self.work)
          }
        }
      Accept => return BOOL_MATCH
    }
  }
  if self.out.length == 0 {
    return DEAD
  }
  self.work.spend(2 * self.out.length + 1)
  let key = FixedArray::make(self.out.length + 1, 0)
  key[0] = program.sym_ctx[column]
  for i in 0..<self.out.length {
    key[i + 1] = self.out.get(i)
  }
  self.intern(key)
}

///|
fn BooleanRun::step(
  self : BooleanRun,
  id : Int32,
  column : Int32,
) -> Int32 raise WorkExhausted {
  let state = self.states.get(id)
  let next = state.trans[column]
  if next != UNKNOWN {
    return next
  }
  let next = self.build(state, column)
  state.trans[column] = next
  next
}

///|
fn BooleanRun::search(
  self : BooleanRun,
  input : StringView,
) -> Bool raise WorkExhausted {
  self.work.spend(2)
  let mut state = self.intern([self.program.ctx_start, self.program.entry])
  for unit in input.code_units() {
    let column = self.program.table.map(unit.to_int())
    let next = self.step(state, column)
    if next == BOOL_MATCH {
      return true
    }
    if next == DEAD {
      return false
    }
    state = next
  }
  self.step(state, self.program.nsym) == BOOL_MATCH
}

///|
/// Used units never exceed `limit`. No mutable runner survives this call.
pub fn Program::matches(
  self : Program,
  input : StringView,
  limit : Int32,
) -> (Bool?, Int32) {
  let work : Work = { left: limit, }
  let result = try {
    work.spend(input.length())
    work.spend(1)
    Some(BooleanRun::new(self, work).search(input))
  } catch {
    WorkExhausted => None
  }
  (result, limit - work.left)
}
