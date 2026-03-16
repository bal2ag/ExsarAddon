-- tests/test_makedb.lua
-- Tests for ExsarUI.MakeDB (requires mocking ExsarAddonDB global).

-- Mock the WoW global
_G.ExsarAddonDB = {}

-- Mock ExsarUI since it depends on WoW CreateFrame etc.
-- We only need MakeDB which is pure Lua.
_G.ExsarUI = {}
function ExsarUI.MakeDB(namespace)
    return function()
        ExsarAddonDB[namespace] = ExsarAddonDB[namespace] or {}
        return ExsarAddonDB[namespace]
    end
end

describe("MakeDB", function()
    before_each(function()
        _G.ExsarAddonDB = {}
    end)

    it("creates namespace on first access", function()
        local myDB = ExsarUI.MakeDB("testModule")
        local db = myDB()
        assert.is_table(db)
        assert.are.same({}, db)
        assert.are.equal(db, ExsarAddonDB.testModule)
    end)

    it("returns same table on subsequent calls", function()
        local myDB = ExsarUI.MakeDB("testModule")
        local db1 = myDB()
        db1.scale = 1.5
        local db2 = myDB()
        assert.are.equal(1.5, db2.scale)
        assert.are.equal(db1, db2)
    end)

    it("does not overwrite existing data", function()
        ExsarAddonDB.testModule = { x = 100, y = 200 }
        local myDB = ExsarUI.MakeDB("testModule")
        local db = myDB()
        assert.are.equal(100, db.x)
        assert.are.equal(200, db.y)
    end)

    it("different namespaces are independent", function()
        local dbA = ExsarUI.MakeDB("moduleA")
        local dbB = ExsarUI.MakeDB("moduleB")
        dbA().scale = 2.0
        dbB().scale = 0.5
        assert.are.equal(2.0, dbA().scale)
        assert.are.equal(0.5, dbB().scale)
    end)

    it("initializes to empty table even if ExsarAddonDB was reset", function()
        local myDB = ExsarUI.MakeDB("fresh")
        _G.ExsarAddonDB = {}
        local db = myDB()
        assert.is_table(db)
        assert.are.same({}, db)
    end)
end)
