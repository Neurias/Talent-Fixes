--- Fix Sadist when LeaderLib is not active
---@param e EsvLuaComputeCharacterHitEvent
local function ApplySadist(e)
	local totalDamage = 0
	for i,damage in pairs(e.DamageList:ToTable()) do
		totalDamage = totalDamage + damage.Amount
	end
	local statusBonusDmgTypes = {}
	if e.Hit.Poisoned then
		table.insert(statusBonusDmgTypes, "Poison")
	end
	if e.Hit.Burning or e.Target.Character:GetStatus("NECROFIRE") then
		table.insert(statusBonusDmgTypes, "Fire")
	end
	if e.Hit.Bleeding then
		table.insert(statusBonusDmgTypes, "Physical")
	end
	local damageList = e.Hit.DamageList
	local damageBonus = math.ceil(totalDamage * 0.1)
	for i,damageType in pairs(statusBonusDmgTypes) do
		damageList:Add(damageType, damageBonus)
	end
	e.DamageList:Merge(damageList)
	e.Hit.ArmorAbsorption = Game.Math.ComputeArmorDamage(damageList, e.Target.CurrentArmor)
	e.Hit.ArmorAbsorption = e.Hit.ArmorAbsorption + Game.Math.ComputeMagicArmorDamage(damageList, e.Target.CurrentMagicArmor)
	--if not Mods.LeaderLib then
        Game.Math.ComputeCharacterHit(e.Target, e.Attacker, e.Weapon, e.DamageList, e.HitType, e.NoHitRoll, e.ForceReduceDurability, e.Hit, e.AlwaysBackstab, e.HighGround, e.CriticalRoll)
    --end
	if not e.Handled then
		e.Handled = true
	end
end

local function CCH_SadistFix(e)
	if e.Attacker and e.Attacker.TALENT_Sadist then
		-- Fix Sadist for melee skills that doesn't have UseCharacterStats = Yes
		if e.HitType == "WeaponDamage" and not Game.Math.IsRangedWeapon(e.Attacker.MainWeapon) and e.Hit.HitWithWeapon then
			ApplySadist(e)
		-- Fix Sadist for Necrofire
		elseif e.HitType == "Melee" and e.Target.Character:GetStatus("NECROFIRE") then
			ApplySadist(e)
		end
	end
end

local function DoHit(hit, damageList, statusBonusDmgTypes, hitType, target, attacker, ctx)
    hit.Hit = true;
    damageList:AggregateSameTypeDamages()
    if type(ctx) == "number" then
        damageList:Multiply(ctx)
    else
        damageList:Multiply(ctx.DamageMultiplier)
    end

    local totalDamage = 0
    for i,damage in pairs(damageList:ToTable()) do
        totalDamage = totalDamage + damage.Amount
    end

    if totalDamage < 0 then
        damageList:Clear()
    end

    Game.Math.ApplyDamageCharacterBonuses(target, attacker, damageList)
    damageList:AggregateSameTypeDamages()
    hit.DamageList:Clear()

    for i,damageType in pairs(statusBonusDmgTypes) do
        damageList:Add(damageType, math.ceil(totalDamage * 0.1))
    end

    Game.Math.ApplyDamagesToHitInfo(damageList, hit)
    hit.ArmorAbsorption = hit.ArmorAbsorption + Game.Math.ComputeArmorDamage(damageList, target.CurrentArmor)
    hit.ArmorAbsorption = hit.ArmorAbsorption + Game.Math.ComputeMagicArmorDamage(damageList, target.CurrentMagicArmor)

    if hit.TotalDamageDone > 0 then
        Game.Math.ApplyLifeSteal(hit, target, attacker, hitType)
    else
        hit.DontCreateBloodSurface = true
    end

    if hitType == "Surface" then
        hit.Surface = true
    end

    if hitType == "DoT" then
        hit.DoT = true
    end
end

 Game.Math.DoHit = DoHit

if Mods.LeaderLib then
	--Mods.LeaderLib.Events.ComputeCharacterHit:Subscribe(CCH_SadistFix)
	--Mods.LeaderLib.HitOverrides.DoHit = DoHit
end
Ext.Events.ComputeCharacterHit:Subscribe(CCH_SadistFix, {Priority=999})

---- Elemental Ranger and Gladiator fix
local surfaceDamageMapping = {
	SurfaceFire = "Fire",
    SurfaceWater = "Water",
    SurfaceWaterFrozen = "Water",
    SurfaceWaterElectrified = "Air",
    SurfaceBlood = "Physical",
    SurfaceBloodElectrified = "Air",
    SurfaceBloodFrozen = "Physical",
    SurfacePoison = "Poison",
    SurfaceOil = "Earth",
    SurfaceLava = "Fire",
	SurfaceFireCursed = "Fire",
	SurfacePoisonCursed = "Poison",
	SurfaceWaterCursed = "Water",
	SurfacePoisonBlessed = "Poison",
	SurfaceWaterBlessed = "Water",
	SurfaceFireBlessed = "Fire",
	SurfaceOilBlessed = "Earth",
	SurfaceWaterFrozenCursed = "Water",
	SurfaceWaterElectrifiedCursed = "Air",
	SurfaceWaterElectrifiedBlessed = "Air",
	SurfaceWaterFrozenBlessed = "Water",
	SurfaceBloodCursed = "Physical",
	SurfaceBloodElectrifiedBlessed = "Air",
    SurfaceBloodFrozenCursed = "Physical",
	SurfaceBloodElectrifiedCursed = "Air",
	SurfaceOilCursed = "Earth",
	SurfaceBloodFrozenBlessed = "Physical",
	SurfaceWeb = "Earth",
	SurfaceWebBlessed = "Earth",
	SurfaceWebCursed = "Earth"
}

--- @param character EsvCharacter
--- @param flag bool
local function SetHasCounterAttacked(character, flag)
    local combat = Ext.ServerEntity.GetCombat(CombatGetIDForCharacter(character.MyGuid))
    for i, team in pairs(combat:GetNextTurnOrder()) do
        if team and team.Character and team.Character.MyGuid == character.MyGuid then
            team.EntityWrapper.CombatComponentPtr.CounterAttacked = flag
        end
    end
end

local function HasCounterAttacked(character)
    local combat = Ext.ServerEntity.GetCombat(CombatGetIDForCharacter(character.MyGuid))
    for i, team in pairs(combat:GetNextTurnOrder()) do
        if team.Character and team.Character.MyGuid == character.MyGuid then
            return team.EntityWrapper.CombatComponentPtr.CounterAttacked
        end
    end
end

local GladiatorTargets = {}

---@param e EsvLuaComputeCharacterHitEvent
Ext.Events.ComputeCharacterHit:Subscribe(function(e)
	--- Elemental Ranger
	if e.Attacker and e.Attacker.TALENT_ElementalRanger and e.HitType == "WeaponDamage" and Game.Math.IsRangedWeapon(e.Attacker.MainWeapon) then
		local surface = GetSurfaceGroundAt(e.Target.Character.MyGuid)
		local dmgType = surfaceDamageMapping[surface]
		if dmgType then
			local totalDamage = 0
			for i,damage in pairs(e.DamageList:ToTable()) do
				totalDamage = totalDamage + damage.Amount
			end
			
			local damageList = Ext.Stats.NewDamageList()
			damageList:CopyFrom(e.DamageList)
			damageList:Add(dmgType, math.ceil(tonumber(totalDamage)*0.2))
			e.DamageList:CopyFrom(damageList)
			e.Hit.ArmorAbsorption = Game.Math.ComputeArmorDamage(damageList, e.Target.CurrentArmor)
			e.Hit.ArmorAbsorption = e.Hit.ArmorAbsorption + Game.Math.ComputeMagicArmorDamage(damageList, e.Target.CurrentMagicArmor)
			if not e.Handled then
				e.Handled = true
			end
			Game.Math.ComputeCharacterHit(e.Target, e.Attacker, e.Weapon, e.DamageList, e.HitType, e.NoHitRoll, e.ForceReduceDurability, e.Hit, e.AlwaysBackstab, e.HighGround, e.CriticalRoll)
		end
		
	--- Gladiator
    elseif e.Attacker and e.Attacker.TALENT_Gladiator and e.NoHitRoll and e.HitType == "Melee" and not e.Hit.HitWithWeapon then
        e.NoHitRoll = false
        local hit = Game.Math.ComputeCharacterHit(e.Target, e.Attacker, e.Weapon, e.DamageList, e.HitType, e.NoHitRoll, e.ForceReduceDurability, e.Hit, e.AlwaysBackstab, e.HighGround, e.CriticalRoll) ---@type EsvStatusHit
        if hit.Missed then
            e.Hit.Hit = false
            e.Hit.DontCreateBloodSurface = true
        end
        e.Hit.CounterAttack = true
        if not e.Handled and hit then
            e.Handled = true
        end
        Osi.ProcObjectTimer(e.Attacker.Character.MyGuid, "LX_GladiatorFollowFix", 1000)
    end
	
		--- Guerilla Fix
	if e.Attacker and e.Attacker.TALENT_SurpriseAttack and e.HitType == "WeaponDamage" then
		local hit = Game.Math.ComputeCharacterHit(e.Target, e.Attacker, e.Weapon, e.DamageList, e.HitType, e.NoHitRoll, e.ForceReduceDurability, e.Hit, e.AlwaysBackstab, e.HighGround, e.CriticalRoll) ---@type EsvStatusHit
        HitHelpers.HitMultiplyDamage(hit, e.Target.Character, e.Attacker.Character, 1 + (Ext.ExtraData.TalentSneakingDamageBonus/100))
		if not e.Handled and hit then
                e.Handled = true
		end
	end
    if IsTagged(e.Target.MyGuid, "LX_IsCounterAttacking") == 1 then
        ClearTag(e.Target.MyGuid, "LX_IsCounterAttacking")
    end
end)
	

---@param e EsvLuaStatusHitEnterEvent
Ext.Events.StatusHitEnter:Subscribe(function(e)
	--- Gladiator
	local target = Ext.Entity.GetCharacter(e.Context.TargetHandle)
	local attacker = Ext.Entity.GetCharacter(e.Context.AttackerHandle)
	if target.Stats.TALENT_Gladiator and (e.Hit.Hit.HitWithWeapon) and not Game.Math.IsRangedWeapon(attacker.Stats.MainWeapon) and target.Stats:GetItemBySlot("Shield") and not e.Hit.Hit.CounterAttack and IsTagged(target.MyGuid, "LX_IsCounterAttacking") == 0 and e.Hit.SkillId ~= "Target_LX_GladiatorHit_-1" and not (e.Hit.Hit.Dodged or e.Hit.Hit.Missed) then
		local counterAttacked = HasCounterAttacked(target)
		if not counterAttacked and GetDistanceTo(target.MyGuid, attacker.MyGuid) <= 5.0 then
			GladiatorTargets[target.MyGuid] = attacker.MyGuid
			SetTag(attacker.MyGuid, "LX_IsCounterAttacking")
			Osi.ProcObjectTimer(target.MyGuid, "LX_GladiatorDelay", 30)
		end
	end
end)

--- @param character GUID
--- @param event string
Ext.Osiris.RegisterListener("ProcObjectTimerFinished", 2, "after", function(character, event)
	if event == "LX_GladiatorDelay" and CharacterIsIncapacitated(character) ~= 1 then
		SetHasCounterAttacked(Ext.ServerEntity.GetCharacter(character), true)
		CharacterUseSkill(character, "Target_LX_GladiatorHit", GladiatorTargets[character], 1, 1, 1)
		GladiatorTargets[character] = nil
	end
end)

--- @param character GUID
--- @param event string
Ext.Osiris.RegisterListener("ProcObjectTimerFinished", 2, "after", function(character, event)
	if event == "LX_GladiatorFollowFix" then
		PlayAnimation(character, "", "")
	end
end)
