return {
  "epwalsh/obsidian.nvim",
  version = "*",
  lazy = false,

  -- Load obsidian.nvim for markdown files in your vault:
  event = {
    "BufReadPre " .. vim.fn.expand("~") .. "/Notes/**.md",
    "BufNewFile " .. vim.fn.expand("~") .. "/Notes/**.md",
  },

  dependencies = {
    -- Required.
    "nvim-lua/plenary.nvim",

    -- see below for full list of optional dependencies 👇
  },
  opts = {
    workspaces = {
      {
        name = "personal",
        path = "~/Notes/personal/",
      },
      {
        name = "work",
        path = "~/Notes/work/",
      },
    },

    -- see below for full list of options 👇
  },
}
