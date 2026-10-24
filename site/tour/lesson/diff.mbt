///|
/// The most lines of an output that `changed_lines` compares. The work grows
/// with the square of the lines that changed, so a larger output gets no
/// highlight.
pub const MAX_DIFF_LINES : Int32 = 2000

///|
fn lines_of(text : String) -> Array[String] {
  text.split("\n").map(line => line.to_owned()).to_array()
}

///|
/// The lines of `after`, from 1, that are not in a longest common
/// subsequence of the lines of `before` and `after`: the lines that an edit
/// added or changed. An empty `before` (no output yet) and an output of
/// more than `MAX_DIFF_LINES` lines give no lines.
pub fn changed_lines(before : String, after : String) -> Array[Int32] {
  if before == "" || before == after {
    return []
  }
  let a = lines_of(before)
  let b = lines_of(after)
  if a.length() > MAX_DIFF_LINES || b.length() > MAX_DIFF_LINES {
    return []
  }
  // The common lines at the start and at the end are in the subsequence.
  let mut start = 0
  while start < a.length() && start < b.length() && a[start] == b[start] {
    start += 1
  }
  let mut end_a = a.length()
  let mut end_b = b.length()
  while end_a > start && end_b > start && a[end_a - 1] == b[end_b - 1] {
    end_a -= 1
    end_b -= 1
  }
  let n = end_a - start
  let m = end_b - start
  // lcs[i * (m + 1) + j]: the length of a longest common subsequence of the
  // lines from `start + i` of `a` and from `start + j` of `b`.
  let width = m + 1
  let lcs : FixedArray[Int32] = FixedArray::make((n + 1) * width, 0)
  for i = n - 1; i >= 0; i = i - 1 {
    for j = m - 1; j >= 0; j = j - 1 {
      lcs[i * width + j] = if a[start + i] == b[start + j] {
        lcs[(i + 1) * width + j + 1] + 1
      } else {
        let down = lcs[(i + 1) * width + j]
        let right = lcs[i * width + j + 1]
        if down >= right {
          down
        } else {
          right
        }
      }
    }
  }
  let changed = []
  let mut i = 0
  let mut j = 0
  while j < m {
    if i < n && a[start + i] == b[start + j] {
      i += 1
      j += 1
    } else if i < n && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1] {
      i += 1
    } else {
      changed.push(start + j + 1)
      j += 1
    }
  }
  changed
}
