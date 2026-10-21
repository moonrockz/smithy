///|
pub struct PreparedValidator {
  priv core : @validation.PreparedValidator
}

///|
pub fn PreparedValidator::prepare(
  model : @smithy.Model,
  shape : @smithy.ShapeId,
  config~ : @validation.Config = @validation.Config::new(),
) -> PreparedValidator raise @validation.PreparationError {
  {
    core: @validation.PreparedValidator::prepare(
      model,
      shape,
      config=config.with_profile(@validation.NativeProfile),
    ),
  }
}

///|
pub fn PreparedValidator::validate(
  self : PreparedValidator,
  value : @ion.Ion,
) -> ValidationResult {
  let kinds : Map[@validation.InstancePath, @ion.IonType] = Map([])
  let view = IonView::new(value, @validation.InstancePath::root(), kinds)
  let result = self.core.validate(view)
  {
    findings: result.findings.map(f => {
      let native_kind = if f.code == @validation.RequiredMember {
        None
      } else if f.path.steps().last()
        is Some(@validation.MapKey(_, _) | @validation.FieldNamePosition(_)) {
        Some(@ion.IonType::Symbol)
      } else {
        kinds.get(f.path)
      }
      {
        code: f.code,
        severity: f.severity,
        path: f.path,
        shape: f.shape,
        message: f.message,
        native_kind,
      }
    }),
    complete: result.complete,
  }
}

///|
priv struct IonView {
  value : @ion.Ion
  path : @validation.InstancePath
  kinds : Map[@validation.InstancePath, @ion.IonType]
  bare : Bool
}

///|
fn IonView::new(
  value : @ion.Ion,
  path : @validation.InstancePath,
  kinds : Map[@validation.InstancePath, @ion.IonType],
) -> IonView {
  kinds.set(path, value.ion_type())
  { value, path, kinds, bare: false, }
}

///|
fn native_kind(kind : @ion.IonType) -> @validation.NativeKind {
  match kind {
    Null => @validation.NullKind
    Bool => @validation.BoolKind
    Int => @validation.IntKind
    Float => @validation.FloatKind
    Decimal => @validation.DecimalKind
    Timestamp => @validation.TimestampKind
    Symbol => @validation.SymbolKind
    String => @validation.StringKind
    Blob => @validation.BlobKind
    Clob => @validation.ClobKind
    Struct => @validation.StructKind
    List => @validation.ListKind
    Sexp => @validation.SexpKind
  }
}

///|
fn decimal_number(value : @ion.Decimal) -> @smithy.NodeNumber? {
  let coefficient = if value.is_negative_zero() {
    "-0"
  } else {
    value.coefficient().to_string()
  }
  @smithy.NodeNumber::parse(coefficient + "e" + value.exponent().to_string())
}

///|
fn timestamp_scalar(value : @ion.Timestamp) -> @validation.NativeScalar {
  let fraction = match value.fraction() {
    Some(decimal) =>
      match decimal_number(decimal) {
        Some(number) => Some(number)
        None => return @validation.InvalidTimestamp
      }
    None => None
  }
  let offset = match value.offset() {
    Some(@ion.Known(minutes)) => @validation.KnownOffsetMinutes(minutes)
    Some(@ion.Unknown) | None => @validation.UnknownOffset
  }
  let timestamp = @validation.NativeTimestamp::new(
    value.year(),
    month=value.month(),
    day=value.day(),
    hour=value.hour(),
    minute=value.minute(),
    second=value.second(),
    fraction~,
    offset~,
  ) catch {
    _ => return @validation.InvalidTimestamp
  }
  @validation.Timestamp(timestamp)
}

///|
impl @validation.ValueView for IonView with fn expansion_size(self) {
  let children = match self.value.kind() {
    List(values) | Sexp(values) => values.length()
    Struct(fields) => fields.length()
    _ => 0
  }
  let annotations = if self.bare {
    0
  } else {
    self.value.annotations().length()
  }
  if children > annotations {
    children
  } else {
    annotations
  }
}

///|
impl @validation.ValueView for IonView with fn inspect(self) {
  if !self.bare && self.value.has_annotations() {
    return @validation.Annotated(
      self.value.annotations().map(token => token.text()),
      { ..self, bare: true, },
    )
  }
  match self.value.kind() {
    Null(kind) => @validation.Native(@validation.TypedNull(native_kind(kind)))
    Bool(value) => @validation.Boolean(value)
    Int(value) =>
      match @smithy.NodeNumber::parse(value.to_string()) {
        Some(number) => @validation.Number(number)
        None => @validation.InvalidNumber
      }
    Float(value) => @validation.Native(@validation.Float(value))
    Decimal(value) =>
      match decimal_number(value) {
        Some(number) => @validation.Native(@validation.Decimal(number))
        None => @validation.InvalidNumber
      }
    Timestamp(value) => @validation.Native(timestamp_scalar(value))
    Symbol(token) => @validation.Native(@validation.Symbol(token.text()))
    String(value) => @validation.String(value)
    Blob(value) => @validation.Native(@validation.Blob(value))
    Clob(value) => @validation.Native(@validation.Clob(value))
    List(values) =>
      @validation.Array(
        values.mapi((index, value) => {
          IonView::new(
            value,
            self.path.index(index) catch {
              _ => self.path
            },
            self.kinds,
          )
        }),
      )
    Sexp(values) =>
      @validation.Sexp(
        values.mapi((index, value) => {
          IonView::new(
            value,
            self.path.index(index) catch {
              _ => self.path
            },
            self.kinds,
          )
        }),
      )
    Struct(fields) => {
      let occurrences : Map[String, Int32] = Map([])
      @validation.NativeObject(
        fields.mapi((position, field) => {
          let name = field.name().text()
          let path = match name {
            Some(name) => {
              let occurrence = occurrences.get(name).unwrap_or(0)
              occurrences.set(name, occurrence + 1)
              self.path.field(name, occurrence~) catch {
                _ => self.path
              }
            }
            None => self.path.field_position(position) catch { _ => self.path }
          }
          (name, IonView::new(field.value(), path, self.kinds))
        }),
      )
    }
  }
}
