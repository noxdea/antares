# ADR 003: Select language structure providers by lexer tag

- Status: Accepted
- Date: 2026-09-15

## Context

Rouge tokens provide a useful generic structure tree, but language parsers can
produce more precise regions. Parser dependencies do not belong in Antares.

## Decision

`Structure.register(language, provider)` associates a provider factory with a
case-insensitive Rouge lexer tag. `Highlighter#structure` selects the factory
once, when it lazily creates its structure. The factory receives the same line,
token, and stabilization callbacks as `Structure.new`; its result must implement
the public structure query methods and `edit`. `Structure.unregister` supports
application teardown and isolated tests.

## Consequences

- Existing and unregistered languages keep the generic derivation.
- A registered provider receives every later `Highlighter#edit` notification.
- Applications can opt into parser-backed accuracy without adding that parser
  to Antares' dependency graph.
- Changing a registration does not replace already-created structure objects.
