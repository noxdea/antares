<h1 align="center">Antares</h1>

<p align="center">
  <strong>Incremental syntax highlighting for Rouge, with measured per-lexer compatibility</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/antares"><img src="https://img.shields.io/gem/v/antares.svg?colorB=319e8c" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/antares"><img src="https://img.shields.io/gem/dt/antares.svg" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.1-ruby.svg" alt="Ruby Version">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#compatibility">Compatibility</a>
</p>

---

Antares adds edit-aware, line-oriented syntax highlighting to [Rouge](https://github.com/rouge-ruby/rouge). It reuses lexer state where compatibility tests show that incremental highlighting is safe, and falls back to bounded re-highlighting for other lexers. Document storage and colors remain with the caller.

## Features

<a name="features"></a>

- Lazy tokenization for individual lines or ranges
- Incremental re-highlighting with sparse state checkpoints
- Cached suffix reuse after edits converge
- Measured compatibility for every Rouge lexer
- Windowed and full-document fallback strategies
- Configurable time and memory limits
- Bracket pairs, fold regions, sticky contexts, and expanding selections
- JSON and XML plist tmLanguage grammars for languages Rouge does not cover
- Rouge and REXML are the only runtime dependencies

## Installation

<a name="installation"></a>

Add to your Gemfile:

```ruby
gem "antares"
```

Then install:

```bash
bundle install
```

### Requirements

<a name="requirements"></a>

- Ruby 3.1+
- Rouge 5.x

## Quick Start

<a name="quick-start"></a>

```ruby
require "antares"

lines = ["value = 1\n", "print(value)\n"]
highlighter = Antares::Highlighter.new(
  lexer: Rouge::Lexers::Python.new,
  lines: ->(index) { lines[index] },
  line_count: -> { lines.length }
)

highlighter.tokens_for(0) # [[Rouge token class, UTF-8 text], ...]

lines[0] = "value = 2\n"
highlighter.edit(from_line: 0, removed: 1, inserted: 1)
highlighter.tokens_in(0..1) # one token array per line

structure = highlighter.structure # built lazily from the same Rouge tokens
structure.bracket_at(0, 7)        # matching Antares::Bracket, or nil
structure.fold_regions            # bracket, indentation, comment, and #region folds
structure.context_at(1)           # outer-to-inner regions for sticky scroll
structure.selection_ranges(1, 3)  # inner-to-outer Antares::Region values
```

Update the provider before calling `edit`. Line indices are zero based;
`removed` is the old line count and `inserted` is the new line count.

The `lines` provider returns one valid UTF-8 logical line for each index,
preferably including its newline. Tokens contain text rather than offsets: sum
`text.bytesize` for byte offsets or `text.length` for character offsets.
Returned rows, token pairs, and text are frozen.

Bracket and selection columns are zero-based character offsets. A selection
region's `end_column` is exclusive. Fold regions use inclusive, zero-based line
indices; their column fields are `nil`. Brackets inside string and comment
tokens are ignored. `Highlighter#edit` updates the existing `Structure`
instance and reuses unchanged line data after token state converges.

`frontier` is the first line not yet proven current.
`advance(until_line: 200)` lets an event loop schedule incremental work.
`last_scanned_lines` reports lexical work and `checkpoint_bytes` reports
normalized checkpoint payload bytes. Highlighter instances are not thread safe.

Language-specific structure providers can replace the generic derivation for
future highlighters with the matching Rouge lexer tag:

```ruby
Antares::Structure.register(:ruby, RubyStructureProvider)
# RubyStructureProvider.new receives the same five callbacks as Structure.new.
Antares::Structure.unregister(:ruby)
```

A provider returns an object implementing `fold_regions`, `brackets`,
`bracket_at`, `context_at`, `selection_ranges`, and `edit`. Registration is
thread safe, case insensitive, and affects only structures built afterwards.
Providers must reflect line changes before `Highlighter#edit`, just like the
line provider. Antares does not depend on Prism.

Load a UTF-8 JSON or XML plist tmLanguage file when Rouge has no lexer for the
language, then pass the result to `Highlighter` normally:

```ruby
lexer = Antares::Grammar.load_tmlanguage("syntaxes/example.tmLanguage.json")
highlighter = Antares::Highlighter.new(lexer: lexer, lines: lines, line_count: count)
```

The loader supports repository references, `$self`/`$base`, `match`, nested
patterns, `begin`/`end` (including `applyEndPatternLast`) with numeric
begin-capture references, and named captures. TextMate comment, string,
numeric, keyword, storage, name, variable,
punctuation, markup, and invalid scopes map to their nearest Rouge token types.
Files are limited to 2 MiB, 64 levels, 10,000 rules, and 16 KiB per regular
expression; lexing also has byte and time bounds. External grammar includes,
`while`, nested repositories, capture subgrammars, and injection grammars raise
`Antares::GrammarError` instead of being partially interpreted.
The fixed Apple plist 1.0 document type is accepted without external lookup;
custom document types and entity declarations are rejected.

## Configuration

<a name="configuration"></a>

Pass options to `Antares::Highlighter.new`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `strategy` | Symbol | `:auto` | Highlighting strategy |
| `checkpoint_interval` | Integer | `64` | Completed lines between checkpoints |
| `window_context` | Integer | `200` | Lines of context for window mode |
| `max_lines` | Integer | `100_000` | Maximum document lines |
| `max_bytes` | Integer | `8 MiB` | Maximum source snapshot |
| `max_line_bytes` | Integer | `16 KiB` | Maximum bytes per line |
| `max_checkpoint_bytes` | Integer | `256 KiB` | Maximum checkpoint payload |
| `max_seconds` | Numeric | `0.25` | Maximum time per scan |

### Strategies

| Strategy | Behavior |
|----------|----------|
| `:auto` | Uses the verdict bundled for the exact Rouge version. Unknown versions and lexers use `:window`. |
| `:incremental` | Forces state snapshots and convergence. Use only for certified lexers. |
| `:window` | Restarts from the root state up to `window_context` lines before the requested range. |
| `:full` | Runs Rouge over the complete bounded document after every edit. |

Exceeding a source limit switches to window mode. Oversized lines and timed-out
ranges return complete plain-text tokens. `fallback_reason` explains the
transition. These limits also apply to `:full`.

## How It Works

<a name="how-it-works"></a>

1. Source Materialization builds a bounded source string from the line provider
2. Checkpoint Restore resumes the nearest reusable lexer state
3. Incremental Lexing records tokens and sparse state checkpoints
4. State Convergence reuses the untouched cached suffix after an edit
5. Fallback Selection uses window mode when incremental lexing is not certified

Antares copies persistent Rouge lexer state, including nested collections,
delegate lexers, and heredoc queues. Checkpoints are created after complete rule
callbacks because Rouge expressions can consume multiple lines or inspect
surrounding text.

Some grammars are inherently nonlocal. For example, adding a distant `=end` can
change how Rouge classifies an earlier unmatched Ruby `=begin`. Such lexers use
window mode instead of unsafe incremental highlighting.

## Compatibility

<a name="compatibility"></a>

`Antares.compatible?(Rouge::Lexers::Python)` returns `:incremental` or
`:window`. Every registered lexer has a bundled verdict; see the
[complete compatibility table](docs/compatibility.md).

The matrix uses three source variants from Rouge's bundled MIT-licensed demos,
applies 50 deterministic edits to each, and compares every line against a fresh
full lex. Three distant-closure probes detect backward reclassification. The
result is an empirical corpus guarantee, not a proof for every input or
non-default lexer option.

## Development

<a name="development"></a>

```bash
bundle install
bundle exec rake test
bundle exec ruby script/compatibility --write
BUDGET=1 bundle exec rake bench
```

Use `MUTATIONS=5 ruby script/compatibility python rust` for a short compatibility
run. Only full runs with at least 50 mutations may replace the bundled matrix.
CI tests Ruby 3.1 through 4.0 on Linux, macOS, and Windows.

See the [changelog](CHANGELOG.md) for release history.

## Contributing

<a name="contributing"></a>

Bug reports and pull requests are welcome at https://github.com/noxdea/antares.

## License

<a name="license"></a>

Released under the [MIT License](LICENSE.txt).
