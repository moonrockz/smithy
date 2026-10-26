///|
/// A member name and its constraints after value preparation.
pub struct ValueMemberContract {
  shape : @smithy.ShapeId
  wire_name : String
  required : Bool
  critical_separator : String?
} derive(Eq, Debug)

///|
/// The effective policy and member names of a prepared structure.
pub struct StructureContract {
  shape : @smithy.ShapeId
  unknown_members : UnknownMembers
  members : Array[ValueMemberContract]
} derive(Eq, Debug)

///|
/// Return detached structure contracts in lexical shape order.
/// Member shapes use the contract of their target structure.
pub fn PreparedValidator::structure_contracts(
  self : PreparedValidator,
) -> Array[StructureContract] {
  let out : Array[StructureContract] = []
  let seen : Set[@smithy.ShapeId] = Set([])
  for _, shape in self.shapes {
    let id = shape.value_shape
    guard shape.body is Structure(_) && !seen.contains(id) else { continue }
    seen.add(id)
    let members = shape.members.map(member_ => {
      shape: member_.id,
      wire_name: member_.name,
      required: member_.required,
      critical_separator: self.critical_paths(member_.id),
    })
    members.sort_by((a, b) => a.wire_name.lexical_compare(b.wire_name))
    out.push({ shape: id, unknown_members: shape.unknown_members, members, })
  }
  out.sort_by((a, b) => a.shape.to_string().lexical_compare(b.shape.to_string()))
  out
}
