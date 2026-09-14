# ADR 002: Derive editor structure from Rouge tokens

- Status: Accepted
- Date: 2026-09-15

## Context

Antares already incrementally tokenizes documents and knows which lexers can
safely resume from checkpoints. Bracket matching, folding, sticky context, and
expanding selections need the same knowledge of strings and comments.

## Decision

Derive generic structure from the token rows owned by `Highlighter`. Keep
per-line structure inputs beside those rows, shift them on edits, and rescan
from the edited line until an unchanged token row is reached. Rebuild the
small document-level indexes from those cached inputs.

Bracket characters are accepted only from Rouge punctuation tokens. Folding
also recognizes indentation, consecutive comment lines, and nested region
markers. Language-specific providers and tmLanguage loading are deferred.

## Consequences

- Highlighting and structure agree about strings and comments.
- The existing lexer compatibility and resource bounds remain authoritative.
- A one-line edit normally reuses the untouched suffix.
- Generic indentation folding is intentionally lexical rather than a full
  language parser.
