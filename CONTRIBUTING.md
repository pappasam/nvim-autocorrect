# Contributing to nvim-autocorrect

The catalog contains 1,009,975 lowercase typo mappings across 12,104 destinations, including 11 two-word phrases.

## Editing and rebuilding

Edit `data/corrections.json`: keys are correct spellings; values list accepted typos.

```json
{
  "definitely": [
    "definately"
  ],
  "separately": [
    "seperately",
    "sepparately"
  ]
}
```

Inputs must be lowercase ASCII words. Destinations may be one word or exactly two lowercase ASCII words separated by one ordinary space, such as `"each other": ["eachother"]`. Apostrophes, other punctuation, tabs, newlines, leading/trailing spaces, repeated spaces, and longer phrases are rejected. Sort keys and typo lists alphabetically, with one typo per line. Empty lists, duplicate keys or typos, conflicting destinations, and identity mappings are rejected. An empty object disables all mappings. Put explanations here; JSON does not support comments.

Saving the source with the plugin loaded rebuilds and reloads the dictionary in the background. Otherwise, run `:AutocorrectBuild` or `make build`. Failed builds preserve the previous dictionary. Commit the source and refreshed audit; compiled dictionaries are local cache files, never repository artifacts. `make build` prints the cache path.

On plugin load, missing or stale caches build automatically in a separate headless Neovim process. The cache lives under `stdpath("cache")/nvim-autocorrect/`, keyed by the plugin's canonical directory so symlinked installations share a cache and separate checkouts remain isolated. The source JSON and Lua builder, parser, reader, and cache code contribute file size, inode, mtime, and ctime to a freshness fingerprint. Startup checks file metadata and a small dictionary header; it does not read the full JSON or decode dictionary buckets.

The build records that fingerprint in the header and checks it again before publishing. A temporary file and atomic rename preserve existing readers' snapshots. Dictionary contents are deterministic for unchanged inputs; the header's local freshness metadata is not intended to be identical across machines. An invalid or truncated header/cache triggers rebuilding. Deleting the cache is safe while Neovim is closed; it will be recreated on the next load. Old repository-local `data/dictionary.mpack` files are ignored and unused.

The first build leaves correction inactive until completion, without changing text already typed. An editor with a loaded dictionary continues using it during a rebuild. Updates made outside Neovim are detected on the next plugin load; use `:AutocorrectBuild` to refresh an existing session. Building needs only Neovim and a writable cache directory, including when the plugin checkout is read-only.

Build validation checks structure and conflicts, not linguistic safety. Refresh the audit below after changing mappings, supplemental protected words, or reviewed correction evidence; `make check` requires all three recorded hashes to match their sources.

## Selection rules

Protect valid input first; for an eligible typo, choose a well-supported correction even when obscure alternatives exist. Corpus ranking is evidence of relative usage, not a guarantee of what the writer intended.

- Only whole lowercase keyword tokens are eligible. Preserve capitalization, acronyms, identifiers, and embedded suffixes.
- Exclude every token found in SCOWL, CMUdict, or `data/protected-words.json`, including normalized names, abbreviations, regional spellings, and accented or punctuated forms. No preference or exception can override this protection.
- Exclude wordfreq tokens unless codespell or `data/reviewed-corrections.json` documents the same unambiguous correction. For three- and four-letter destinations, three- and four-letter inputs additionally require an adjacent swap or repeated letter, except the exact reviewed `hte` preference.
- Single-word destinations must be SCOWL words or one of the 20 existing computing terms allowlisted in `scripts/audit-dictionary.py`. Two-word destinations must pass the documented joined-word rule below, with both components in SCOWL. Supplemental protection does not authorize a destination.
- Generated typos use a single missing/repeated letter, adjacent transposition, or adjacent-QWERTY-key substitution/insertion. Other misspellings require independent documentation.
- Generated typos normally contain at least six letters. At five letters, require a documented correction, an adjacent swap selected by the preferences below, or a common-word length rule. Four-letter inputs can also qualify for common five-letter destinations under the rule below; three-letter inputs still require the common short-word rule or an exact reviewed exception. One- and two-letter inputs remain excluded.

For single-word destinations, enumerate all single-edit candidates, including every protected token, name, normalized form, and word outside the destination catalog. Apply these preferences in order:

1. An exact reviewed short correction, confirmed by codespell.
2. For the common short-word rule, a destination with at least 100 occurrences per million and a 100-fold frequency lead over every alternative. A swap cannot bypass this requirement.
3. Otherwise, a unique adjacent swap that preserves all input letters, beating deletion candidates and, at five or more letters, sufficiently rare same-length alternatives as described below.
4. A clearly dominant common candidate under the frequency rule below.

A sole candidate needs no ambiguity preference, but still needs the frequency floor when using the common short-word rule. When no preference resolves competing candidates, leave the typo uncorrected. All input-protection, corpus, edit-pattern, length, and destination checks still apply. Selection happens during maintenance; Neovim uses the explicit generated mappings.

### Adjacent-swap preference

The destination must differ only by swapping exactly one adjacent pair of distinct letters, preserving the input's length and letter counts. If every competing candidate is one letter shorter, retain the original swap preference: `requirse` → `requires` wins over `require`, even when the deletion candidate is more common.

For inputs with at least five letters, a unique swap may also beat same-length non-swap alternatives when its frequency is at least 10 occurrences per million and at least 100 times that of every such alternative. Compare the complete same-length candidate set, including names and protected terms outside the destination catalog. Missing corpus frequencies count as zero. Shorter deletion candidates are excluded from this frequency comparison, preserving the original preference for keeping all letters.

This admits `hwere` → `where`: `twere` is sufficiently rare, and `here` and `were` are deletion candidates. A second possible swap or any longer candidate still blocks the swap preference; the general frequency rule may independently resolve them. Close same-length alternatives and rare swap destinations do not qualify for the refinement. The stricter common short-word rule has priority: `wehat` still selects `what`, which dominates all alternatives, including `wheat`.

The refinement never overrides protected input, corpus screening, destination validation, or word boundaries. The audit records its thresholds in `transposition_preference` and counts mappings using it in `rare_alternative_transposition_corrections`.

### Frequency preference

When the adjacent-swap preference does not select a candidate, choose the most frequent candidate only if its wordfreq frequency is both:

- At least `0.00001` (10 occurrences per million words).
- At least 100 times the frequency of every competing candidate.

Use the pinned English wordfreq corpus for all candidates, including names and words outside the catalog. Missing corpus entries have frequency zero. Equal frequencies, close alternatives, and rare winners do not qualify. The threshold is a conservative heuristic, not a measured error probability; review corpus coverage and supplemental protections when maintaining the catalog.

`abotu` now selects `about` despite the rare candidates `abote` and `Abott`. `seperate` similarly selects `separate` over its rare alternatives. Valid input is still protected regardless of how frequent a possible correction is: `trial`, `trail`, and `buidl` remain untouched.

The constants live in `scripts/dictionary_policy.py`. The audit records the thresholds in `frequency_preference` and counts resolutions in `preferred_frequency_corrections`.

### Five-letter adjacent swaps

An undocumented five-letter typo may qualify when exactly one adjacent pair is swapped and the resulting destination wins through the adjacent-swap or frequency preference. For `mgiht`, `might` is the only known single-edit candidate. Other five-letter edit patterns require documentation or one of the common-word rules below. Protection of real words and corpus tokens always applies.

The audit records mappings needing this length exception as `five_letter_transposition_exceptions`. `preferred_transposition_corrections` counts swaps that override deletion candidates or sufficiently rare same-length alternatives.

### Common three- and four-letter words

Generate typos only for lowercase SCOWL words through size 60 with wordfreq frequency at least `0.0001` (100 occurrences per million). Inputs may have three, four, or five letters, using one missing/repeated letter, adjacent swap, or adjacent-QWERTY-key substitution/insertion. `short_word_typos` in `scripts/dictionary_policy.py` defines the keyboard neighbors and edit patterns. Do not generate two-letter inputs.

Compare every known single-edit alternative, including protected names, normalized forms and words outside the destination catalog. The destination must be at least 100 times more frequent than every competitor, even when a unique adjacent swap exists. A sole candidate still needs the 100-per-million floor. Existing documented five-letter corrections retain their prior eligibility; the stricter rule admits new generated patterns.

Protected inputs remain excluded. For new additions, a token already in wordfreq needs documentary confirmation of an adjacent swap or repeated-letter error. This extra restriction avoids expanding shorthand such as `wth` into `with` or `mayu` into `may`. The audit enforces this restriction for three- and four-letter inputs; documented five-letter inputs retain their existing path. The expansion script also applies it to new five-letter inputs.

`wiht` → `with` passes the same filters as other additions, without an exact override. Its [Wiktionary entry](https://en.wiktionary.org/wiki/wiht) describes Old English and Old Saxon. The catalog targets modern English prose and does not treat historical-language entries alone as modern English words. This does not override protection from the reference dictionaries. `whit`, `form`, `from`, `teh`, and common shorthand stay unchanged; `fomr` is too ambiguous to choose between `form` and `from`.

The audit records `short_word_preference`, `frequency_short_corrections` (including previously shipped mappings that now also qualify), and `short_word_destinations`. These frequencies rank intended words; generated variants are plausible keystroke errors, not 7,010 individually observed common misspellings. Corpus coverage and context-free correction still limit precision.

### Common five-letter words

Four- and five-letter keyboard typos of five-letter destinations can qualify when the destination occurs at least 100 times per million words and is at least 100 times more frequent than every known single-edit alternative. A sole candidate still needs the frequency floor. The generator considers lowercase SCOWL words through size 60 and the single-edit patterns in `keyboard_typos`; arbitrary substitutions and multiple edits do not acquire a length exception.

This admits `whch`, `whih`, and `wgich` → `which`. For four-letter inputs leading to five-letter words, documented omissions can pass corpus screening; the swap/repeat-only restriction on three- and four-letter destinations remains intact. All protected inputs, names, and normalized forms remain excluded.

This rule extends length eligibility only. The short-word, swap, and frequency candidate-selection order remains unchanged. Existing documented and swap exceptions retain their prior eligibility. The audit records thresholds in `five_letter_preference` and counts qualifying mappings in `frequency_five_letter_corrections`.

### Reviewed spelling evidence

`data/reviewed-corrections.json` records exact externally documented typo-to-word pairs with `correction`, `reason`, and an HTTP(S) `source` URL. Contributors review whether each source establishes an actual spelling error. This evidence supplements codespell for corpus screening and documented spelling patterns; it does not override input protection, destination validation, length limits, or ambiguity checks. Conflicts with codespell, including multiple suggested destinations, fail validation.

The initial five entries are `probebly` → `probably`, `rimember` → `remember`, `thousend` → `thousand`, and `peolpe`/`pepole` → `people`. Each pair appears in [Peter Norvig's collected spelling errors](https://www.norvig.com/ngrams/spell-errors.txt), compiled from Wikipedia and Roger Mitton's corpora. The source snapshot used for review has SHA-256 `a4abe6ce6c24280f9a8d0485cbf78ddd2e58279ca01293692630a08ba4b13407`. The first three document substitutions outside neighboring keys. The last two document adjacent swaps already present in wordfreq; corpus membership alone does not establish intentional usage. These are reviewed examples, not an automatic import of the entire collection or a ranking of modern typo frequency.

The file is maintenance input only. After changing it, run `scripts/expand-common-words.py`, inspect the proposed catalog and rejected candidates, run the full audit, and update the catalog and audit together. Existing mappings are preserved by the generator, so remove any newly rejected mappings reported by the audit. Saving this evidence file alone does not rebuild the runtime dictionary. Missing or malformed evidence fails validation; an explicit empty object is permitted. The audit records `reviewed_records`, `reviewed_corrections`, `reviewed_corpus_exceptions`, and a canonical `reviewed_sha256` covering pairs and their evidence; `make check` rejects stale evidence.

### Joined words and contractions

Restore a missing space only for an exact pair documented by pinned codespell or reviewed evidence. The input must contain at least six letters and equal the concatenation of exactly two SCOWL words. Each component must occur at least 100 times per million words in wordfreq. These component frequencies establish common vocabulary; they are not phrase-frequency estimates.

Protected input is always excluded. Enumerate every known single-edit word candidate and every two-token split, including normalized names, rare words, and supplemental protected terms. Any single-word candidate or alternative split blocks correction regardless of frequency. The only allowed edit is inserting the space: spelling errors combined with missing spaces do not qualify. No general word segmentation runs during editing.

The 11 accepted pairs are `aboutthe` → `about the`, `alsoneeds` → `also needs`, `eachother` → `each other`, `fromthe` → `from the`, `onlyonce` → `only once`, `receivedfrom` → `received from`, `shortwhile` → `short while`, `somemore` → `some more`, `useanother` → `use another`, `wantto` → `want to`, and `whoknows` → `who knows`. Each is documented in [codespell 2.4.1's dictionary](https://github.com/codespell-project/codespell/blob/v2.4.1/codespell_lib/data/dictionary.txt).

`infact` stays unchanged because words such as `infant` and `intact` compete. `overthere` admits both `over there` and `overt here`. `alot` and `aswell` are protected reference tokens. The strict split check also rejects `atleast` because normalized names and terms admit `atle ast`.

Contraction restoration does not fit the present protection policy: SCOWL/CMUdict protect apostrophe-free forms such as `dont`, `didnt`, and `isnt`, including normalization of their punctuated forms. Other candidates such as `its`, `were`, and `well` are ordinary words. Apostrophes remain outside the source format. Supporting those forms would require a separate deliberate change to protection policy or contextual editing.

`scripts/expand-common-words.py` includes documented joined pairs and applies the same filters as the audit. This batch adds 11 mappings and preserves every prior mapping. The audit records `joined_word_policy` and `joined_word_corrections`; joined pairs are counted separately from single-word single-edit and documented multi-edit corrections. Two-word destinations use the existing native abbreviation engine and cache representation, with no runtime dependency or additional lookup work.

### Reviewed short corrections

`DOCUMENTED_SHORT_CORRECTIONS` in `scripts/dictionary_policy.py` contains exact reviewed exceptions to the minimum-length and ambiguity rules. Currently only `hte` → `the` is approved for common prose usage. Codespell must confirm that exact mapping; an undocumented or different destination cannot use the exception.

These exceptions never override protected input, corpus screening, destination validation, or lowercase whole-word matching. `HTE`, `Hte`, and `foo_hte` remain untouched. Other short typos can qualify under the frequency rule above; `teh` remains excluded by reference-dictionary protection. Exact overrides require explicit review and documentation here; the common short-word rule does not bypass ambiguity checks. The audit counts accepted exceptions in `documented_short_corrections`.

### Supplemental protected words

Use `data/protected-words.json` for legitimate terms missing from the reference dictionaries. Each key is an exact lowercase ASCII token to preserve, with a nonempty `reason` and an HTTP(S) `source` URL establishing intentional usage. Sort keys alphabetically. For example:

```json
{
  "buidl": {
    "reason": "Intentional cryptocurrency slang, not an accidental spelling of build.",
    "source": "https://www.coingecko.com/en/glossary/buidl"
  }
}
```

List normalized spellings explicitly when accents or punctuation are relevant, and add inflections individually when supported by evidence. Entries are exact words, not patterns. The audit validates the file's structure; contributors review the evidence. Duplicate keys, invalid tokens, missing evidence, and a missing or malformed file fail validation. An explicit empty object is allowed.

Supplemental tokens cannot appear as typos, even when codespell, frequency, swap, or reviewed short-correction rules otherwise permit correction. They also join the full set of competing single-edit candidates, using the preferences above. Listing a word does not authorize it as a correction destination. `buidl` is protected this way, preserving intentional usage while ordinary `build` remains unchanged.

After editing the list, run the full audit and remove any flagged mappings from `data/corrections.json`, including ambiguous neighbors. Refresh `data/audit.json`, then run `make check`. Commit the list, corrected catalog, and audit together. The audit records `supplemental_protected_tokens` and a canonical `supplemental_protected_sha256` covering tokens and evidence. `make check` rejects stale supplemental audit data and direct protected-word mappings.

The supplemental list is maintenance input; Neovim uses the rebuilt dictionary. Editing or saving the list alone does not change an already loaded dictionary. Run `:AutocorrectBuild` after updating the catalog to rebuild and reload it in an open editor, or restart Neovim after `make build`.

## Catalog expansion

The previous expansion to 1,000,029 entries added 499,966 mappings to the prior 500,063 entries, preserving every existing mapping. It includes 5,698 new destination words. Candidates combine missing variants of existing destinations with lowercase SCOWL words through size 60 that occur at least once per million words in the pinned wordfreq corpus. Destinations are considered in descending frequency, with alphabetical ties, using the generated edit patterns and documented codespell corrections above. Expansion stops after a complete destination group crosses 1,000,000 mappings.

All additions pass the same protected-word, corpus, length, destination, and ambiguity checks; the expansion does not relax the selection rules. The lowest-frequency destination expanded in this batch occurs about 2.95 times per million words. The frequency threshold for resolving ambiguous corrections remains 10 occurrences per million words with a 100-fold lead; less frequent destinations must qualify without that preference.

### Short-word expansion

This batch adds 7,010 mappings to the prior 1,000,029 entries and preserves every existing mapping. It covers 357 common destinations, including 322 new ones: 929 corrections lead to three-letter words and 6,081 lead to four-letter words. The typo inputs have three letters (21), four letters (1,651), or five letters (5,338). All qualifying destination groups are included; no count-based cutoff or weaker threshold is used to fill the batch.

Reproduce the expansion using the same pinned maintenance dependencies and SCOWL release as the audit:

```sh
uv run scripts/expand-short-words.py --scowl /tmp/scowl-2020.12.07 \
  --output /tmp/short-word-corrections.json
uv run scripts/audit-dictionary.py --scowl /tmp/scowl-2020.12.07 \
  --source /tmp/short-word-corrections.json --expect 1009975 \
  --report /tmp/short-word-audit.json
```

The expansion writes a separate proposed catalog and reports additions and rejected candidate pairs. Starting from the shipped catalog produces zero additions and identical catalog contents. Review the proposal and audit before replacing `data/corrections.json` and `data/audit.json`.

### Common-word and reviewed-evidence expansion

This batch adds 2,026 mappings across 214 existing destinations, preserving every previous mapping: 2,021 keyboard typos of common five-letter words and five reviewed corrections. The added inputs contain four letters (32), five letters (1,989), six letters (2), or eight letters (3). The resulting catalog contains 1,009,964 mappings across the same 12,093 destinations.

```sh
uv run scripts/expand-common-words.py --scowl /tmp/scowl-2020.12.07 \
  --output /tmp/common-word-corrections.json
uv run scripts/audit-dictionary.py --scowl /tmp/scowl-2020.12.07 \
  --source /tmp/common-word-corrections.json --expect 1009975 \
  --report /tmp/common-word-audit.json
```

The generator reports additions, categories, and rejected candidate pairs, and fails on conflicting existing mappings. Starting from the shipped catalog produces zero additions and identical contents. That batch introduced no runtime dependencies or punctuation/space corrections; the generator now also includes the joined-word batch described above.

### Swaps with rare alternatives

The refinement added 899 adjacent-swap mappings across 769 existing destination words, preserving every previous mapping. Of these additions, 426 have five letters. That batch brought the catalog to 1,007,938 mappings across the same 12,093 destinations.

Reproduce the batch with the pinned maintenance references:

```sh
uv run scripts/expand-transpositions.py --scowl /tmp/scowl-2020.12.07 \
  --output /tmp/transposition-corrections.json
uv run scripts/audit-dictionary.py --scowl /tmp/scowl-2020.12.07 \
  --source /tmp/transposition-corrections.json --expect 1009975 \
  --report /tmp/transposition-audit.json
```

The script considers only swaps of existing destinations admitted by the refinement. It preserves the common short-word preference and reports conflicting existing mappings for review. Starting from the shipped catalog produces zero additions and identical contents.

## Reference data and audit

Maintenance references:

- [SCOWL 2020.12.07](https://wordlist.aspell.net/), Kevin Atkinson and contributors: all distributed lists for exclusions; word lists through size 80 for destinations. Its `Copyright` file contains licensing and contributor credits.
- [CMUdict](https://github.com/cmusphinx/cmudict), Carnegie Mellon University, package `cmudict==1.1.1`: additional words and names.
- [wordfreq 3.1.1](https://github.com/rspeer/wordfreq), Robyn Speer and contributors: corpus screening and frequency ordering.
- [codespell 2.4.1](https://github.com/codespell-project/codespell): independently documented corrections.
- [Norvig’s collected spelling errors](https://www.norvig.com/ngrams/), from Wikipedia and [Roger Mitton’s corpora](https://titan.dcs.bbk.ac.uk/~roger/corpora.html): five manually reviewed pairs, recorded with evidence in `data/reviewed-corrections.json`. The historical collection includes student writing; it is evidence of observed spellings, not current typo prevalence.

These are maintenance dependencies only. `data/audit.json` records counts, the canonical mapping hash, reference fingerprint, versions, and results; it is not runtime input.

With `uv` installed, download and extract SCOWL, then run the audit:

```sh
curl -fL -o /tmp/scowl.tar.gz https://deb.debian.org/debian/pool/main/s/scowl/scowl_2020.12.07.orig.tar.gz
# SHA-256: 5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc
tar -xzf /tmp/scowl.tar.gz -C /tmp
uv run scripts/audit-dictionary.py \
  --scowl /tmp/scowl-2020.12.07 --expect 1009975 \
  --report data/audit.json
```

The audit independently enumerates single-edit alternatives against the explicit JSON mappings. Adjust `--expect` for intentional catalog-size changes.

## Performance and validation

The dictionary uses 256 hash buckets, read on demand and cached across buffers. An open file descriptor preserves a consistent snapshot during atomic rebuilds, including through Stow symlinks. First access reads and decodes a bucket synchronously; later lookups use its cached table.

During Insert/Replace mode in enabled buffers, `vim.on_key` installs at most two native abbreviations and reads a bounded region around the cursor. Neovim handles expansion, preserving punctuation, undo/redo, macros, and Ctrl-V bypass. User abbreviations take precedence. Avoid scanning or installing the full catalog during editing.

Run from the repository root with Neovim, StyLua, and Python 3.11+ installed:

```sh
make check
make benchmark
make benchmark-dictionary
```

`make check` and `make test` build the local cache first, so both work from a fresh checkout. Checks cover all mappings, capitalization, native abbreviation behavior, boundaries, long lines, shared Lua/Python validation fixtures, audit consistency, automatic builds, cache reuse and invalidation, read-only installations, snapshots, symlinks, determinism, and recovery from invalid input or truncated cache data. Benchmarks isolate plugin costs; compare results on the same Neovim version and machine. Building and normal editing require no Python.

`make benchmark` measures setup, filetype activation, first insertion, 6,000 repeated words, and a subsequent buffer. Fixture construction happens before timing. `make benchmark-dictionary` measures opening the compiled dictionary, decoding all 256 buckets, cached lookups, and retained Lua heap after garbage collection. A cold bucket means it has not been decoded in that process; the operating system may already cache its bytes.

To compare saved catalogs, pass a source JSON or compiled dictionary path respectively:

```sh
nvim -u NONE --headless -i NONE -l tests/benchmark.lua /path/to/corrections.json
nvim -u NONE --headless -i NONE -l tests/benchmark_dictionary.lua /path/to/dictionary.mpack
```

Before the automatic cache-build workflow was introduced, the expansion was measured using the actual prior and expanded catalogs, with five fresh-process samples per catalog, alternating their order, on Neovim `v0.13.0-dev-1536+g050fa30632`. The OS file cache was warm. These historical measurements compare catalog sizes; they exclude the initial build and the new startup freshness check. They are medians from this machine, not latency guarantees:

| Measurement | 500,063 mappings | 1,000,029 mappings |
| --- | ---: | ---: |
| Compiled dictionary | 9.37 MiB | 19.14 MiB |
| Plugin setup | 0.85 ms | 0.89 ms |
| First insertion | 4.80 ms | 9.83 ms |
| 6,000 repeated words | 179.58 ms | 181.38 ms |
| Cold bucket, median | 0.55 ms | 1.40 ms |
| Cold bucket, 95th percentile | 2.19 ms | 3.99 ms |
| Cached lookup, synthetic miss | 0.148 µs | 0.146 µs |
| Retained Lua heap after first bucket | 0.22 MiB | 0.46 MiB |
| Retained Lua heap after all buckets | 33.44 MiB | 66.64 MiB |

The main costs are approximately double the compiled size and retained dictionary memory, plus longer synchronous decoding when a bucket is first needed. Repeated editing in this sample changed little, but it uses only three distinct words; broader vocabulary encounters more cold buckets. Cached buckets remain shared across buffers and are retained until the dictionary is closed or reloaded. Heap measurements are incremental dictionary allocations, not total process memory or transient peaks; full-cache memory is reached only after every bucket has been accessed.
