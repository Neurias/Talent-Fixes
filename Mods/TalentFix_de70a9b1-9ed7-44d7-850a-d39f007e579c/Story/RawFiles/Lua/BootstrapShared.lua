Helpers = {}
--- @param object IEoCServerObject | IEoCClientObject
Helpers.IsCharacter = function(object)
    if Ext.IsServer() then
        return getmetatable(object) == "esv::Character"
    else
        return getmetatable(object) == "ecl::Character"
    end
end

HitHelpers = {}

damageTypes = {
    "Physical",
    "Piercing",
    "Fire",
    "Air",
    "Water",
    "Earth",
    "Poison",
    "Shadow",
    "Corrosive",
    "Magic"
}

magicDamageTypes = {
    "Fire",
    "Air",
    "Water",
    "Earth",
    "Poison",
    "Magic"
}

physicalDamageTypes = {
    "Physical",
    "Corrosive"
}

--- @param hit StatsHitDamageInfo
HitHelpers.HitGetMagicDamage = function(hit)
    local total = 0
    for i,dmgType in pairs(magicDamageTypes) do
        total = total + hit.DamageList:GetByType(dmgType)
    end
    return total
end

--- @param hit StatsHitDamageInfo
HitHelpers.HitGetPhysicalDamage = function(hit)
    local total = 0
    for i,dmgType in pairs(physicalDamageTypes) do
        total = total + hit.DamageList:GetByType(dmgType)
    end
    return total
end

--- @param hit StatsHitDamageInfo
HitHelpers.HitGetTotalDamage = function(hit)
    local total = 0
    for i,dmgType in pairs(damageTypes) do
        total = total + hit.DamageList:GetByType(dmgType)
    end
    return total
end

--- @param hit StatsHitDamageInfo
--- @param target EsvCharacter
HitHelpers.HitRecalculateAbsorb = function(hit, target)
    if Helpers.IsCharacter(target) then
        local physDmg = HitHelpers.HitGetPhysicalDamage(hit)
        local magicDmg = HitHelpers.HitGetMagicDamage(hit)
        local pArmourAbsorb = math.min(target.Stats.CurrentArmor, physDmg)
        local mArmourAbsorb = math.min(target.Stats.CurrentMagicArmor, magicDmg)
        hit.ArmorAbsorption = math.min(pArmourAbsorb + mArmourAbsorb, hit.TotalDamageDone)
	else
		hit.ArmorAbsorption = 0
    end
end

--- @param hit StatsHitDamageInfo
--- @param target EsvCharacter
--- @param instigator EsvCharacter
HitHelpers.HitRecalculateLifesteal = function(hit, instigator)
    if hit.DoT or hit.Surface then return end
    hit.LifeSteal = math.floor(Ext.Round((instigator.Stats.LifeSteal / 100) * (hit.TotalDamageDone - hit.ArmorAbsorption)))
end

--- @param hit StatsHitDamageInfo
--- @param target EsvCharacter | EsvItem
--- @param instigator EsvCharacter
--- @param damageType string
--- @param amount integer
HitHelpers.HitAddDamage = function(hit, target, instigator, damageType, amount)
    hit.TotalDamageDone = math.ceil(hit.TotalDamageDone + amount)
    hit.DamageList:Add(damageType, amount)
	if Helpers.IsCharacter(target) then
    	HitHelpers.HitRecalculateAbsorb(hit, target)
	else
		hit.ArmorAbsorption = 0
	end
    if instigator ~= nil then
        HitHelpers.HitRecalculateLifesteal(hit, instigator)
    end
end

--- @param hit StatsHitDamageInfo
--- @param target EsvCharacter
HitHelpers.HitMultiplyDamage = function(hit, target, instigator, multiplier)
    hit.DamageList:Multiply(multiplier)
    hit.TotalDamageDone = HitHelpers.HitGetTotalDamage(hit)
    HitHelpers.HitRecalculateAbsorb(hit, target)
    if instigator ~= nil then
        HitHelpers.HitRecalculateLifesteal(hit, instigator)
    end
end