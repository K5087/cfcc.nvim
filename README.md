# cfcc.nvim

Cpp Function Code Action

for cpp function declarator/definition quick generate

only simply syntax pattern ,haven't semantic analysis

## depend

this plugin depend clangd provide source/header file analysis

## Example

```lua
require("cfcc").code_action()
```

## Plan

query now cause unexcept bug, some maybe rewrite with ast scan

or change this project to a lsp,so that can have more capability
