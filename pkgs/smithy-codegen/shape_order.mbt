///|
/// The shapes that a shape refers to. Traits are not edges. A container refers
/// to its member shapes, and a member refers to its target.
fn edges(shape : @smithy.Shape) -> Array[@smithy.ShapeId] {
  match shape.body {
    Member(target~) => [target]
    Operation(input~, output~, errors~) => [input, output] + errors
    Service(operations~, resources~, errors~, ..) =>
      operations + resources + errors
    Resource(
      identifiers~,
      properties~,
      create~,
      put~,
      read~,
      update~,
      delete~,
      list~,
      operations~,
      collectionOperations~,
      resources~
    ) => {
      let out = identifiers.values().to_array() +
        properties.values().to_array() +
        operations +
        collectionOperations +
        resources
      for id in [create, put, read, update, delete, list] {
        if id is Some(id) {
          out.push(id)
        }
      }
      out
    }
    Structure(ids) | Union(ids) | Enum(ids) | IntEnum(ids) => ids
    List(id) => [id]
    Map(key~, value~) => [key, value]
    Simple(_) => []
  }
}

///|
fn compare_ids(a : @smithy.ShapeId, b : @smithy.ShapeId) -> Int32 {
  a.to_string().lexical_compare(b.to_string())
}

///|
/// The service and every shape that it reaches through members, operations,
/// errors and resources. Traits are not followed. A shape that the model does
/// not hold is skipped. The result is sorted by shape ID text. The walk uses an
/// explicit stack.
pub fn service_closure(
  model : @smithy.Model,
  service : @smithy.ShapeId,
) -> Array[@smithy.ShapeId] {
  let seen : Set[@smithy.ShapeId] = Set([])
  let found : Array[@smithy.ShapeId] = []
  let stack = [service]
  while stack.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen.add(id)
    if model.shapes.get(id) is Some(shape) {
      found.push(id)
      stack.append(edges(shape))
    }
  }
  found.sort_by(compare_ids)
  found
}

///|
/// Push a key on a binary min-heap.
fn heap_push(heap : Array[Int32], key : Int32) -> Unit {
  heap.push(key)
  let mut i = heap.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if heap[parent] <= heap[i] {
      break
    }
    let tmp = heap[parent]
    heap[parent] = heap[i]
    heap[i] = tmp
    i = parent
  }
}

///|
/// Remove the smallest key of a binary min-heap.
fn heap_pop(heap : Array[Int32]) -> Int32? {
  guard !heap.is_empty() else { return None }
  let top = heap[0]
  let last = heap.pop().unwrap()
  if !heap.is_empty() {
    heap[0] = last
    let n = heap.length()
    let mut i = 0
    while true {
      let left = 2 * i + 1
      let right = left + 1
      let mut smallest = i
      if left < n && heap[left] < heap[smallest] {
        smallest = left
      }
      if right < n && heap[right] < heap[smallest] {
        smallest = right
      }
      if smallest == i {
        break
      }
      let tmp = heap[smallest]
      heap[smallest] = heap[i]
      heap[i] = tmp
      i = smallest
    }
  }
  Some(top)
}

///|
/// Find the strongly connected components with an iterative Tarjan walk.
/// Return the component number of each node and the node count of each
/// component.
fn components(deps : Array[Array[Int32]]) -> (Array[Int32], Array[Int32]) {
  let n = deps.length()
  let index = Array::make(n, -1)
  let low = Array::make(n, 0)
  let on_stack = Array::make(n, false)
  let comp = Array::make(n, -1)
  let sizes : Array[Int32] = []
  let scc : Array[Int32] = []
  let mut counter = 0
  for root in 0..<n {
    if index[root] != -1 {
      continue
    }
    // Each frame is a node and the position of its next edge.
    let frames : Array[(Int32, Int32)] = [(root, 0)]
    index[root] = counter
    low[root] = counter
    counter += 1
    scc.push(root)
    on_stack[root] = true
    while frames.length() > 0 {
      let (node, position) = frames[frames.length() - 1]
      if position < deps[node].length() {
        frames[frames.length() - 1] = (node, position + 1)
        let next = deps[node][position]
        if index[next] == -1 {
          index[next] = counter
          low[next] = counter
          counter += 1
          scc.push(next)
          on_stack[next] = true
          frames.push((next, 0))
        } else if on_stack[next] {
          low[node] = low[node].min(index[next])
        }
      } else {
        frames.pop() |> ignore
        if low[node] == index[node] {
          let id = sizes.length()
          let mut size = 0
          while scc.pop() is Some(member) {
            on_stack[member] = false
            comp[member] = id
            size += 1
            if member == node {
              break
            }
          }
          sizes.push(size)
        }
        if frames.last() is Some((parent, _)) {
          low[parent] = low[parent].min(low[node])
        }
      }
    }
  }
  (comp, sizes)
}

///|
/// Order shapes so that a shape comes after the shapes that it refers to.
/// Every input ID appears once. A container refers to its members, and a
/// member refers to its target. When a member is not in the input, the
/// container refers to the target of that member. Shapes in a cycle
/// come after the other shapes that are ready at the same time, in name order.
/// Ties go to the smaller shape ID text. The model gives no edges to a shape
/// that it does not hold. No step recurses.
pub fn topological_order(
  model : @smithy.Model,
  ids : Array[@smithy.ShapeId],
) -> Array[@smithy.ShapeId] {
  let nodes : Array[@smithy.ShapeId] = []
  let seen : Set[@smithy.ShapeId] = Set([])
  for id in ids {
    if seen.add_and_check(id) {
      nodes.push(id)
    }
  }
  nodes.sort_by(compare_ids)
  let n = nodes.length()
  let position : Map[@smithy.ShapeId, Int32] = Map([])
  for i, id in nodes {
    position[id] = i
  }
  // deps[i] holds the sorted node numbers that node i refers to.
  let deps : Array[Array[Int32]] = []
  for id in nodes {
    let out : Array[Int32] = []
    if model.shapes.get(id) is Some(shape) {
      for edge in edges(shape) {
        // A member that is not in the input stands for its target.
        // The step limit stops a malformed chain of members.
        let mut target = edge
        let mut steps = 0
        while steps < 8 &&
              !position.contains(target) &&
              model.shapes.get(target)
              is Some({ body: Member(target=next), .. }) {
          target = next
          steps += 1
        }
        if position.get(target) is Some(j) {
          out.push(j)
        }
      }
      out.sort()
    }
    deps.push(out)
  }
  let (comp, sizes) = components(deps)
  let count = sizes.length()
  let cyclic = Array::make(count, false)
  for i in 0..<n {
    if sizes[comp[i]] > 1 || deps[i].contains(i) {
      cyclic[comp[i]] = true
    }
  }
  // Nodes are sorted, so the first node of a component has the smallest name.
  let members : Array[Array[Int32]] = Array::makei(count, _ => [])
  for i in 0..<n {
    members[comp[i]].push(i)
  }
  let waiting = Array::make(count, 0)
  let dependents : Array[Array[Int32]] = Array::makei(count, _ => [])
  for i in 0..<n {
    for j in deps[i] {
      if comp[i] != comp[j] {
        waiting[comp[i]] += 1
        dependents[comp[j]].push(comp[i])
      }
    }
  }
  // The key is the rank of the first node, plus n for a cycle, so that a cycle
  // only wins when no other component is ready.
  let by_key : Array[Int32] = Array::make(2 * n, -1)
  let key_of = c => members[c][0] + (if cyclic[c] { n } else { 0 })
  let heap : Array[Int32] = []
  for c in 0..<count {
    if waiting[c] == 0 {
      by_key[key_of(c)] = c
      heap_push(heap, key_of(c))
    }
  }
  let out : Array[@smithy.ShapeId] = []
  while heap_pop(heap) is Some(key) {
    let c = by_key[key]
    for i in members[c] {
      out.push(nodes[i])
    }
    for d in dependents[c] {
      waiting[d] -= 1
      if waiting[d] == 0 {
        by_key[key_of(d)] = d
        heap_push(heap, key_of(d))
      }
    }
  }
  out
}
