/obj/item/clothing
	name = "clothing"
	resistance_flags = FLAMMABLE
	max_integrity = 200
	integrity_failure = 0.4
	var/damaged_clothes = 0 //similar to machine's BROKEN stat and structure's broken var
	///What level of bright light protection item has.
	var/flash_protect = FLASH_PROTECTION_NONE
	var/tint = 0				//Sets the item's level of visual impairment tint, normally set to the same as flash_protect
	var/up = 0					//but separated to allow items to protect but not impair vision, like space helmets
	var/visor_flags = 0			//flags that are added/removed when an item is adjusted up/down
	var/visor_flags_inv = 0		//same as visor_flags, but for flags_inv
	var/visor_flags_cover = 0	//same as above, but for flags_cover
//what to toggle when toggled with weldingvisortoggle()
	var/visor_vars_to_toggle = VISOR_FLASHPROTECT | VISOR_TINT | VISOR_VISIONFLAGS | VISOR_DARKNESSVIEW | VISOR_INVISVIEW
	lefthand_file = 'icons/mob/inhands/clothing_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/clothing_righthand.dmi'
	var/alt_desc = null
	var/toggle_message = null
	var/alt_toggle_message = null
	var/active_sound = null
	var/toggle_cooldown = null
	var/cooldown = 0
	var/clothing_flags = NONE

	var/cuttable = FALSE //If you can cut the clothing with anything sharp
	var/clothamnt = 0 //How much cloth

	/// What items can be consumed to repair this clothing (must by an /obj/item/stack)
	var/repairable_by = /obj/item/stack/sheet/cloth

	//Var modification - PLEASE be careful with this I know who you are and where you live
	var/list/user_vars_to_edit //VARNAME = VARVALUE eg: "name" = "butts"
	var/list/user_vars_remembered //Auto built by the above + dropped() + equipped()

	var/pocket_storage_component_path

	//These allow head/mask items to dynamically alter the user's hair
	// and facial hair, checking hair_extensions.dmi and facialhair_extensions.dmi
	// for a state matching hair_state+dynamic_hair_suffix
	// THESE OVERRIDE THE HIDEHAIR FLAGS
	var/dynamic_hair_suffix = ""//head > mask for head hair
	var/dynamic_fhair_suffix = ""//mask > head for facial hair

	///These are armor values that protect the wearer, taken from the clothing's armor datum. List updates on examine because it's currently only used to print armor ratings to chat in Topic().
	var/list/armor_list = list()
	///These are armor values that protect the clothing, taken from its armor datum. List updates on examine because it's currently only used to print armor ratings to chat in Topic().
	var/list/durability_list = list()

	/// How much clothing damage has been dealt to each of the limbs of the clothing, assuming it covers more than one limb
	var/list/damage_by_parts
	/// How much integrity is in a specific limb before that limb is disabled (for use in [/obj/item/clothing/proc/take_damage_zone], and only if we cover multiple zones.) Set to 0 to disable shredding.
	var/limb_integrity = 0
	/// How many zones (body parts, not precise) we have disabled so far, for naming purposes
	var/zones_disabled

/obj/item/clothing/Initialize()
	if((clothing_flags & VOICEBOX_TOGGLABLE))
		actions_types += /datum/action/item_action/toggle_voice_box
	. = ..()
	if(ispath(pocket_storage_component_path))
		LoadComponent(pocket_storage_component_path)

/obj/item/clothing/MouseDrop(atom/over_object)
	. = ..()
	var/mob/M = usr

	if(ismecha(M.loc)) // stops inventory actions in a mech
		return

	if(!M.incapacitated() && loc == M && istype(over_object, /obj/screen/inventory/hand))
		var/obj/screen/inventory/hand/H = over_object
		if(M.putItemFromInventoryInHandIfPossible(src, H.held_index))
			add_fingerprint(usr)

/obj/item/reagent_containers/food/snacks/clothing
	name = "temporary moth clothing snack item"
	desc = "If you're reading this it means I messed up. This is related to moths eating clothes and I didn't know a better way to do it than making a new food object."
	list_reagents = list(/datum/reagent/consumable/nutriment = 1)
	tastes = list("dust" = 1, "lint" = 1)
	foodtype = CLOTH

/obj/item/clothing/attack(mob/M, mob/user, def_zone)
	if(user.a_intent != INTENT_HARM && ismoth(M))
		if(damaged_clothes == CLOTHING_SHREDDED)
			to_chat(user, "<span class='notice'>[src] seem[p_s()] pretty torn apart... [p_they(TRUE)] probably wouldn't be too tasty.</span>")
			return
		var/obj/item/reagent_containers/food/snacks/clothing/clothing_as_food = new
		clothing_as_food.name = name
		if(clothing_as_food.attack(M, user, def_zone))
			take_damage(15, sound_effect=FALSE)
		qdel(clothing_as_food)
	else
		return ..()

/obj/item/clothing/attackby(obj/item/W, mob/user, params)
	if(W.get_sharpness() && cuttable)
		if (alert(user, "Are you sure you want to cut the [src] into strips?", "Cut clothing:", "Yes", "No") != "Yes")
			return
		playsound(src.loc, 'sound/items/poster_ripped.ogg', 100, TRUE)
		to_chat(user, "<span class='notice'>You cut the [src] into strips with [W].</span>")
		var/obj/item/stack/sheet/cloth/C = new (get_turf(src), clothamnt)
		user.put_in_hands(C)
		qdel(src)

	if(damaged_clothes && istype(W, repairable_by))
		var/obj/item/stack/S = W
		switch(damaged_clothes)
			if(CLOTHING_DAMAGED)
				S.use(1)
				repair(user, params)
			if(CLOTHING_SHREDDED)
				if(S.amount < 3)
					to_chat(user, "<span class='warning'>You require 3 [S.name] to repair [src].</span>")
					return
				to_chat(user, "<span class='notice'>You begin fixing the damage to [src] with [S]...</span>")
				if(do_after(user, 6 SECONDS, TRUE, src))
					if(S.use(3))
						repair(user, params)
		return 1
	return ..()

/// Set the clothing's integrity back to 100%, remove all damage to bodyparts, and generally fix it up
/obj/item/clothing/proc/repair(mob/user, params)
	update_clothes_damaged_state(CLOTHING_PRISTINE)
	obj_integrity = max_integrity
	name = initial(name) // remove "tattered" or "shredded" if there's a prefix
	body_parts_covered = initial(body_parts_covered)
	slot_flags = initial(slot_flags)
	damage_by_parts = null
	if(user)
		UnregisterSignal(user, COMSIG_MOVABLE_MOVED)
		to_chat(user, "<span class='notice'>You fix the damage on [src].</span>")

/**
  * take_damage_zone() is used for dealing damage to specific bodyparts on a worn piece of clothing, meant to be called from [/obj/item/bodypart/proc/check_woundings_mods()]
  *
  *	This proc only matters when a bodypart that this clothing is covering is harmed by a direct attack (being on fire or in space need not apply), and only if this clothing covers
  * more than one bodypart to begin with. No point in tracking damage by zone for a hat, and I'm not cruel enough to let you fully break them in a few shots.
  * Also if limb_integrity is 0, then this clothing doesn't have bodypart damage enabled so skip it.
  *
  * Arguments:
  * * def_zone: The bodypart zone in question
  * * damage_amount: Incoming damage
  * * damage_type: BRUTE or BURN
  * * armour_penetration: If the attack had armour_penetration
  */
/obj/item/clothing/proc/take_damage_zone(def_zone, damage_amount, damage_type, armour_penetration)
	if(!def_zone || !limb_integrity || (initial(body_parts_covered) in GLOB.bitflags)) // the second check sees if we only cover one bodypart anyway and don't need to bother with this
		return
	var/list/covered_limbs = body_parts_covered2organ_names(body_parts_covered) // what do we actually cover?
	if(!(def_zone in covered_limbs))
		return

	var/damage_dealt = take_damage(damage_amount * 0.1, damage_type, armour_penetration, FALSE) * 10 // only deal 10% of the damage to the general integrity damage, then multiply it by 10 so we know how much to deal to limb
	LAZYINITLIST(damage_by_parts)
	damage_by_parts[def_zone] += damage_dealt
	if(damage_by_parts[def_zone] > limb_integrity)
		disable_zone(def_zone, damage_type)

/**
  * disable_zone() is used to disable a given bodypart's protection on our clothing item, mainly from [/obj/item/clothing/proc/take_damage_zone()]
  *
  * This proc disables all protection on the specified bodypart for this piece of clothing: it'll be as if it doesn't cover it at all anymore (because it won't!)
  * If every possible bodypart has been disabled on the clothing, we put it out of commission entirely and mark it as shredded, whereby it will have to be repaired in
  * order to equip it again. Also note we only consider it damaged if there's more than one bodypart disabled.
  *
  * Arguments:
  * * def_zone: The bodypart zone we're disabling
  * * damage_type: Only really relevant for the verb for describing the breaking, and maybe obj_destruction()
  */
/obj/item/clothing/proc/disable_zone(def_zone, damage_type)
	var/list/covered_limbs = body_parts_covered2organ_names(body_parts_covered)
	if(!(def_zone in covered_limbs))
		return

	var/zone_name = parse_zone(def_zone)
	var/break_verb = ((damage_type == BRUTE) ? "torn" : "burned")

	if(iscarbon(loc))
		var/mob/living/carbon/C = loc
		C.visible_message("<span class='danger'>The [zone_name] on [C]'s [src.name] is [break_verb] away!</span>", "<span class='userdanger'>The [zone_name] on your [src.name] is [break_verb] away!</span>", vision_distance = COMBAT_MESSAGE_RANGE)
		RegisterSignal(C, COMSIG_MOVABLE_MOVED, .proc/bristle)

	zones_disabled++
	for(var/i in zone2body_parts_covered(def_zone))
		body_parts_covered &= ~i

	if(body_parts_covered == NONE) // if there are no more parts to break then the whole thing is kaput
		obj_destruction((damage_type == BRUTE ? "melee" : "laser")) // melee/laser is good enough since this only procs from direct attacks anyway and not from fire/bombs
		return

	switch(zones_disabled)
		if(1)
			name = "damaged [initial(name)]"
		if(2)
			name = "mangy [initial(name)]"
		if(3 to INFINITY) // take better care of your shit, dude
			name = "tattered [initial(name)]"

	update_clothes_damaged_state(CLOTHING_DAMAGED)

/obj/item/clothing/Destroy()
	user_vars_remembered = null //Oh god somebody put REFERENCES in here? not to worry, we'll clean it up
	return ..()

/obj/item/clothing/dropped(mob/user)
	..()
	if(!istype(user))
		return
	UnregisterSignal(user, COMSIG_MOVABLE_MOVED)
	if(LAZYLEN(user_vars_remembered))
		for(var/variable in user_vars_remembered)
			if(variable in user.vars)
				if(user.vars[variable] == user_vars_to_edit[variable]) //Is it still what we set it to? (if not we best not change it)
					user.vars[variable] = user_vars_remembered[variable]
		user_vars_remembered = initial(user_vars_remembered) // Effectively this sets it to null.

/obj/item/clothing/equipped(mob/user, slot)
	..()
	if (!istype(user))
		return
	if(slot_flags & slot) //Was equipped to a valid slot for this item?
		if(iscarbon(user) && LAZYLEN(zones_disabled))
			RegisterSignal(user, COMSIG_MOVABLE_MOVED, .proc/bristle)
		if (LAZYLEN(user_vars_to_edit))
			for(var/variable in user_vars_to_edit)
				if(variable in user.vars)
					LAZYSET(user_vars_remembered, variable, user.vars[variable])
					user.vv_edit_var(variable, user_vars_to_edit[variable])

	if((HIDEJUMPSUIT in flags_inv) || (LEGS & body_parts_covered))	//WS start - Digitigrade magboots
		var/mob/living/carbon/human/H = user
		if(H.get_item_by_slot(ITEM_SLOT_FEET))
			var/obj/item/clothing/shoes/S = H.get_item_by_slot(ITEM_SLOT_FEET)
			if(("legs" in H.dna.species.mutant_bodyparts) && H.dna.features["legs"] == "Digitigrade Legs")
				if((DIGITIGRADE_SHOE & S.obj_flags) || (DIGITIGRADE_COMPATIBLE & S.obj_flags))
					S.digi_alt(H, 1)								//WS end - Digitigrade magboots

/obj/item/clothing/examine(mob/user)
	. = ..()
	if(damaged_clothes == CLOTHING_SHREDDED)
		. += "<span class='warning'><b>[p_theyre(TRUE)] completely shredded and require[p_s()] mending before [p_they()] can be worn again!</b></span>"
		return

	switch (max_heat_protection_temperature)
		if (400 to 1000)
			. += "[src] offers the wearer limited protection from fire."
		if (1001 to 1600)
			. += "[src] offers the wearer some protection from fire."
		if (1601 to 35000)
			. += "[src] offers the wearer robust protection from fire."

	for(var/zone in damage_by_parts)
		var/pct_damage_part = damage_by_parts[zone] / limb_integrity * 100
		var/zone_name = parse_zone(zone)
		switch(pct_damage_part)
			if(100 to INFINITY)
				. += "<span class='warning'><b>The [zone_name] is useless and requires mending!</b></span>"
			if(60 to 99)
				. += "<span class='warning'>The [zone_name] is heavily shredded!</span>"
			if(30 to 59)
				. += "<span class='danger'>The [zone_name] is partially shredded.</span>"

	var/datum/component/storage/pockets = GetComponent(/datum/component/storage)
	if(pockets)
		var/list/how_cool_are_your_threads = list("<span class='notice'>")
		if(pockets.attack_hand_interact)
			how_cool_are_your_threads += "[src]'s storage opens when clicked.\n"
		else
			how_cool_are_your_threads += "[src]'s storage opens when dragged to yourself.\n"
		if (pockets.can_hold?.len) // If pocket type can hold anything, vs only specific items
			how_cool_are_your_threads += "[src] can store [pockets.max_items] <a href='?src=[REF(src)];show_valid_pocket_items=1'>item\s</a>.\n"
		else
			how_cool_are_your_threads += "[src] can store [pockets.max_items] item\s that are [weightclass2text(pockets.max_w_class)] or smaller.\n"
		if(pockets.quickdraw)
			how_cool_are_your_threads += "You can quickly remove an item from [src] using Alt-Click.\n"
		if(pockets.silent)
			how_cool_are_your_threads += "Adding or removing items from [src] makes no noise.\n"
		how_cool_are_your_threads += "</span>"
		. += how_cool_are_your_threads.Join()

	if(LAZYLEN(armor_list))
		armor_list.Cut()
	if(armor.bio)
		armor_list += list("TOXIN" = armor.bio)
	if(armor.bomb)
		armor_list += list("EXPLOSIVE" = armor.bomb)
	if(armor.bullet)
		armor_list += list("BULLET" = armor.bullet)
	if(armor.energy)
		armor_list += list("ENERGY" = armor.energy)
	if(armor.laser)
		armor_list += list("LASER" = armor.laser)
	if(armor.magic)
		armor_list += list("MAGIC" = armor.magic)
	if(armor.melee)
		armor_list += list("MELEE" = armor.melee)
	if(armor.rad)
		armor_list += list("RADIATION" = armor.rad)

	if(LAZYLEN(durability_list))
		durability_list.Cut()
	if(armor.fire)
		durability_list += list("FIRE" = armor.fire)
	if(armor.acid)
		durability_list += list("ACID" = armor.acid)

	if(LAZYLEN(armor_list) || LAZYLEN(durability_list))
		. += "<span class='notice'>It has a <a href='?src=[REF(src)];list_armor=1'>tag</a> listing its protection classes.</span>"

/obj/item/clothing/Topic(href, href_list)
	. = ..()

	if(href_list["list_armor"])
		var/list/readout = list("<span class='notice'><u><b>PROTECTION CLASSES (I-X)</u></b>")
		if(LAZYLEN(armor_list))
			readout += "\n<b>ARMOR</b>"
			for(var/dam_type in armor_list)
				var/armor_amount = armor_list[dam_type]
				readout += "\n[dam_type] [armor_to_protection_class(armor_amount)]" //e.g. BOMB IV
		if(LAZYLEN(durability_list))
			readout += "\n<b>DURABILITY</b>"
			for(var/dam_type in durability_list)
				var/durability_amount = durability_list[dam_type]
				readout += "\n[dam_type] [armor_to_protection_class(durability_amount)]" //e.g. FIRE II
		readout += "</span>"

		to_chat(usr, "[readout.Join()]")

/**
  * Rounds armor_value to nearest 10, divides it by 10 and then expresses it in roman numerals up to 10
  *
  * Rounds armor_value to nearest 10, divides it by 10
  * and then expresses it in roman numerals up to 10
  * Arguments:
  * * armor_value - Number we're converting
  */
/obj/item/clothing/proc/armor_to_protection_class(armor_value)
	armor_value = round(armor_value,10) / 10
	switch (armor_value)
		if (1)
			. = "I"
		if (2)
			. = "II"
		if (3)
			. = "III"
		if (4)
			. = "IV"
		if (5)
			. = "V"
		if (6)
			. = "VI"
		if (7)
			. = "VII"
		if (8)
			. = "VIII"
		if (9)
			. = "IX"
		if (10 to INFINITY)
			. = "X"
	return .

/obj/item/clothing/obj_break(damage_flag)
	update_clothes_damaged_state(CLOTHING_DAMAGED)

	if(isliving(loc)) //It's not important enough to warrant a message if it's not on someone
		var/mob/living/M = loc
		if(src in M.get_equipped_items(FALSE))
			to_chat(M, "<span class='warning'>Your [name] start[p_s()] to fall apart!</span>")
		else
			to_chat(M, "<span class='warning'>[src] start[p_s()] to fall apart!</span>")

//This mostly exists so subtypes can call appriopriate update icon calls on the wearer.
/obj/item/clothing/proc/update_clothes_damaged_state()
	return

/obj/item/clothing/update_overlays()
	. = ..()
	var/index = "[REF(initial(icon))]-[initial(icon_state)]"
	var/static/list/damaged_clothes_icons = list()
	if(damaged_clothes)
		var/icon/damaged_clothes_icon = damaged_clothes_icons[index]
		if(!damaged_clothes_icon)
			damaged_clothes_icon = icon(initial(icon), initial(icon_state), , 1)	//we only want to apply damaged effect to the initial icon_state for each object
			damaged_clothes_icon.Blend("#fff", ICON_ADD) 	//fills the icon_state with white (except where it's transparent)
			damaged_clothes_icon.Blend(icon('icons/effects/item_damage.dmi', "itemdamaged"), ICON_MULTIPLY) //adds damage effect and the remaining white areas become transparant
			damaged_clothes_icon = fcopy_rsc(damaged_clothes_icon)
			damaged_clothes_icons[index] = damaged_clothes_icon
		add_overlay(damaged_clothes_icon, 1)
	else
		damaged_clothes = 0
		cut_overlay(damaged_clothes_icons[index], TRUE)


/*
SEE_SELF  // can see self, no matter what
SEE_MOBS  // can see all mobs, no matter what
SEE_OBJS  // can see all objs, no matter what
SEE_TURFS // can see all turfs (and areas), no matter what
SEE_PIXELS// if an object is located on an unlit area, but some of its pixels are
          // in a lit area (via pixel_x,y or smooth movement), can see those pixels
BLIND     // can't see anything
*/

/proc/generate_female_clothing(index,t_color,icon,type)
	var/icon/female_clothing_icon	= icon("icon"=icon, "icon_state"=t_color)
	var/icon/female_s				= icon("icon"='icons/mob/clothing/under/masking_helpers.dmi', "icon_state"="[(type == FEMALE_UNIFORM_FULL) ? "female_full" : "female_top"]")
	female_clothing_icon.Blend(female_s, ICON_MULTIPLY)
	female_clothing_icon 			= fcopy_rsc(female_clothing_icon)
	GLOB.female_clothing_icons[index] = female_clothing_icon

/obj/item/clothing/under/verb/toggle()
	set name = "Adjust Suit Sensors"
	set category = "Object"
	set src in usr
	var/mob/M = usr
	if (istype(M, /mob/dead/))
		return
	if (!can_use(M))
		return
	if(src.has_sensor == LOCKED_SENSORS)
		to_chat(usr, "The controls are locked.")
		return 0
	if(src.has_sensor == BROKEN_SENSORS)
		to_chat(usr, "The sensors have shorted out!")
		return 0
	if(src.has_sensor <= NO_SENSORS)
		to_chat(usr, "This suit does not have any sensors.")
		return 0

	var/list/modes = list("Off", "Binary vitals", "Exact vitals", "Tracking beacon")
	var/switchMode = input("Select a sensor mode:", "Suit Sensor Mode", modes[sensor_mode + 1]) in modes
	if(get_dist(usr, src) > 1)
		to_chat(usr, "<span class='warning'>You have moved too far away!</span>")
		return
	sensor_mode = modes.Find(switchMode) - 1

	if (src.loc == usr)
		switch(sensor_mode)
			if(0)
				to_chat(usr, "<span class='notice'>You disable your suit's remote sensing equipment.</span>")
			if(1)
				to_chat(usr, "<span class='notice'>Your suit will now only report whether you are alive or dead.</span>")
			if(2)
				to_chat(usr, "<span class='notice'>Your suit will now only report your exact vital lifesigns.</span>")
			if(3)
				to_chat(usr, "<span class='notice'>Your suit will now report your exact vital lifesigns as well as your coordinate position.</span>")

	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		if(H.w_uniform == src)
			H.update_suit_sensors()

/obj/item/clothing/under/attack_hand(mob/user)
	if(attached_accessory && ispath(attached_accessory.pocket_storage_component_path) && loc == user)
		attached_accessory.attack_hand(user)
		return
	..()

/obj/item/clothing/under/AltClick(mob/user)
	if(..())
		return 1

	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE, ismonkey(user)))
		return
	else
		if(attached_accessory)
			remove_accessory(user)
		else
			rolldown()

/obj/item/clothing/under/verb/jumpsuit_adjust()
	set name = "Adjust Jumpsuit Style"
	set category = null
	set src in usr
	rolldown()

/obj/item/clothing/under/proc/rolldown()
	if(!can_use(usr))
		return
	if(!can_adjust)
		to_chat(usr, "<span class='warning'>You cannot wear this suit any differently!</span>")
		return
	if(toggle_jumpsuit_adjust())
		to_chat(usr, "<span class='notice'>You adjust the suit to wear it more casually.</span>")
	else
		to_chat(usr, "<span class='notice'>You adjust the suit back to normal.</span>")
	if(ishuman(usr))
		var/mob/living/carbon/human/H = usr
		H.update_inv_w_uniform()
		H.update_body()

/obj/item/clothing/under/proc/toggle_jumpsuit_adjust()
	if(adjusted == DIGITIGRADE_STYLE)
		return
	adjusted = !adjusted
	if(adjusted)
		if(fitted != FEMALE_UNIFORM_TOP)
			fitted = NO_FEMALE_UNIFORM
		if(!alt_covers_chest) // for the special snowflake suits that expose the chest when adjusted (and also the arms, realistically)
			body_parts_covered &= ~CHEST
			body_parts_covered &= ~ARMS
	else
		fitted = initial(fitted)
		if(!alt_covers_chest)
			body_parts_covered |= CHEST
			body_parts_covered |= ARMS
			if(!LAZYLEN(damage_by_parts))
				return adjusted
			for(var/zone in list(BODY_ZONE_CHEST, BODY_ZONE_L_ARM, BODY_ZONE_R_ARM)) // ugly check to make sure we don't reenable protection on a disabled part
				if(damage_by_parts[zone] > limb_integrity)
					for(var/part in zone2body_parts_covered(zone))
						body_parts_covered &= part
	return adjusted

/obj/item/clothing/proc/weldingvisortoggle(mob/user) //proc to toggle welding visors on helmets, masks, goggles, etc.
	if(!can_use(user))
		return FALSE

	visor_toggling()

	to_chat(user, "<span class='notice'>You adjust \the [src] [up ? "up" : "down"].</span>")

	if(iscarbon(user))
		var/mob/living/carbon/C = user
		C.head_update(src, forced = 1)
	for(var/X in actions)
		var/datum/action/A = X
		A.UpdateButtonIcon()
	return TRUE

/obj/item/clothing/proc/visor_toggling() //handles all the actual toggling of flags
	up = !up
	clothing_flags ^= visor_flags
	flags_inv ^= visor_flags_inv
	flags_cover ^= initial(flags_cover)
	icon_state = "[initial(icon_state)][up ? "up" : ""]"
	if(visor_vars_to_toggle & VISOR_FLASHPROTECT)
		flash_protect ^= initial(flash_protect)
	if(visor_vars_to_toggle & VISOR_TINT)
		tint ^= initial(tint)

/obj/item/clothing/head/helmet/space/plasmaman/visor_toggling() //handles all the actual toggling of flags
	up = !up
	clothing_flags ^= visor_flags
	flags_inv ^= visor_flags_inv
	icon_state = "[initial(icon_state)]"
	if(visor_vars_to_toggle & VISOR_FLASHPROTECT)
		flash_protect ^= initial(flash_protect)
	if(visor_vars_to_toggle & VISOR_TINT)
		tint ^= initial(tint)

/obj/item/clothing/proc/can_use(mob/user)
	if(user && ismob(user))
		if(!user.incapacitated())
			return 1
	return 0


/obj/item/clothing/obj_destruction(damage_flag)
	if(damage_flag == "bomb" || damage_flag == "melee")
		var/turf/T = get_turf(src)
		//so the shred survives potential turf change from the explosion.
		addtimer(CALLBACK_NEW(/obj/effect/decal/cleanable/shreds, list(T, name)), 1)
		deconstruct(FALSE)
	else if(!(damage_flag in list("acid", "fire")))
		body_parts_covered = NONE
		slot_flags = NONE
		update_clothes_damaged_state(CLOTHING_SHREDDED)
		if(isliving(loc))
			var/mob/living/M = loc
			if(src in M.get_equipped_items(FALSE)) //make sure they were wearing it and not attacking the item in their hands / eating it if they were a moth.
				M.visible_message("<span class='danger'>[M]'s [src.name] fall[p_s()] off, [p_theyre()] completely shredded!</span>", "<span class='warning'><b>Your [src.name] fall[p_s()] off, [p_theyre()] completely shredded!</b></span>", vision_distance = COMBAT_MESSAGE_RANGE)
				M.dropItemToGround(src)
			else
				M.visible_message("<span class='danger'>[src] fall[p_s()] apart, completely shredded!</span>", vision_distance = COMBAT_MESSAGE_RANGE)
		name = "shredded [initial(name)]" // change the name -after- the message, not before.
	else
		..()

/// If we're a clothing with at least 1 shredded/disabled zone, give the wearer a periodic heads up letting them know their clothes are damaged
/obj/item/clothing/proc/bristle(mob/living/L)
	if(!istype(L))
		return
	if(prob(0.2))
		to_chat(L, "<span class='warning'>The damaged threads on your [src.name] chafe!</span>")
