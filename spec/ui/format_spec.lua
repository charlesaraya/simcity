-- spec/ui/format_spec.lua
-- Pure money formatting: comma-grouped integers. Extracted from the HUD so the
-- grouping logic is testable without love.

local Format = require("src.ui.format")

describe("Format.commas", function()
    it("leaves sub-thousand numbers unchanged", function()
        assert.are.equal("0", Format.commas(0))
        assert.are.equal("1", Format.commas(1))
        assert.are.equal("999", Format.commas(999))
    end)

    it("groups thousands", function()
        assert.are.equal("1,000", Format.commas(1000))
        assert.are.equal("12,345", Format.commas(12345))
        assert.are.equal("1,234,567", Format.commas(1234567))
    end)

    it("handles negatives, keeping the sign outside the grouping", function()
        assert.are.equal("-2,500", Format.commas(-2500))
        assert.are.equal("-7", Format.commas(-7))
    end)
end)
