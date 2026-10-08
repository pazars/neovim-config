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
  { src = "https://github.com/neovim/nvim-lspconfig" }
})

-- Colorscheme
vim.cmd.colorscheme("kanagawa")

-- Set space as the custom <leader> key
vim.g.mapleader = " "

local formatters = { python = "ruff", lua = "emmylua_ls" }

-- <leader> - f: format the current buffer
vim.keymap.set("n", "<leader>f", function ()
  local formatter = formatters[vim.bo.filetype]

  if not formatter then
    vim.notify("No formatter configured for " .. vim.bo.filetype)
    return
  end

  vim.lsp.buf.format({ name = formatter, async = true })
end, { desc = "Format buffer" }
)

vim.lsp.enable({ "ty", "ruff", "emmylua_ls" })
