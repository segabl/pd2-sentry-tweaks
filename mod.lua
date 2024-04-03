if RequiredScript == "lib/units/equipment/sentry_gun/sentrygunbase" then

	-- Make attach raycast consistent with PlayerEquipment.valid_shape_placement raycast
	Hooks:OverrideFunction(SentryGunBase, "_attach", function(pos, rot, sentrygun_unit)
		pos = pos or sentrygun_unit:position()
		rot = rot or sentrygun_unit:rotation()
		local from_pos = pos + rot:z() * 10
		local to_pos = pos + rot:z() * -20
		local ray

		if sentrygun_unit then
			ray = sentrygun_unit:raycast("ray", from_pos, to_pos, "slot_mask", managers.slot:get_mask("trip_mine_placeables"), "ray_type", "equipment_placement")
		else
			ray = World:raycast("ray", from_pos, to_pos, "slot_mask", managers.slot:get_mask("trip_mine_placeables"), "ray_type", "equipment_placement")
		end

		if ray then
			return {
				max_index = 3,
				index = 1,
				body = ray.body,
				position = ray.body:position(),
				rotation = ray.body:rotation(),
				unit = ray.unit
			}
		end
	end)

elseif RequiredScript == "lib/units/equipment/sentry_gun/sentrygunbrain" then

	-- Make enemies more likely to ignore the silent sentry when there are other targets to shoot and reduce the ammo waste during rotation
	Hooks:PostHook(SentryGunBrain, "setup", "setup_sentry_tweaks", function(self, shaprness_mul)
		if self._ext_movement:team().id == "criminal1" then
			self._criminal_sentry = true
			self._shaprness_mul = shaprness_mul * 0.1
			if Network:is_server() and self._unit:name() == tweak_data.equipments.sentry_id_strings[2] then
				PlayerMovement.set_attention_settings(self, {
					"sentry_gun_enemy_cbt_hacked"
				})
			end
		end
	end)

	-- Reduce firing range for non AP sentry
	Hooks:PostHook(SentryGunBrain, "_upd_detection", "_upd_detection_sentry_tweaks", function(self)
		if not self._criminal_sentry then
			return
		end

		local my_team = self._ext_movement:team()
		for u_key, attention_info in pairs(self._detected_attention_objects) do
			local anim_data = alive(attention_info.unit) and attention_info.unit:anim_data()
			local harmless = anim_data and (anim_data.hands_back or anim_data.surrender or anim_data.hands_tied)
			local not_enemy = not attention_info.has_team or not my_team.foes[attention_info.unit:movement():team().id]
			local out_of_range = attention_info.dis > self._tweak_data.DETECTION_RANGE * (self._ap_bullets and 2 or 0.4)
			if harmless or not_enemy or out_of_range then
				self:_destroy_detected_attention_object_data(attention_info)
			end
		end
	end)

elseif RequiredScript == "lib/units/weapons/sentrygunweapon" then

	-- Double sentry ammo (AP uses more ammo, see further below)
	tweak_data.upgrades.sentry_gun_base_ammo = math.max(tweak_data.upgrades.sentry_gun_base_ammo, 250)

	-- Make sentries able to shoot through bots and hostages
	Hooks:PostHook(SentryGunWeapon, "setup", "setup_sentry_tweaks", function(self)
		if self._unit:movement():team().id == "criminal1" then
			self._criminal_sentry = true
			self._bullet_slotmask = self._bullet_slotmask - World:make_slot_mask(16, 22)
		end
	end)

	-- Make AP more accurate but slower and use 2x the amount of ammo
	SentryGunWeapon._AP_ROUNDS_FIRE_RATE = 4

	Hooks:PostHook(SentryGunWeapon, "_set_fire_mode", "_set_fire_mode_sentry_tweaks", function(self, use_armor_piercing)
		if self._criminal_sentry and self._setup and self._setup.spread_mul then
			self._spread_mul = self._setup.spread_mul * (use_armor_piercing and 0.1 or 1)
		end
	end)

	local change_ammo = SentryGunWeapon.change_ammo
	function SentryGunWeapon:change_ammo(amount, ...)
		change_ammo(self, math.max(amount < 0 and self._criminal_sentry and self._use_armor_piercing and amount * 2.5 or amount, -self._ammo_total), ...)
	end

elseif RequiredScript == "lib/units/beings/player/playerequipment" then

	-- Allow placing sentries facing towards you by holding the sprint key while placing it
	local use_sentry_gun = PlayerEquipment.use_sentry_gun
	function PlayerEquipment:use_sentry_gun(selected_index, unit_idstring_index, ...)
		-- Work around a bug where clients can't place any more sentries when host doesn't spawn the previously requested one
		-- If it's been 5 seconds since the last attempt, stop waiting for the server to send a sentry placement result
		if self._sentrygun_placement_requested and self._sentrygun_placement_requested_t and self._sentrygun_placement_requested_t + 5 < TimerManager:game():time() then
			self._sentrygun_placement_requested = nil
			self._sentrygun_placement_requested_t = nil
		end

		self._deploying_sentry = true
		local result = use_sentry_gun(self, selected_index, unit_idstring_index, ...)
		self._deploying_sentry = false

		if self._sentrygun_placement_requested and not self._sentrygun_placement_requested_t then
			self._sentrygun_placement_requested_t = TimerManager:game():time()
		end

		return result
	end

	local _m_deploy_rot = PlayerEquipment._m_deploy_rot
	function PlayerEquipment:_m_deploy_rot(...)
		local rot = _m_deploy_rot(self, ...)

		if self._deploying_sentry and self._unit:base():controller():get_input_bool("run") then
			return Rotation(rot:yaw() + 180, 0, 0)
		end

		return rot
	end

	local valid_shape_placement = PlayerEquipment.valid_shape_placement
	function PlayerEquipment:valid_shape_placement(equipment_id, equipment_data, ...)
		local valid, ray = valid_shape_placement(self, equipment_id, equipment_data, ...)

		if valid and alive(self._dummy_unit) and string.find(equipment_id or "", "^sentry_gun") and self._unit:base():controller():get_input_bool("run") then
			self._dummy_unit:set_rotation(Rotation(self._unit:movement():m_head_rot():yaw() + 180, 0, 0))
		end

		return valid, ray
	end

end
