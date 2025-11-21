local mod = dmhub.GetModLoading()

function creatureIsRetainer()
    return false
end

function monster:IsRetainer()
    return self:try_get("retainer", false)
end

creature.RegisterSymbol {
    symbol = "retainer",
    lookup = function(c)
        return c:IsRetainer()
    end,
    help = {
        name = "Retainer",
        type = "boolean",
        desc = "If this creature is a retainer, this will be true.",
        seealso = {},
    },
}