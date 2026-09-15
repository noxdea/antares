# ADR 004: Interpret a bounded tmLanguage subset

- Status: Accepted
- Date: 2026-09-15

## Context

Rouge does not cover every language used by editors. TextMate grammars are a
common interchange format, but they contain recursive references and untrusted
regular expressions. Loading them as generated Ruby code would add a second
execution boundary.

## Decision

`Grammar.load_tmlanguage` reads JSON with Ruby's JSON parser or XML plist with
REXML's pull parser, validates a bounded grammar model, and returns a
`Rouge::Lexer` subclass instance backed by an interpreter. The supported model
includes `match`, repository and `$self`/`$base` includes, nested pattern groups,
`begin`/`end`, end-pattern priority, numeric end backreferences, and named
captures. Scope names map to the closest stable Rouge token family.

The loader rejects files larger than 2 MiB, nesting beyond 64 levels, more than
10,000 rules, regular expressions larger than 16 KiB, duplicate dictionary
keys, custom XML document types or entities, unresolved and external includes,
and unsupported operational keys. The fixed Apple plist 1.0 document type is
removed before parsing and never resolved. Lexing is separately bounded by
source bytes, expanded rule count, include and context depth, zero-width
transitions, and elapsed time.

## Consequences

- Loaded lexers work with `Highlighter` and generic `Structure` without generated
  code or a TextMate runtime dependency.
- XML support requires REXML, the maintained Ruby XML toolkit.
- External grammar bundles, injections, `while` rules, nested repositories, and
  capture subgrammars fail explicitly. They can be added when a real grammar
  requires them and supplies interoperability fixtures.
- Loaded lexers use Antares' bounded window strategy rather than incremental
  Rouge state snapshots.
