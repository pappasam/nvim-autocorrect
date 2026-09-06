if vim.g.loaded_nvim_autocorrect then
  return
end

require("autocorrect").setup(vim.g.nvim_autocorrect)
