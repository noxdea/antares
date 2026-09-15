# Lexer compatibility

Generated for Rouge 5.1.0: three source variants, 50 deterministic edits each, and three distant-closure probes per lexer.

| Lexer | Strategy | Passing checks | First failure |
|---|---|---:|---|
| `abap` | `incremental` | 156/156 |  |
| `actionscript` | `window` | 151/156 | token_mismatch |
| `ada` | `incremental` | 156/156 |  |
| `addmusick` | `window` | 153/156 | token_mismatch |
| `apache` | `incremental` | 156/156 |  |
| `apex` | `window` | 155/156 | nonlocal_token |
| `apiblueprint` | `window` | 133/156 | token_mismatch |
| `apple_script` | `window` | 154/156 | token_mismatch |
| `armasm` | `incremental` | 156/156 |  |
| `augeas` | `window` | 155/156 | token_mismatch |
| `awk` | `window` | 153/156 | token_mismatch |
| `batchfile` | `incremental` | 156/156 |  |
| `bbcbasic` | `window` | 155/156 | nonlocal_token |
| `bibtex` | `incremental` | 156/156 |  |
| `bicep` | `window` | 154/156 | token_mismatch |
| `biml` | `incremental` | 156/156 |  |
| `bpf` | `incremental` | 156/156 |  |
| `brainfuck` | `incremental` | 156/156 |  |
| `brightscript` | `incremental` | 156/156 |  |
| `bsl` | `incremental` | 156/156 |  |
| `c` | `window` | 151/156 | token_mismatch |
| `ceylon` | `window` | 152/156 | token_mismatch |
| `cfscript` | `window` | 153/156 | token_mismatch |
| `cisco_ios` | `window` | 153/156 | token_mismatch |
| `clean` | `incremental` | 156/156 |  |
| `clojure` | `window` | 154/156 | token_mismatch |
| `cmake` | `incremental` | 156/156 |  |
| `cmhg` | `window` | 153/156 | token_mismatch |
| `cobol` | `incremental` | 156/156 |  |
| `codeowners` | `incremental` | 156/156 |  |
| `coffeescript` | `incremental` | 156/156 |  |
| `common_lisp` | `window` | 153/156 | token_mismatch |
| `conf` | `incremental` | 156/156 |  |
| `console` | `window` | 0/156 | Antares::UnsupportedLexerError |
| `cpp` | `window` | 153/156 | token_mismatch |
| `crystal` | `window` | 155/156 | nonlocal_token |
| `csharp` | `window` | 154/156 | token_mismatch |
| `css` | `window` | 141/156 | token_mismatch |
| `csvs` | `window` | 154/156 | nonlocal_token |
| `cuda` | `window` | 149/156 | token_mismatch |
| `cypher` | `window` | 154/156 | token_mismatch |
| `cython` | `window` | 151/156 | token_mismatch |
| `d` | `window` | 149/156 | token_mismatch |
| `dafny` | `incremental` | 156/156 |  |
| `dart` | `window` | 155/156 | nonlocal_token |
| `datastudio` | `window` | 155/156 | nonlocal_token |
| `diff` | `incremental` | 156/156 |  |
| `digdag` | `incremental` | 156/156 |  |
| `docker` | `incremental` | 156/156 |  |
| `dot` | `window` | 153/156 | token_mismatch |
| `dylan` | `window` | 154/156 | token_mismatch |
| `ecl` | `window` | 144/156 | token_mismatch |
| `eex` | `incremental` | 156/156 |  |
| `eiffel` | `incremental` | 156/156 |  |
| `elixir` | `incremental` | 156/156 |  |
| `elm` | `incremental` | 156/156 |  |
| `email` | `incremental` | 156/156 |  |
| `epp` | `incremental` | 156/156 |  |
| `erb` | `incremental` | 156/156 |  |
| `erlang` | `incremental` | 156/156 |  |
| `escape` | `window` | 0/156 | Antares::UnsupportedLexerError |
| `factor` | `window` | 155/156 | nonlocal_token |
| `fluent` | `window` | 154/156 | token_mismatch |
| `fortran` | `incremental` | 156/156 |  |
| `freefem` | `window` | 155/156 | nonlocal_token |
| `fsharp` | `incremental` | 156/156 |  |
| `gdscript` | `window` | 146/156 | token_mismatch |
| `ghc-cmm` | `window` | 152/156 | token_mismatch |
| `ghc-core` | `window` | 139/156 | token_mismatch |
| `gherkin` | `window` | 155/156 | nonlocal_token |
| `gjs` | `incremental` | 156/156 |  |
| `glsl` | `window` | 130/156 | token_mismatch |
| `go` | `window` | 152/156 | token_mismatch |
| `gradle` | `window` | 138/156 | token_mismatch |
| `graphql` | `window` | 155/156 | nonlocal_token |
| `groovy` | `window` | 150/156 | token_mismatch |
| `gts` | `incremental` | 156/156 |  |
| `hack` | `window` | 155/156 | nonlocal_token |
| `haml` | `incremental` | 156/156 |  |
| `handlebars` | `incremental` | 156/156 |  |
| `haskell` | `incremental` | 156/156 |  |
| `haxe` | `window` | 155/156 | nonlocal_token |
| `hcl` | `incremental` | 156/156 |  |
| `hlsl` | `window` | 152/156 | token_mismatch |
| `hocon` | `incremental` | 156/156 |  |
| `hql` | `window` | 154/156 | token_mismatch |
| `html` | `incremental` | 156/156 |  |
| `http` | `incremental` | 156/156 |  |
| `hylang` | `window` | 155/156 | nonlocal_token |
| `idlang` | `incremental` | 156/156 |  |
| `idris` | `incremental` | 156/156 |  |
| `iecst` | `window` | 133/156 | token_mismatch |
| `igorpro` | `incremental` | 156/156 |  |
| `ini` | `incremental` | 156/156 |  |
| `io` | `window` | 153/156 | token_mismatch |
| `irb` | `window` | 0/156 | Antares::UnsupportedLexerError |
| `irb_output` | `incremental` | 156/156 |  |
| `isabelle` | `incremental` | 156/156 |  |
| `isbl` | `window` | 146/156 | token_mismatch |
| `j` | `window` | 154/156 | token_mismatch |
| `janet` | `incremental` | 156/156 |  |
| `java` | `window` | 140/156 | token_mismatch |
| `javascript` | `incremental` | 156/156 |  |
| `jinja` | `incremental` | 156/156 |  |
| `jsl` | `incremental` | 156/156 |  |
| `json` | `incremental` | 156/156 |  |
| `json-doc` | `incremental` | 156/156 |  |
| `json5` | `window` | 155/156 | nonlocal_token |
| `jsonnet` | `window` | 151/156 | token_mismatch |
| `jsp` | `window` | 145/156 | token_mismatch |
| `jsx` | `window` | 150/156 | token_mismatch |
| `julia` | `incremental` | 156/156 |  |
| `kick_assembler` | `window` | 146/156 | token_mismatch |
| `kotlin` | `window` | 151/156 | token_mismatch |
| `lasso` | `window` | 144/156 | token_mismatch |
| `lean` | `window` | 153/156 | token_mismatch |
| `liquid` | `incremental` | 156/156 |  |
| `literate_coffeescript` | `incremental` | 156/156 |  |
| `literate_haskell` | `incremental` | 156/156 |  |
| `livescript` | `window` | 143/156 | token_mismatch |
| `llvm` | `window` | 145/156 | token_mismatch |
| `lua` | `incremental` | 156/156 |  |
| `lustre` | `window` | 155/156 | nonlocal_token |
| `lutin` | `window` | 155/156 | nonlocal_token |
| `m68k` | `incremental` | 156/156 |  |
| `magik` | `incremental` | 156/156 |  |
| `make` | `window` | 153/156 | token_mismatch |
| `markdown` | `incremental` | 156/156 |  |
| `mason` | `window` | 111/156 | token_mismatch |
| `mathematica` | `window` | 154/156 | token_mismatch |
| `matlab` | `incremental` | 156/156 |  |
| `meson` | `incremental` | 156/156 |  |
| `minizinc` | `window` | 147/156 | token_mismatch |
| `mojo` | `incremental` | 156/156 |  |
| `moonscript` | `incremental` | 156/156 |  |
| `mosel` | `window` | 147/156 | token_mismatch |
| `msgtrans` | `incremental` | 156/156 |  |
| `mxml` | `incremental` | 156/156 |  |
| `nasm` | `incremental` | 156/156 |  |
| `nesasm` | `incremental` | 156/156 |  |
| `nginx` | `incremental` | 156/156 |  |
| `nial` | `incremental` | 156/156 |  |
| `nim` | `incremental` | 156/156 |  |
| `nix` | `incremental` | 156/156 |  |
| `objective_c` | `window` | 155/156 | nonlocal_token |
| `objective_cpp` | `window` | 149/156 | token_mismatch |
| `ocaml` | `incremental` | 156/156 |  |
| `ocl` | `incremental` | 156/156 |  |
| `openedge` | `incremental` | 156/156 |  |
| `opentype_feature_file` | `incremental` | 156/156 |  |
| `p4` | `window` | 154/156 | nonlocal_token |
| `pascal` | `window` | 144/156 | token_mismatch |
| `pdf` | `incremental` | 156/156 |  |
| `perl` | `incremental` | 156/156 |  |
| `php` | `window` | 154/156 | token_mismatch |
| `plaintext` | `window` | 0/156 | Antares::UnsupportedLexerError |
| `plist` | `window` | 145/156 | token_mismatch |
| `plsql` | `incremental` | 156/156 |  |
| `pony` | `window` | 138/156 | token_mismatch |
| `postscript` | `incremental` | 156/156 |  |
| `powershell` | `incremental` | 156/156 |  |
| `praat` | `incremental` | 156/156 |  |
| `prolog` | `window` | 150/156 | token_mismatch |
| `prometheus` | `incremental` | 156/156 |  |
| `properties` | `incremental` | 156/156 |  |
| `protobuf` | `window` | 150/156 | token_mismatch |
| `puppet` | `incremental` | 156/156 |  |
| `python` | `incremental` | 156/156 |  |
| `q` | `incremental` | 156/156 |  |
| `qml` | `incremental` | 156/156 |  |
| `r` | `window` | 146/156 | token_mismatch |
| `racket` | `window` | 154/156 | token_mismatch |
| `reasonml` | `incremental` | 156/156 |  |
| `rego` | `window` | 155/156 | nonlocal_token |
| `rescript` | `incremental` | 156/156 |  |
| `rml` | `window` | 149/156 | token_mismatch |
| `robot_framework` | `incremental` | 156/156 |  |
| `rocq` | `incremental` | 156/156 |  |
| `ruby` | `window` | 155/156 | nonlocal_token |
| `rust` | `incremental` | 156/156 |  |
| `sas` | `window` | 155/156 | nonlocal_token |
| `sass` | `incremental` | 156/156 |  |
| `scala` | `window` | 153/156 | token_mismatch |
| `scheme` | `window` | 155/156 | nonlocal_token |
| `scss` | `window` | 155/156 | nonlocal_token |
| `sed` | `window` | 155/156 | token_mismatch |
| `shell` | `incremental` | 156/156 |  |
| `sieve` | `window` | 155/156 | nonlocal_token |
| `slice` | `window` | 153/156 | token_mismatch |
| `slim` | `incremental` | 156/156 |  |
| `smalltalk` | `window` | 153/156 | token_mismatch |
| `smarty` | `incremental` | 156/156 |  |
| `sml` | `incremental` | 156/156 |  |
| `sparql` | `incremental` | 156/156 |  |
| `sqf` | `window` | 155/156 | nonlocal_token |
| `sql` | `incremental` | 156/156 |  |
| `ssh` | `incremental` | 156/156 |  |
| `stan` | `window` | 60/156 | token_mismatch |
| `stata` | `window` | 152/156 | token_mismatch |
| `supercollider` | `window` | 154/156 | token_mismatch |
| `svelte` | `incremental` | 156/156 |  |
| `swift` | `incremental` | 156/156 |  |
| `systemd` | `incremental` | 156/156 |  |
| `syzlang` | `window` | 155/156 | nonlocal_token |
| `syzprog` | `incremental` | 156/156 |  |
| `tap` | `incremental` | 156/156 |  |
| `tcl` | `incremental` | 156/156 |  |
| `terraform` | `incremental` | 156/156 |  |
| `tex` | `incremental` | 156/156 |  |
| `thrift` | `incremental` | 156/156 |  |
| `toml` | `incremental` | 156/156 |  |
| `tsx` | `window` | 155/156 | token_mismatch |
| `ttcn3` | `window` | 155/156 | nonlocal_token |
| `tulip` | `incremental` | 156/156 |  |
| `turtle` | `window` | 147/156 | token_mismatch |
| `twig` | `incremental` | 156/156 |  |
| `typescript` | `incremental` | 156/156 |  |
| `vala` | `window` | 153/156 | token_mismatch |
| `vb` | `incremental` | 156/156 |  |
| `vcl` | `window` | 152/156 | token_mismatch |
| `velocity` | `window` | 147/156 | token_mismatch |
| `verilog` | `window` | 155/156 | nonlocal_token |
| `veryl` | `window` | 146/156 | token_mismatch |
| `vhdl` | `window` | 136/156 | token_mismatch |
| `viml` | `incremental` | 156/156 |  |
| `vue` | `incremental` | 156/156 |  |
| `wollok` | `window` | 146/156 | token_mismatch |
| `xml` | `incremental` | 156/156 |  |
| `xojo` | `incremental` | 156/156 |  |
| `xpath` | `window` | 155/156 | nonlocal_token |
| `xquery` | `window` | 154/156 | token_mismatch |
| `yaml` | `incremental` | 156/156 |  |
| `yang` | `window` | 155/156 | nonlocal_token |
| `zig` | `incremental` | 156/156 |  |
