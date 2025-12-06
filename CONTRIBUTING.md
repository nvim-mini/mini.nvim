# Contributing

Thank you for your willingness to contribute to 'mini.nvim'. It means a lot!

You can make contributions in the following ways:

- **Mention it** somehow to help reach broader audience. This helps a lot.
- **Create a GitHub issue**. It can be one of the following types:
    - **Bug report**. Describe your actions in a reproducible way along with their effect and what you expected should happen. Before making one, please make your best efforts to:
        - Make sure that it is not an intended behavior, i.e. not described in documentation as such.
        - Make sure that it was not reported before, i.e. there is no bug report already created (no matter open or closed).
    - **Feature request**. A concise and justified description of what one or several modules should be able to do. Before making one, please make your best efforts to make sure that it is not a feature that won't get implemented (these should be described in documentation; for example: block comments in 'mini.comment').
- **Create a pull request (PR)**. It can be one of the following types:
    - **Code related**. For example, fix a bug or implement a feature. **Before even starting one, please make sure that it is aligned with project vision and goals**. The best way to do so is to receive positive feedback from maintainer on your initiative in one of the GitHub issues (existing or created by you). Please, make sure to regenerate latest help file and that all tests pass (see later sections).
    - **Documentation related**. For example, fix typo/wording in 'README.md', code comments or annotations (which are used to generate Neovim documentation; see later section). Feel free to make these without creating a GitHub issue.
    - **Add plugin integration to 'mini.base16' and 'mini.hues' modules**.
- **Add explicit support to other colorschemes**. Every 'mini.nvim' module supports any colorscheme right out of the box. This is done by making most highlight groups be linked to a semantically similar builtin highlight group. Other groups are hard-coded based on personal preference. However, these choices might be out of tune with a particular colorscheme. Updating as many colorschemes as possible to have explicit 'mini.nvim' support is highly appreciated. For your convenience, there is a list of all highlight groups in later section of this file.
- **Participate in [discussions](https://github.com/nvim-mini/mini.nvim/discussions)**.

All well-intentioned, polite, and respectful contributions are always welcome! Thanks for reading this!

## Commit messages

- Try to make commit message as concise as possible while giving enough information about nature of a change. Think about whether it will be easy to understand in one year time when browsing through commit history.

- Single commit should change either zero or one module, or affect all modules (i.e. enforcing some universal rule but not necessarily change files). Changes for two or more modules should be split in several module-specific commits.

- Use [Conventional commits](https://www.conventionalcommits.org/en/v1.0.0/) style:
    - Messages should have the following structure:

        ```
        <type>[optional scope][!]: <description>
        <empty line>
        [optional body]
        <empty line>
        [optional footer(s)]
        ```

    - `<type>` is **mandatory** and can be one of:
        - `ci` - change in how automation (GitHub actions, dual distribution scripts, etc.) is done.
        - `docs` - change in user facing documentation (help, README, CONTRIBUTING, etc.).
        - `feat` - adding new user facing feature.
        - `fix` - resolving user facing issue.
        - `refactor` - change in code or documentation that should not affect users.
        - `style` - change in convention of how something should be done (formatting, wording, etc.) and its effects.
        - `test` - change in tests.
      For temporary commits which later should be squashed (when working on PR, for example), use `fixup` type.
    - `[optional scope]`, if present, should be done in parenthesis `()`. If commit changes single module (as it usually should), using scope with module name is **mandatory**. If commit enforces something for all modules, use `ALL` scope.
    - Breaking change, if present, should be expressed with `!` before `:`.
    - `<description>` is a change overview in imperative, present tense ("change" not "changed" nor "changes"). Should result into first line under 72 characters. Should start with not capitalized word and NOT end with sentence ending punctuation (i.e. one of `.,?!;`).
    - `[optional body]`, if present, should contain details and motivation about the change in plain language. Should be formatted to have maximum 80 characters in line.
    - `[optional footer(s)]`, if present, should be instruction(s) to Git or Github. Use "Resolve #xxx" on separate line if this commit resolves issue or PR.

- Use module's function and field names without module's name. Like `add()` and not `MiniSurround.add()`.

Examples:

```
feat(deps): add folds in update confirmation buffer
```

```
fix(jump): make operator not delete one character if target is not found

One main goal is to do that in a dot-repeatable way, because this is very
likely to be repeated after an unfortunate first try.

Resolve #688
```

```
refactor(bracketed): do not source 'vim.treesitter' on `require()`

Although less explicit, this considerably reduces startup footprint of
'mini.bracketed' in isolation.
```

```
feat(hues)!: update verbatim text to be distinctive
```

```
test(ALL): update screenshots to work on Nightly
```

### Automated commit linting

- To lint messages of already done commits, execute `scripts/lintcommit-ci.sh <git-log-range>`. For example, to lint currently latest commit use `scripts/lintcommit-ci.sh HEAD~..HEAD`.
- To lint commit message before doing commit, install [`pre-commit`](https://pre-commit.com/#install) and enable it with `pre-commit install --hook-type commit-msg` (from the root directory). NOTE: requires `nvim` executable. If it throws (usually descriptive) error - recommit with proper message.

## Generating help file

If your contribution updates annotations used to generate help file, please regenerate it. You can make this with one of the following (assuming current directory being project root):

- From command line execute `make documentation`.
- Inside Neovim instance run `:luafile scripts/minidoc.lua` or `:lua require('mini.doc').generate()`.

## Testing

If your contribution updates code, please make sure that it doesn't break existing tests. If it adds new functionality or fixes a recognized bug, add new test case(s). There are two ways of running tests:

- From command line:
    - Execute `make test` to run all tests (with `nvim` as executable).
    - Execute `make test_xxx` to run tests only from file `tests/test_xxx.lua` (with `nvim` as executable). For example, `make test_ai`.
    - If you have multiple Neovim executables (say, `nvim_07`, `nvim_08`, `nvim_09`, `nvim_010`), you can use `NVIM_EXEC` variable to tests against multiple versions like this:
      `NVIM_EXEC="nvim_07 nvim_08 nvim_09 nvim_010" make test` or `NVIM_EXEC="nvim_07 nvim_08 nvim_09 nvim_010" make test_xxx`.
- Inside Neovim instance execute `:lua require('mini.test').setup(); MiniTest.run()` to run all tests or `:lua require('mini.test').setup(); MiniTest.run_file()` to run tests only from current buffer.

This plugin uses 'mini.test' to manage its tests. For a more hands-on introduction, see [TESTING.md](TESTING.md).

**Notes**:

- If new functionality relies on an external dependency (`git` CLI tool, LSP server, etc.), use mocking (writing Lua code which emulates dependency usage as close as reasonably possible). For examples, take a look at tests for 'mini.pick', 'mini.completion', and 'mini.statusline'.
- There is a certain number of tests that are flaky (i.e. will sometimes report an error due to other reasons than actual functionality being broke). It is usually the ones which test time related functionality (i.e. that certain action was done after specific amount of delay).

    A commonly used way to know if the test is flaky is that it fails on non-nightly Neovim version yet there were no changes to its tested module after it had passed in the past. For example, some 'mini.animate' test is shown to break but there were no changes to it since test passed in CI couple of days before.

    This issue is addressed by having test cases being executed several times in case of failure (with more retries in slow context). See ["Retry" section in 'TESTING.md'](TESTING.md#Retry).

    In case there is some test breaking which reasonably should not, rerun that test (or the whole file) at least several times.
- Advice for writing more robust tests:
    - To test asynchronous or slow execution, use common `sleep()` test helper. For a more robust testing code, **never** directly use numbers to compute sleep time. Use precomputed time delay constants, which should always take into account different testing OSs (like be bigger on Windows, etc.). If module testing requires its extensive use and tests can not be made robust enough (examples are 'mini.animate', 'mini.jump', etc.), consider using it with argument that skips entire test case if `sleep()` is called in slow context.
    - Take into account that Windows uses "\" as default path separator instead of Unix "/". This should be accounted either in module's code (preferably) or in test files (for example, by computing path separator and relying on it).

## Formatting

This project uses [StyLua](https://github.com/JohnnyMorganz/StyLua) version 2.1.0 for formatting Lua code. Before making changes to code, please:

- [Install StyLua](https://github.com/JohnnyMorganz/StyLua#installation). NOTE: use `v2.1.0`.
- Format with it. Currently there are two ways to do this:
    - Manually run `stylua .` from the root directory of this project.
    - Install [`pre-commit`](https://pre-commit.com/#install) and enable it with `pre-commit install` (from the root directory). This will auto-format relevant code before making commits.

## List of highlight groups

Here is a list of all highlight groups defined inside 'mini.nvim' modules. See documentation in 'doc' directory to find out what they are used for.

- 'mini.animate':
    - `MiniAnimateCursor`
    - `MiniAnimateNormalFloat`

- 'mini.clue':
    - `MiniClueBorder`
    - `MiniClueDescGroup`
    - `MiniClueDescSingle`
    - `MiniClueNextKey`
    - `MiniClueNextKeyWithPostkeys`
    - `MiniClueSeparator`
    - `MiniClueTitle`

- 'mini.cmdline':
    - `MiniCmdlinePeekBorder`
    - `MiniCmdlinePeekLineNr`
    - `MiniCmdlinePeekNormal`
    - `MiniCmdlinePeekSep`
    - `MiniCmdlinePeekSign`
    - `MiniCmdlinePeekTitle`

- 'mini.completion':
    - `MiniCompletionActiveParameter`
    - `MiniCompletionDeprecated`
    - `MiniCompletionInfoBorderOutdated`

- 'mini.cursorword':
    - `MiniCursorword`
    - `MiniCursorwordCurrent`

- 'mini.deps':
    - `MiniDepsChangeAdded`
    - `MiniDepsChangeRemoved`
    - `MiniDepsHint`
    - `MiniDepsInfo`
    - `MiniDepsMsgBreaking`
    - `MiniDepsPlaceholder`
    - `MiniDepsTitle`
    - `MiniDepsTitleError`
    - `MiniDepsTitleSame`
    - `MiniDepsTitleUpdate`

- 'mini.diff':
    - `MiniDiffSignAdd`
    - `MiniDiffSignChange`
    - `MiniDiffSignDelete`
    - `MiniDiffOverAdd`
    - `MiniDiffOverChange`
    - `MiniDiffOverChangeBuf`
    - `MiniDiffOverContext`
    - `MiniDiffOverContextBuf`
    - `MiniDiffOverDelete`

- 'mini.files':
    - `MiniFilesBorder`
    - `MiniFilesBorderModified`
    - `MiniFilesCursorLine`
    - `MiniFilesDirectory`
    - `MiniFilesFile`
    - `MiniFilesNormal`
    - `MiniFilesTitle`
    - `MiniFilesTitleFocused`

- 'mini.hipatterns':
    - `MiniHipatternsFixme`
    - `MiniHipatternsHack`
    - `MiniHipatternsNote`
    - `MiniHipatternsTodo`

- 'mini.icons':
    - `MiniIconsAzure`
    - `MiniIconsBlue`
    - `MiniIconsCyan`
    - `MiniIconsGreen`
    - `MiniIconsGrey`
    - `MiniIconsOrange`
    - `MiniIconsPurple`
    - `MiniIconsRed`
    - `MiniIconsYellow`

- 'mini.indentscope':
    - `MiniIndentscopeSymbol`
    - `MiniIndentscopeSymbolOff`

- 'mini.jump':
    - `MiniJump`

- 'mini.jump2d':
    - `MiniJump2dDim`
    - `MiniJump2dSpot`
    - `MiniJump2dSpotAhead`
    - `MiniJump2dSpotUnique`

- 'mini.map':
    - `MiniMapNormal`
    - `MiniMapSymbolCount`
    - `MiniMapSymbolLine`
    - `MiniMapSymbolView`

- 'mini.notify':
    - `MiniNotifyBorder`
    - `MiniNotifyLspProgress`
    - `MiniNotifyNormal`
    - `MiniNotifyTitle`

- 'mini.operators':
    - `MiniOperatorsExchangeFrom`

- 'mini.pick':
    - `MiniPickBorder`
    - `MiniPickBorderBusy`
    - `MiniPickBorderText`
    - `MiniPickCursor`
    - `MiniPickIconDirectory`
    - `MiniPickIconFile`
    - `MiniPickHeader`
    - `MiniPickMatchCurrent`
    - `MiniPickMatchMarked`
    - `MiniPickMatchRanges`
    - `MiniPickNormal`
    - `MiniPickPreviewLine`
    - `MiniPickPreviewRegion`
    - `MiniPickPrompt`
    - `MiniPickPromptCaret`
    - `MiniPickPromptPrefix`

- 'mini.snippets':
    - `MiniSnippetsCurrent`
    - `MiniSnippetsCurrentReplace`
    - `MiniSnippetsFinal`
    - `MiniSnippetsUnvisited`
    - `MiniSnippetsVisited`

- 'mini.starter':
    - `MiniStarterCurrent`
    - `MiniStarterFooter`
    - `MiniStarterHeader`
    - `MiniStarterInactive`
    - `MiniStarterItem`
    - `MiniStarterItemBullet`
    - `MiniStarterItemPrefix`
    - `MiniStarterSection`
    - `MiniStarterQuery`

- 'mini.statusline':
    - `MiniStatuslineDevinfo`
    - `MiniStatuslineFileinfo`
    - `MiniStatuslineFilename`
    - `MiniStatuslineInactive`
    - `MiniStatuslineModeCommand`
    - `MiniStatuslineModeInsert`
    - `MiniStatuslineModeNormal`
    - `MiniStatuslineModeOther`
    - `MiniStatuslineModeReplace`
    - `MiniStatuslineModeVisual`

- 'mini.surround':
    - `MiniSurround`

- 'mini.tabline':
    - `MiniTablineCurrent`
    - `MiniTablineFill`
    - `MiniTablineHidden`
    - `MiniTablineModifiedCurrent`
    - `MiniTablineModifiedHidden`
    - `MiniTablineModifiedVisible`
    - `MiniTablineTabpagesection`
    - `MiniTablineTrunc`
    - `MiniTablineVisible`

- 'mini.test':
    - `MiniTestEmphasis`
    - `MiniTestFail`
    - `MiniTestPass`

- 'mini.trailspace':
    - `MiniTrailspace`
