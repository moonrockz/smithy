$version: "2"

namespace morphir.dsl

use morphir.ir.v4#Name
use morphir.ir.v4#Path

/// Marks a service as a module of a Morphir SDK package.
@trait(selector: "service")
structure sdkModule {
    /// The package, such as "morphir/SDK".
    @required
    package: Path

    /// The module in the package, such as "basics".
    @required
    module: Path
}

/// Marks a simple shape as a type of an SDK module.
@trait(selector: "simpleType")
structure sdkType {
    /// The type name in its module, such as "int".
    @required
    name: Name
}

/// Marks an operation as a function of an SDK module. The input members are
/// the parameters in order. The output member `result` is the return value.
@trait(selector: "operation")
structure function {
    /// The function name in its module, such as "is-empty".
    @required
    name: Name

    /// The backend gives the implementation.
    native: Boolean
}

/// The member has the type variable with this name, such as `number`.
@trait(selector: "structure > member")
@pattern("^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
string typeVariable
