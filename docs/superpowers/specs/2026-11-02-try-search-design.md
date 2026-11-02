# Non-raising expression search

## Intent and scope

Implement [issue #30](https://github.com/svyatov/jmespath-ruby/issues/30) for integrations that display query failures.
Add `Expression#try_search` with the inputs and evaluation options accepted by `search`.
Distinguish successful null results from failures without evaluating twice.
Preserve the replacement contract, standard JMESPath semantics, and ordinary `search` behavior.

This is a bounded change with a short design.
A generic result framework, source compilation through `try_search`, and additional dependencies are outside scope.
Broad exception capture, repeated conversions, and shared capture state between calls are unacceptable outcomes.

## Approaches

The user selected A1: scoped error capture with application calls excluded from capture.
A private execution context holds ownership information for one `try_search` invocation.
This preserves internal method signatures but requires reliable scope restoration and application-call classification.

A2 passes an explicit context through plans, evaluators, functions, conversions, and input loading.
It makes state visible in each interface but changes many internal interfaces for one public method.
A1 limits those interface changes while retaining both evaluation paths.

The user selected O1: exceptions escaping application callbacks propagate unchanged.
This includes library errors raised by nested ordinary queries inside those callbacks.
O2 would capture those nested failures, conflicting with the callback rule in the issue.

## Public contract

My proposed public type is `JMESPath::SearchResult`, with readers `success?`, `value`, and `error`.
The result container is frozen; it does not copy or freeze the value or error.
Successful null, false, and ordinary values all have `success? == true` and `error == nil`.
A failure has `success? == false`, `value == nil`, and the original exception as `error`.
Preserve successful object identity and exception identity, metadata, and backtrace.
No extra result methods or public construction interface are required.

Validate evaluation options before input access and error capture.
Invalid options propagate as `ArgumentError`.
Configured expressions and per-call overrides retain the behavior of `search`.
Suppressed validation failures remain successful null results.

## Error ownership

Capture library-owned evaluation failures, including type, arity, unknown-function, invalid-value, and per-call nesting-limit failures.
Capture JSON parsing failures from library input loading.
Capture native file and stream failures from input operations performed by the library.
Caller-owned streams remain open; owned files close on success and failure.

Application function callbacks, registry dispatch overrides, and conversion methods execute outside the active capture context.
Exceptions escaping those calls propagate, including JSON errors and application-raised instances of library error classes.
Application overrides of input methods follow the same propagation rule; native input failures remain eligible for capture.
Unrelated exceptions propagate without conversion into failure results.

Identify provenance during the original execution, without rerunning evaluation or conversions.
Do not infer ownership from exception class, message, or backtrace alone.
Do not mutate exception objects to store ownership.
Record ownership by exception identity in the invocation context at eligible failure sites.
Record exceptions escaping application calls as excluded from that invocation, even if previously recorded as library-owned.
Exclusion takes precedence over ownership.
This prevents an exception from becoming capturable merely because a callback scope has restored capture before unwinding finishes.

Audit both the compiled plan and evaluator, including function references, built-ins, normalization, and input loading.
Retain validation suppression and custom registry dispatch order.
Keep rescue scopes around native I/O and JSON parsing narrow enough to preserve application exceptions.

## Context lifecycle

My proposed storage is private, fiber-local state using Ruby's supported thread-local indexing interface.
Each invocation owns a fresh context and restores the previous context in `ensure`.
Threads and fibers do not share mutable capture records.
Application calls suspend the outer context and restore it on every exit.
A nested `try_search` creates its own context, including when called inside an application callback.
An ordinary query inside an application callback executes without the outer capture context.
Completed scopes release exception references and retain no input documents.
No capture state is stored on expressions, plans, registries, or shared evaluators.
Ordinary calls avoid allocating capture records.

## Validation and documentation

Add focused regression tests before implementation through the public interface.
Cover successful null, false, object identity, suppression, every captured failure category, and invalid options before input access.
Cover callback and conversion exceptions, including library and JSON classes, preserved identity, backtrace, and single conversion counts.
Cover native input failures, overridden input methods, file closure, and caller-owned stream lifetime.
Cover nested ordinary queries, nested `try_search`, function references, configured expressions, overrides, and both evaluation paths.
Verify restoration after failures and interleaved calls across threads and fibers.
Include exception reuse across calls and re-raising through application code to detect stale ownership.

Update public RBS, YARD, executable examples, and the relevant query and error guides.
The CLI receives no result mode or new flag; review help for relevant shared guidance.
Preserve imported compliance fixtures and dependency versions.
Run `bundle exec rake` and `bundle exec rake docs` before declaring implementation complete.

## Builder decisions

The builder chooses private helper names, file layout, and the narrowest eligible failure sites.
The builder must verify that application exceptions survive enclosing built-in rescue handlers unchanged.
Any need to change the public contract or replace A1 requires another design decision.
