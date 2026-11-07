// Added for moonrockz/regex.

///|
/// A constant-time upper bound on the nodes examined by `contains`.
pub fn RecharSet::lookup_bound(self : RecharSet) -> Int32 {
  nw(self.0)
}
