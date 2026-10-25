$version: "2"
namespace example.payments

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcCancels
use smithy.rpc#jsonRpcLifecycle
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#jsonRpcRefersToCall
use smithy.rpc#jsonRpcSession
use smithy.rpc#method
use smithy.rpc#rpcError
use smithy.rpc#unknownMembers

/// A POS controls a terminal. All card values in this sample are masked test data.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "pos", accepts: PointOfSale }
        { name: "terminal", accepts: PaymentTerminal }
    ]
)
@jsonRpcSession(
    states: ["starting", "initializing", "ready", "paying", "stopping", "stopped"]
    capabilities: [
        { name: "payment", method: "terminal.initialize", pointer: "/capabilities/payment" }
        { name: "swipe", method: "terminal.initialize", pointer: "/capabilities/swipe" }
        { name: "chip", method: "terminal.initialize", pointer: "/capabilities/chip" }
        { name: "contactless", method: "terminal.initialize", pointer: "/capabilities/contactless" }
        { name: "pin", method: "terminal.initialize", pointer: "/capabilities/pin" }
        { name: "tips", method: "terminal.initialize", pointer: "/capabilities/tips" }
        { name: "signature", method: "terminal.initialize", pointer: "/capabilities/signature" }
        { name: "progress", method: "terminal.initialize", pointer: "/capabilities/progress" }
        { name: "cancellation", method: "terminal.initialize", pointer: "/capabilities/cancellation" }
    ]
    refusals: [{ states: ["starting", "initializing", "stopping", "stopped"], code: 1007 }]
    capabilityRefusal: 1008
)
structure TerminalProtocol {}

@jsonRpc(versions: ["2.0"])
@unknownMembers("ignore")
service PaymentTerminal {
    version: "1"
    operations: [
        Initialize, Initialized, Ping, StartPayment, PaymentStatus, RefundPayment,
        VoidPayment, GetReceipt, ListTransactions, Shutdown, Exit, CancelRequest
    ]
}

@jsonRpc(versions: ["2.0"])
@unknownMembers("ignore")
service PointOfSale {
    version: "1"
    operations: [PaymentProgress, ConfirmTip, RequestSignature, Display]
}

@method(name: "terminal.initialize", params: "named", kind: "request")
@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "initializing")
operation Initialize { input: InitializeInput, output: InitializeOutput }

structure InitializeInput {
    @required protocolVersion: ProtocolVersion
    @required posName: String
}

enum ProtocolVersion { V1 = "1" }

structure InitializeOutput {
    @required protocolVersion: ProtocolVersion
    @required terminalId: String
    @required capabilities: Capabilities
}

structure Capabilities {
    payment: Boolean
    swipe: Boolean
    chip: Boolean
    contactless: Boolean
    pin: Boolean
    tips: Boolean
    signature: Boolean
    progress: Boolean
    cancellation: Boolean
}

@method(name: "terminal.initialized", params: "named", kind: "notification")
@jsonRpcLifecycle(allowedIn: ["initializing"], onCall: "ready")
operation Initialized {}

/// Ping is valid in every session state.
@method(name: "terminal.ping", params: "named", kind: "request", nullResult: true)
operation Ping {}

@method(name: "payment.start", params: "named", kind: "request")
@jsonRpcLifecycle(allowedIn: ["ready"], onCall: "paying", onSuccess: "ready", onError: "ready", requires: ["payment"])
operation StartPayment {
    input: StartPaymentInput
    output: PaymentOutput
    errors: [CardDeclined, CardRemoved, TerminalBusy, Timeout]
}

structure StartPaymentInput {
    @required paymentId: PaymentId
    @required amount: Money
    @required entry: EntryMethod
}

@length(min: 1)
string PaymentId

structure Money {
    @required amount: Amount
    @required currency: Currency
}

@range(min: 0)
bigDecimal Amount

enum Currency {
    USD
    EUR
    GBP
}

union EntryMethod {
    swipe: TestCard
    chip: TestCard
    contactless: TestCard
    manualEntry: TestCard
}

/// A masked value is sufficient for this sample. Never send a real card number.
structure TestCard { @required maskedNumber: MaskedTestCard }

@pattern("^\\*\\*\\*\\* [0-9]{4}$")
string MaskedTestCard

structure PaymentOutput {
    @required paymentId: PaymentId
    @required outcome: PaymentOutcome
}

union PaymentOutcome {
    approved: Approved
    declined: Declined
    partiallyApproved: PartiallyApproved
}

structure Approved { @required authorizationCode: String }
structure Declined { @required reason: String }
structure PartiallyApproved { @required authorizedAmount: Money }

@method(name: "payment.status", params: "named", kind: "request", resultMember: "outcome")
@jsonRpcLifecycle(allowedIn: ["ready", "paying"])
operation PaymentStatus { input: PaymentIdInput, output: PaymentOutput, errors: [PaymentNotFound] }

structure PaymentIdInput { @required paymentId: PaymentId }

@method(name: "payment.refund", params: "named", kind: "request")
@jsonRpcLifecycle(allowedIn: ["ready"])
operation RefundPayment { input: RefundInput, output: RefundOutput, errors: [PaymentNotFound, RefundExceedsAmount] }

structure RefundInput { @required paymentId: PaymentId, @required amount: Money }
structure RefundOutput { @required refundId: String, @required amount: Money }

@method(name: "payment.void", params: "named", kind: "request", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["ready"])
operation VoidPayment { input: PaymentIdInput, errors: [PaymentNotFound] }

@method(name: "receipt.get", params: "named", kind: "request")
@jsonRpcLifecycle(allowedIn: ["ready"])
operation GetReceipt { input: PaymentIdInput, output: Receipt, errors: [PaymentNotFound] }

structure Receipt {
    @required paymentId: PaymentId
    @required merchant: Merchant
    @required lines: ReceiptLines
    @required total: Money
    customerCopy: Boolean
    footer: String
}
structure Merchant { @required name: String, address: String }
list ReceiptLines { member: ReceiptLine }
structure ReceiptLine { @required label: String, @required amount: Money }

@method(name: "transactions.list", params: "named", kind: "request")
@jsonRpcLifecycle(allowedIn: ["ready"])
operation ListTransactions { input: ListTransactionsInput, output: ListTransactionsOutput }

structure ListTransactionsInput { nextToken: String, since: Timestamp }
structure ListTransactionsOutput { @required transactions: Transactions, nextToken: String }
list Transactions { member: Transaction }
structure Transaction {
    @required paymentId: PaymentId
    @required createdAt: Timestamp
    @required amount: Money
    labels: Labels
}
map Labels { key: String, value: String }

@method(name: "terminal.shutdown", params: "named", kind: "request", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["ready"], onSuccess: "stopping")
operation Shutdown {}

@method(name: "terminal.exit", params: "named", kind: "notification")
@jsonRpcLifecycle(allowedIn: ["stopping"], onCall: "stopped")
operation Exit {}

@method(name: "$/cancelRequest", params: "named", kind: "notification")
@jsonRpcLifecycle(allowedIn: ["paying"], requires: ["cancellation"])
@jsonRpcCancels(idMember: "id", code: -32800)
operation CancelRequest { input: CancelRequestInput }
structure CancelRequestInput { @required id: Document }

@method(name: "payment.progress", params: "named", kind: "notification")
@jsonRpcLifecycle(allowedIn: ["paying"], requires: ["progress"])
@jsonRpcRefersToCall(idMember: "requestId")
operation PaymentProgress { input: PaymentProgressInput }
structure PaymentProgressInput { @required requestId: Document, @required phase: PaymentPhase }
enum PaymentPhase {
    INSERT_CARD = "insertCard"
    ENTER_PIN = "enterPin"
    AUTHORIZING = "authorizing"
}

@method(name: "pos.confirmTip", params: "named", kind: "request", resultMember: "accepted")
@jsonRpcLifecycle(allowedIn: ["paying"], requires: ["tips"])
operation ConfirmTip { input: ConfirmTipInput, output: ConfirmTipOutput }
structure ConfirmTipInput { @required paymentId: PaymentId, @required amount: Money }
structure ConfirmTipOutput { @required accepted: Boolean }

@method(name: "pos.requestSignature", params: "named", kind: "request", resultMember: "signature")
@jsonRpcLifecycle(allowedIn: ["paying"], requires: ["signature"])
operation RequestSignature { input: RequestSignatureInput, output: RequestSignatureOutput }
structure RequestSignatureInput { @required paymentId: PaymentId, @required prompt: String }
structure RequestSignatureOutput { @required signature: Blob }

@method(name: "pos.display", params: "named", kind: "notification")
@jsonRpcLifecycle(allowedIn: ["ready", "paying"])
operation Display { input: DisplayInput }
structure DisplayInput { @required message: String }

@error("client")
@rpcError(code: 1001, dataMember: "reason")
structure CardDeclined { @required reason: String }

@error("client")
@rpcError(code: 1002, absentData: true)
structure CardRemoved {}

@error("server")
@rpcError(code: 1003)
structure TerminalBusy { @required retryAfterSeconds: Integer }

@error("server")
@rpcError(code: 1004, absentData: true)
structure Timeout {}

@error("client")
@rpcError(code: 1005)
structure PaymentNotFound { @required paymentId: PaymentId }

@error("client")
@rpcError(code: 1006)
structure RefundExceedsAmount { @required paymentId: PaymentId, @required maximum: Money }
