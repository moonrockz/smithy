$version: "2"
namespace smithy.serialization

/// Named JSON representation profiles. A profile applies to the declaring shape and to every
/// shape reachable from it.
@trait(selector: ":is(structure, union, list, map)")
@length(min: 1)
list jsonProfiles {
    member: ProfileDeclaration
}

structure ProfileDeclaration {
    @required
    id: ProfileId
    documentation: String
    /// Use the rules declared under another profile, for example with another writer mode.
    ruleSet: ProfileId
    /// canonical (default) or expanded.
    writer: RuleName
    /// reject (default) or ignore.
    unknownMembers: RuleName
    defaults: ProfileDefaults
    /// Capabilities that a runtime must implement to prepare this profile.
    requires: RuleNames
}

structure ProfileDefaults {
    union: UnionRule
    dictionary: DictionaryRule
}

/// Representation rules of a shape or member: a base rule and rules for named profiles.
@trait(selector: ":is(structure, union, list, map, simpleType, member)")
structure jsonEncoding {
    base: ShapeRule
    profiles: ProfileRules
}

map ProfileRules {
    key: ProfileId
    value: ShapeRule
}

structure ShapeRule {
    union: UnionRule
    tuple: TupleRule
    dictionary: DictionaryRule
    adapter: AdapterId
    name: WireName
    tag: WireName
    aliases: WireNames
    /// omit (default) or null: how an absent optional member is written. A reader treats null
    /// as absence for a member with the null policy.
    absent: RuleName
    /// Read the fields that no other member claims as this member's external union.
    flatten: Boolean
    forms: FormRules
}

structure UnionRule {
    /// external, internal, adjacent, tagArray or untagged.
    @required
    style: RuleName
    tag: WireName
    content: WireName
    /// tagArray: tagOnly (default) or slot.
    unit: RuleName
    /// Reader-only alternative object layouts.
    accept: UnionRules
}

list UnionRules {
    member: UnionRule
}

structure TupleRule {
    @required
    members: MemberNames
    rest: MemberName
    /// omit or null, for optional trailing positions.
    optional: RuleName
}

structure DictionaryRule {
    /// object or entries.
    @required
    layout: RuleName
    key: AdapterId
    /// key (default), adapter or preserve (the order of the input or of the caller's value).
    order: RuleName
    /// The other layout, which readers also accept.
    accept: RuleNames
}

list FormRules {
    member: FormRule
}

/// A compact form: a reader guard, the members that it binds and an optional writer guard.
structure FormRule {
    member: MemberName
    @required
    read: ReadGuard
    bind: MemberName
    positions: MemberNames
    rest: MemberName
    write: WriteGuard
}

structure ReadGuard {
    @required
    kind: RuleName
    adapter: AdapterId
    /// The object must contain this field.
    field: WireName
    /// The object must not contain this field.
    absent: WireName
}

structure WriteGuard {
    empty: MemberNames
    present: MemberNames
}

/// Select a union member by the JSON kind of its value.
@trait(selector: "union")
structure untagged {}

/// An empty value of this optional member is the same logical value as its absence.
@trait(selector: "structure > member :not([trait|required])")
structure emptyAsAbsent {}

/// A versioned document bundle: where its version is, and the root and profiles of each release.
@trait(selector: "structure")
structure jsonBundle {
    @required
    id: BundleId
    @required
    version: VersionLocation
    @required
    releases: ReleaseBindings
}

structure VersionLocation {
    @required
    field: WireName
    @required
    adapter: AdapterId
}

@length(min: 1)
list ReleaseBindings {
    member: ReleaseBinding
}

structure ReleaseBinding {
    @required
    since: ReleaseText
    @required
    until: ReleaseText
    @required
    root: RootRef
    @required
    profiles: ProfileIds
}

@idRef(failWhenMissing: true, selector: ":is(structure, union)")
string RootRef

@pattern("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
string ReleaseText

@pattern("^[a-z][a-z0-9]*([.-][a-z0-9]+)*$")
@length(min: 1, max: 64)
string ProfileId

@length(min: 1)
list ProfileIds {
    member: ProfileId
}

@pattern("^[a-z][a-z0-9]*([.-][a-z0-9]+)*$")
@length(min: 1, max: 64)
string AdapterId

@pattern("^[a-z][a-z0-9]*([.-][a-z0-9]+)*$")
@length(min: 1, max: 64)
string BundleId

@pattern("^[a-z][A-Za-z0-9]*$")
string RuleName

list RuleNames {
    member: RuleName
}

@length(min: 1, max: 1024)
string WireName

list WireNames {
    member: WireName
}

@pattern("^[A-Za-z_][A-Za-z0-9_]*$")
string MemberName

list MemberNames {
    member: MemberName
}