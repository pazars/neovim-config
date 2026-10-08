-- Basic editing settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.termguicolors = true

-- Install and load plugins
vim.pack.add({
  -- Colorschme
  { src = "https://github.com/rebelot/kanagawa.nvim" },
  -- LSP config defaults
  { src = "https://github.com/neovim/nvim-lspconfig" },
})

-- Colorscheme
vim.cmd.colorscheme("kanagawa")

-- Set space as the custom <leader> key
vim.g.mapleader = " "

-- <leader> - f[ormat] - r[uff]
vim.keymap.set("n", "<leader>fr", function()
  vim.lsp.buf.format({ name = "ruff", async = true })
end, { desc = "Format with Ruff" })

-- Python language server
vim.lsp.enable({"ty", "ruff"})
