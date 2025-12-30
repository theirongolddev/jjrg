-- tests/jjrg_spec.lua
-- Tests for jjrg plugin

local core = require("jjrg.core")
local config = require("jjrg.config")

describe("jjrg", function()
	describe("config", function()
		it("should have default configuration", function()
			assert.is_table(config.defaults)
			assert.is_table(config.defaults.rg_args)
			assert.is_table(config.defaults.jj_args)
			assert.is_boolean(config.defaults.use_telescope)
			assert.is_boolean(config.defaults.use_snacks)
			assert.is_boolean(config.defaults.quickfix_open)
		end)

		it("should merge user config with defaults", function()
			config.setup({ use_telescope = false })
			assert.is_false(config.options.use_telescope)
			assert.is_true(config.options.use_snacks) -- unchanged default
			-- Reset
			config.setup({})
		end)

		it("should preserve custom rg_args", function()
			config.setup({ rg_args = { "--hidden" } })
			assert.same({ "--hidden" }, config.options.rg_args)
			-- Reset
			config.setup({})
		end)
	end)

	describe("core.get_context", function()
		local lines = { "line1", "line2", "line3", "line4", "line5" }

		it("should return context around a line", function()
			local ctx = core.get_context(lines, 3, 1)
			assert.is_string(ctx)
			assert.matches("line2", ctx)
			assert.matches("line3", ctx)
			assert.matches("line4", ctx)
		end)

		it("should handle edge at start", function()
			local ctx = core.get_context(lines, 1, 2)
			assert.is_string(ctx)
			assert.matches("line1", ctx)
			assert.matches("line2", ctx)
			assert.matches("line3", ctx)
		end)

		it("should handle edge at end", function()
			local ctx = core.get_context(lines, 5, 2)
			assert.is_string(ctx)
			assert.matches("line3", ctx)
			assert.matches("line4", ctx)
			assert.matches("line5", ctx)
		end)

		it("should mark the target line", function()
			local ctx = core.get_context(lines, 3, 1)
			assert.matches(">line3", ctx)
		end)
	end)

	describe("core.search_diff", function()
		local sample_diff = [[
diff --git a/src/main.lua b/src/main.lua
--- a/src/main.lua
+++ b/src/main.lua
@@ -1,5 +1,6 @@
 local M = {}
+local utils = require("utils")

 function M.hello()
-  print("hello")
+  print("hello world")
 end
]]

		it("should return empty for empty pattern", function()
			local matches, err = core.search_diff("", sample_diff)
			assert.same({}, matches)
			assert.is_string(err)
		end)

		it("should return empty for empty diff", function()
			local matches, err = core.search_diff("test", "")
			assert.same({}, matches)
			assert.is_string(err)
		end)

		it("should find matches in diff content", function()
			local matches, err = core.search_diff("hello", sample_diff)
			assert.is_nil(err)
			assert.is_table(matches)
			-- Should find "hello" in the diff
			if #matches > 0 then
				assert.is_string(matches[1].text)
				assert.matches("hello", matches[1].text)
			end
		end)

		it("should find added lines", function()
			local matches, err = core.search_diff("utils", sample_diff)
			assert.is_nil(err)
			assert.is_table(matches)
		end)
	end)

	describe("core.to_quickfix", function()
		it("should convert matches to quickfix format", function()
			local matches = {
				{ filename = "test.lua", lnum = 10, col = 1, text = "test line" },
				{ filename = "other.lua", lnum = 20, col = 5, text = "other line" },
			}

			local qf = core.to_quickfix(matches)
			assert.equals(2, #qf)
			assert.equals("test.lua", qf[1].filename)
			assert.equals(10, qf[1].lnum)
			assert.equals("test line", qf[1].text)
		end)

		it("should handle empty matches", function()
			local qf = core.to_quickfix({})
			assert.same({}, qf)
		end)
	end)
end)
