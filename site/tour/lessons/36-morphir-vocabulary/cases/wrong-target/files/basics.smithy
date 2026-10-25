$version: "2"

namespace morphir.sdk.basics

use morphir.dsl#function
use morphir.dsl#sdkModule
use morphir.dsl#sdkType
use morphir.dsl#typeVariable

@sdkType(name: "int")
long Int

@sdkType(name: "float")
double Float

@sdkType(name: "bool")
boolean Bool

@sdkType(name: "basics")
service Basics {
    operations: [Add, Negate, And]
}

/// add : number -> number -> number
@function(name: "add", native: true)
operation Add {
    input := {
        @required
        @typeVariable("number")
        a: Document

        @required
        @typeVariable("number")
        b: Document
    }

    output := {
        @required
        @typeVariable("number")
        result: Document
    }
}

/// negate : number -> number
@function(name: "negate", native: true)
operation Negate {
    input := {
        @required
        @typeVariable("number")
        a: Document
    }

    output := {
        @required
        @typeVariable("number")
        result: Document
    }
}

/// and : Bool -> Bool -> Bool
@function(name: "and", native: true)
operation And {
    input := {
        @required
        a: Bool

        @required
        b: Bool
    }

    output := {
        @required
        result: Bool
    }
}
