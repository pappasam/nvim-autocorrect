# Neovim Autocorrect

**Warning: I plan to force push with history corrections until this stabilizes to prevent the repo's history from getting to large as I experiment with code design**

Automatic spelling corrections for prose, using Neovim's native insert-mode abbreviations. Includes 1,007,039 lowercase typo corrections and enables them in Markdown and Git commit messages by default.

Requires a recent Neovim with `vim.uv`, `vim.system`, and Lua abbreviation mappings (`vim.keymap.set("ia", ...)`). Tested on Neovim `v0.13.0-dev-1536+g050fa30632`. Vim is not supported.

## Differentiating Features

- Corrects whole lowercase words when you type a separator or leave Insert mode.
- Preserves capitalized words, acronyms, identifiers, and longer words containing a typo.
- Uses native abbreviation behavior for punctuation, undo/redo, macros, and Ctrl-V bypass.
- Loads dictionary partitions on demand and shares them across buffers.
- Installs at most two internal abbreviations during insertion, regardless of dictionary size.
- Respects existing user abbreviations and provides no default key mappings.
- Builds and caches the dictionary automatically, with background rebuilds after source changes.
- Needs no external dictionaries or Python packages during normal editing.

## Configuration Overview

The default filetypes are `markdown` and `gitcommit`. To choose your own:

```lua
require("autocorrect").setup({
  filetypes = { "markdown", "gitcommit", "text" },
})
```

The list replaces the defaults. An empty list disables automatic correction. Calling `setup()` again safely replaces the previous configuration.

## Installation

Install with your usual plugin manager. We recommend [Neovim's native package manager](https://neovim.io/doc/user/pack.html).

Loading the plugin enables its defaults; calling `setup()` is optional. No installation hook is needed. On first load, Neovim builds the dictionary in the background and stores it under `stdpath("cache")/nvim-autocorrect/`. Correction begins when the build finishes; text typed before then is left unchanged.

Later sessions reuse the cache. Source or builder updates trigger a new build when the plugin loads. The plugin directory can be read-only. To build ahead of the first session, run `make build` from the plugin directory using the same Neovim and cache environment as your editor.

## Full Documentation

From within Neovim, type:

```vim
:help nvim-autocorrect
```

See [the help file](doc/autocorrect.txt) for configuration and commands, and [the contributor guide](CONTRIBUTING.md) for dictionary syntax, source credits, auditing, and performance details.

## Key Mappings

This plugin provides no default key mappings. Neovim's abbreviation controls apply:

- Type a separator (space, punctuation, etc.) to expand a matching word.
- Press Ctrl-] to expand without inserting a separator.
- Press Ctrl-V before a separator to bypass expansion for that separator.

For example, `definately` becomes `definitely `, while `Definately` and `foo_definately` remain unchanged.

## Dictionary Maintenance

Edit `data/corrections.json`. Saving it while the plugin is loaded rebuilds and reloads the dictionary in the background. Use `:AutocorrectBuild` to trigger this manually. A failed build preserves the previous dictionary.

From the plugin repository:

```sh
make build                # Build the local cache and print its path
make check                # Build, validate, and test from a fresh checkout
make benchmark            # Measure editing with the shipped dictionary
make benchmark-dictionary # Measure bucket loading and retained memory
```

Commit the source and refreshed audit; generated dictionaries are local cache files and are not tracked in Git. The linguistic audit is a separate maintenance task documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## FAQ

### How does it choose between possible corrections?

After protecting known words, names, and corpus tokens, the dictionary can prefer a clearly dominant common correction: `abotu` → `about`. The frequency rule requires at least 10 occurrences per million words and a 100-fold lead over every alternative. Close candidates remain uncorrected; see the [full selection rules](CONTRIBUTING.md#selection-rules).

### How are swapped letters handled?

When a unique adjacent-letter swap preserves all letters and every competing correction deletes one, the swap wins: `requirse` becomes `requires`, even though deleting `s` would give `require`. When this swap preference cannot resolve the alternatives, a common candidate may win if it is at least 100 times more frequent than every competitor. Known valid words remain protected. See the [selection rules](CONTRIBUTING.md#adjacent-swap-preference).

This also permits five-letter swaps such as `mgiht` → `might`, subject to the same word, name, and corpus filters. Typos of common three- and four-letter words use a stricter frequency rule below. The exact reviewed exception `hte` → `the` also applies.

### Does it correct short words such as `wiht`?

Yes. `wiht` → `with`, `taht` → `that`, and `yuo` → `you` qualify under the short-word rule: the destination occurs at least 100 times per million words and is at least 100 times more frequent than every known alternative. The catalog adds 7,010 typos of common three- and four-letter words, including extra-keystroke inputs such as `tthe`. Known words and names, shorthand such as `wth`, and close alternatives such as `fomr` remain unchanged.

The [Wiktionary entry for `wiht`](https://en.wiktionary.org/wiki/wiht) describes Old English and Old Saxon. This plugin targets modern English prose; historical-language entries alone do not disqualify a typo. Reference-dictionary protection still applies.

### Why does it correct `hte` but not `teh` or capitalized words?

`hte` → `the` is an explicit reviewed preference. Other short ambiguous typos and tokens found in spelling/name dictionaries remain excluded. Only whole lowercase tokens are eligible; names and acronyms retain their capitalization.

This screening cannot enumerate every lowercase name, brand, or specialized term. Automatic correction remains context-free; see the contributor guide for the selection rules and limitations.

### Why isn't `thousend` corrected to `thousand`?

The generated patterns cover neighboring-key substitutions, not arbitrary vowel substitutions. `a` and `e` are not neighboring keys, and the pinned codespell dictionary does not document this correction. This is a deliberate coverage limit; increasing the vocabulary does not change the allowed typo patterns.

### What if a legitimate term gets corrected?

Add it with a reason and source URL to `data/protected-words.json`, then refresh the catalog, audit, and generated dictionary as described in [supplemental protected words](CONTRIBUTING.md#supplemental-protected-words). This protects terms missing from the reference dictionaries, such as `buidl`, and checks their effect on ambiguous corrections.

### Can I use it in other filetypes?

Yes. Add them to `filetypes` in `setup()`. Correction applies throughout each selected buffer; it does not distinguish prose from fenced code or comments.

### Does it modify existing text or correct files on save?

It expands words as you type in Insert or Replace mode. Saving the dictionary's source rebuilds its data; saving ordinary buffers does not rewrite their contents.
