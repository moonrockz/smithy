$version: "2"

namespace morphir.sdk.string

use morphir.dsl#function
use morphir.dsl#sdkModule
use morphir.dsl#sdkType
use morphir.sdk.basics#Bool
use morphir.sdk.basics#Int

@sdkType(name: "string")
string String

@sdkModule(package: "morphir/SDK", module: "string")
service StringModule {
    operations: [IsEmpty, Length, Append]
}

/// isEmpty : String -> Bool
@function(name: "is-empty", native: true)
operation IsEmpty {
    input := {
        @required
        s: String
    }

    output := {
        @required
        result: Bool
    }
}

/// length : String -> Int
@function(name: "length", native: true)
operation Length {
    input := {
        @required
        s: String
    }

    output := {
        @required
        result: Int
    }
}

/// append : String -> String -> String
@function(name: "append", native: true)
operation Append {
    input := {
        @required
        s1: String

        @required
        s2: String
    }

    output := {
        @required
        result: String
    }
}
