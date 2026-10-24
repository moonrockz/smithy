# Reading findings

Smithy validates the model and reports validation events. The Findings tab shows each event in one row, with these parts:

- the severity;
- the event ID;
- the place: the file, the line and the column;
- the message.

There are four [severities](https://smithy.io/2.0/spec/model-validation.html#severity):

- `ERROR`: something is structurally wrong with the model. You cannot suppress an error.
- `DANGER`: something is very likely wrong. An unsuppressed `DANGER` event makes the model invalid.
- `WARNING`: something can be wrong.
- `NOTE`: information only. It does not show a problem.

This model has one `WARNING`. The shape `Fahrenheit` has the trait `@deprecated`, and the member `temperature` targets it. The event ID is `DeprecatedShape.example#Fahrenheit`. The event is on the member `example#Reading$temperature`.

An event ID that contains dots is hierarchical. A dot separates its segments. A suppression ID [matches](https://smithy.io/2.0/spec/model-validation.html#matching-suppression-event-ids) each event ID that starts with the same segments. For example, the suppression ID `DeprecatedShape` matches the event ID `DeprecatedShape.example#Fahrenheit`.

Now suppress the warning. Put this line directly before the line `temperature: Fahrenheit`:

```smithy
@suppress(["DeprecatedShape"])
```

The trait [`@suppress`](https://smithy.io/2.0/spec/model-validation.html#suppress-trait) suppresses the events with these IDs on its shape. The Findings tab still lists the event, marked `SUPPRESSED`. The specification defines four severities, and `SUPPRESSED` is not one of them. It tells you that a suppression matched the event. The model has no warning now.

To suppress events in a full namespace or in the full model, use the [metadata `suppressions`](https://smithy.io/2.0/spec/model-validation.html#suppression-metadata).
