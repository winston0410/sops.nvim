local util = require("util")

---@class SopsModule
local M = {}

---@param bufnr number
local function sops_decrypt_buffer(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.fs.dirname(path)

  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

  vim.system(
    { "sops", "--decrypt", "--input-type", filetype, "--output-type", filetype, path },
    { cwd = cwd, text = true },
    function(out)
      vim.schedule(function()
        if out.code ~= 0 then
          vim.notify("Failed to decrypt file", vim.log.levels.WARN)

          return
        end

        local decrypted_lines = vim.fn.split(out.stdout, "\n", false)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, decrypted_lines)

        -- Run BufReadPost autocmds since the buffer contents have changed
        vim.api.nvim_exec_autocmds("BufReadPost", {
          buffer = bufnr,
        })
      end)
    end
  )
end

---@param bufnr number
local function sops_encrypt_buffer(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.fs.dirname(path)

  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local editor_script = vim.fs.joinpath(plugin_root, "scripts", "sops-editor.sh")

  if vim.fn.filereadable(editor_script) == 0 then
    vim.notify("SOPS editor script not found: " .. editor_script, vim.log.levels.WARN)

    return
  end

  local temp_file = vim.fn.tempname()
  local function cleanup()
    vim.fn.delete(temp_file)
  end

  local plaintext_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local success = vim.fn.writefile(plaintext_lines, temp_file) == 0

  if not success then
    cleanup()
    vim.notify("Failed to write temp file", vim.log.levels.WARN)

    return
  end

  vim.system({ "sops", "encrypt", path }, {
    cwd = cwd,
    env = {
      SOPS_EDITOR = editor_script,
      SOPS_NVIM_TEMP_FILE = temp_file,
    },
    text = true,
  }, function(out)
    vim.schedule(function()
      cleanup()

      if out.code ~= 0 then
        vim.notify("SOPS failed to edit file: " .. (out.stderr or ""), vim.log.levels.WARN)
        return
      end

      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(out.stdout, "\n", { plain = true }))

      -- Run BufReadPost autocmds since the buffer contents have changed
      vim.api.nvim_exec_autocmds("BufReadPost", {
        buffer = bufnr,
      })
    end)
  end)
end

---@param opts table
M.setup = function(opts)
  opts = opts or {}

  vim.api.nvim_create_user_command("SopsDecrypt", function()
    local bufnr = vim.api.nvim_get_current_buf()
    sops_decrypt_buffer(bufnr)
  end, {
    desc = "Decrypt the current file using SOPS",
  })

  vim.api.nvim_create_user_command("SopsEncrypt", function()
    local bufnr = vim.api.nvim_get_current_buf()
    sops_encrypt_buffer(bufnr)
  end, {
    desc = "Encrypt the current file using SOPS",
  })

  local main_au_group = vim.api.nvim_create_augroup("sops.nvim", { clear = true })

  vim.api.nvim_create_autocmd({
    -- use BufWinEnter so it would fire when session was restored. This autocmd will be running more than once
    "BufWinEnter",
    "BufReadPost",
    "FileReadPost",
  }, {
    group = main_au_group,
    callback = function()
    end,
  })
end

return M
