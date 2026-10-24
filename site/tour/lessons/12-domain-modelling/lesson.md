# Domain modelling in Smithy

This lesson puts the earlier lessons together. The model describes the orders of a small shop. Each rule of the domain becomes a shape or a trait:

- An order ID is `ORD-` and five digits. The trait `@pattern` on `OrderId` gives this rule.
- An order is in one of four states. The enum `OrderState` gives the states.
- A customer pays with a card or with an invoice, never with both. The union `PaymentMethod` holds exactly one of them.
- An invoice payment holds no data, so the member `invoice` targets `Unit`.
- An order has an ID, a state, a payment method and lines. The trait `@required` on each member gives this rule.
- An order has one or more lines. The trait `@length(min: 1)` on `lines` gives this rule.
- The quantity of a line is from 1 to 99. The trait `@range` on `Quantity` gives this rule.
- A new order is in the state `PLACED`. The default value of `state` gives this rule.

Look at the JSON Schema output. The rules are also in the schema. The list `required` of `Order` contains the four members. The property `id` has the `pattern`. `OrderState` has an `enum` list of the four states. The property `quantity` has `minimum` and `maximum`. The property `lines` has `"minItems": 1`. The property `state` refers to `OrderState` and has `"default": "PLACED"`.

Smithy also checks the default values in the model against the shapes. Now change the default value of `state` from `"PLACED"` to `"NEW"`. The Findings tab shows an error with the event ID `DefaultTrait`. The value `"NEW"` is not a value of the enum `OrderState`. Change it back.
