from   collections import Counter
import json
from   math import floor

#TODO figure out SpawnGroup Difficulty
#TODO flesh out manual data

PATH_GAME_BASE = r'D:\games\Infinity Engine\Icewind Dale Enhanced Edition'
path_pristine = PATH_GAME_BASE + '/override.pristine/SPAWNGRP.2da'
path_output = PATH_GAME_BASE + '/override/SPAWNGRP.2da'
DEFAULT_DIFFICULTY = 10 # 10=25/15, 20=15/15, 30=9/15, 40=8/15, 50=9/15, 70=1/15
manual = '''
#AR1200 100 ORCWAXE ORCWBOW ORCEWAXE ORCSHAM OGRE * * *
#AR1200 100 ORCWAXE ORCWBOW ORCEWAXE ORCSHAM OGRE * * *
'''

# Convert enemy list into spawngroup slots
def compute_spawner_slots( enemy_list, num_slots = 8 ):
    '''Given list of enemies, generate a list of exactly 8 slots that approximates the input distribution. Fill empty with *'''
    if not enemy_list: return ['*'] * num_slots

    # Generate initial distribution stats
    counts = Counter( enemy_list )
    total = sum( counts.values() )
    distribution = [] # :: (enemy, ideal frac slots, floored int slots)
    for enemy, count in counts.items():
        ideal = count / total * num_slots # ideal is percent of distrib * num slots
        distribution.append( (enemy, ideal, floor( ideal )) )
    
    used_so_far = sum( [ d[2] for d in distribution ] )

    # sort by larged remainder so we can allocate any leftover slots
    distribution.sort( key = lambda d: d[1] - d[2], reverse = True ) # ideal-floored

    # allocate remaining slots
    leftover = num_slots - used_so_far
    final_counts = {}
    for enemy, ideal_float, floor_val in distribution:
        final_counts[enemy] = floor_val
        
    idx = 0
    while leftover > 0 and idx < len(distribution):
        enemy, ideal_float, floor_val = distribution[idx]
        final_counts[enemy] += 1
        leftover -= 1
        idx += 1
    
    # Construct final slot list
    slots = []
    for enemy, count in final_counts.items():
        slots.extend( [enemy] * count )
    slots.extend( ['*'] * (num_slots - len(slots)) )
    slots = slots[:num_slots]

    return slots
def compute_spawner_slots_with_guarantees_jank_ratio( enemy_list, num_slots=8 ):
    """
    Take a list of enemies (duplicates => more frequent).
    Return exactly `num_slots` slots that:
      1) Attempt to preserve the distribution as best we can.
      2) Guarantee that every distinct enemy appears at least once
         if the total number of distinct enemies <= num_slots.
      3) If we have > num_slots distinct enemies, we drop the ones that are
         least frequent until we have only num_slots distinct enemies.
    
    Returns a list of length `num_slots`. Some may be '*'.
    """
    # Quick exit if empty
    if not enemy_list:
        return ["*"] * num_slots
    
    # Count occurrences
    counts = Counter(enemy_list)
    distinct_enemies = list(counts.keys())
    
    # If there are more distinct enemies than slots, we can't include all.
    # Simple fallback: drop the least common until we only have `num_slots`.
    if len(distinct_enemies) > num_slots:
        # Sort by ascending frequency
        distinct_enemies.sort(key=lambda e: counts[e], reverse=False)
        to_remove = len(distinct_enemies) - num_slots
        for i in range(to_remove):
            enemy_to_remove = distinct_enemies[i]
            del counts[enemy_to_remove]
        # Re-check which remain
        distinct_enemies = list(counts.keys())
    
    # Now we have at most `num_slots` distinct enemies.
    M = len(distinct_enemies)
    
    # If M == 0 (somehow everything got removed?), fill with '*'
    if M == 0:
        return ["*"] * num_slots
    
    total = sum(counts.values())
    
    # 1) Guarantee 1 slot for each distinct enemy
    guaranteed = {enemy: 1 for enemy in distinct_enemies}
    guaranteed_count = M  # total guaranteed so far
    
    # 2) "Use up" 1 occurrence from each enemy for distribution purposes
    adjusted_counts = {}
    for enemy in distinct_enemies:
        adjusted_counts[enemy] = max(counts[enemy] - 1, 0)
    adjusted_sum = sum(adjusted_counts.values())
    
    leftover_slots = num_slots - M
    if leftover_slots <= 0:
        # Edge case: leftover_slots == 0 => exactly one slot per distinct enemy
        # If leftover_slots < 0, something's off, but let's be safe.
        final_slots = list(guaranteed.keys())
        # fill if there's space left for any reason
        while len(final_slots) < num_slots:
            final_slots.append("*")
        return final_slots[:num_slots]
    
    # 3) Distribute leftover slots using the "largest remainder" method
    if adjusted_sum == 0:
        # Means every enemy had exactly 1 count in original data
        # so we used them up. Fill leftover with "*".
        final_slots = []
        for e in distinct_enemies:
            final_slots.append(e)  # each one once
        while len(final_slots) < num_slots:
            final_slots.append("*")
        return final_slots[:num_slots]
    
    # Build data for largest remainder approach
    distribution_list = []
    for e in distinct_enemies:
        fraction = (adjusted_counts[e] / adjusted_sum) * leftover_slots
        floor_val = floor(fraction)
        distribution_list.append((e, fraction, floor_val))
    
    used_so_far = sum(x[2] for x in distribution_list)
    leftover = leftover_slots - used_so_far
    
    # Sort by remainder descending
    distribution_list.sort(key=lambda x: (x[1] - x[2]), reverse=True)
    
    # Distribute leftover one by one
    final_dist = {e: x[2] for (e,_,x) in zip(distinct_enemies, distribution_list, distribution_list)}
    idx = 0
    while leftover > 0 and idx < len(distribution_list):
        e, fraction, floor_val = distribution_list[idx]
        final_dist[e] += 1
        leftover -= 1
        idx += 1
    
    # 4) Combine guaranteed + distributed
    final_slots = []
    for e in distinct_enemies:
        total_slots_for_e = guaranteed[e] + final_dist[e]
        final_slots.extend([e] * total_slots_for_e)
    
    # Fill with '*' if fewer than num_slots
    while len(final_slots) < num_slots:
        final_slots.append("*")
    
    # Truncate extras if we somehow overshot
    final_slots = final_slots[:num_slots]
    
    # (Optional) Shuffle or interleave final_slots if needed.
    
    return final_slots
def compute_spawner_slots_with_guarantees_steal_from_rich( enemy_list, num_slots=8 ):
    """
    Distribute 'num_slots' among the enemies in 'enemy_list' purely by ratio,
    ensuring that if the number of distinct enemies <= num_slots, each enemy
    appears at least once. If there are more than 'num_slots' distinct enemies,
    we drop the least frequent ones first.
    
    Returns a list of exactly 'num_slots' elements (some may be '*').
    """
    if not enemy_list:
        return ["*"] * num_slots

    # --- 1) Count occurrences ---
    counts = Counter(enemy_list)
    distinct_enemies = list(counts.keys())
    total_count = sum(counts.values())

    # --- 2) If more distinct enemies than slots, drop the least frequent ---
    if len(distinct_enemies) > num_slots:
        # Sort ascending by frequency
        distinct_enemies.sort(key=lambda e: counts[e])
        to_remove = len(distinct_enemies) - num_slots
        for i in range(to_remove):
            enemy_to_remove = distinct_enemies[i]
            del counts[enemy_to_remove]
        # Refresh variables
        distinct_enemies = list(counts.keys())
        total_count = sum(counts.values())

    # (Now we have at most 'num_slots' distinct enemies.)
    # If STILL no enemies left, fill with '*'.
    if not distinct_enemies:
        return ["*"] * num_slots

    # --- 3) Pure ratio distribution (floor + largest remainder) ---
    # ideal_count[e] = (counts[e] / total_count) * num_slots
    # We store the floor portion in final_dist[e], then distribute leftover by remainder.
    final_dist = {}
    distribution_data = []
    for e in distinct_enemies:
        fraction = (counts[e] / total_count) * num_slots
        floor_val = floor(fraction)
        distribution_data.append((e, fraction, floor_val))

    # Sum of floors used
    sum_of_floors = sum(x[2] for x in distribution_data)
    leftover = num_slots - sum_of_floors

    # Sort by largest remainder (fraction - floor)
    distribution_data.sort(key=lambda x: (x[1] - x[2]), reverse=True)

    # Initialize final_dist with floors
    for (e, fraction, fl) in distribution_data:
        final_dist[e] = fl

    # Distribute leftover one at a time, from largest remainder to smaller
    idx = 0
    while leftover > 0 and idx < len(distribution_data):
        e, fraction, fl = distribution_data[idx]
        final_dist[e] += 1
        leftover -= 1
        idx += 1

    # --- 4) If any enemy ended up with 0, forcibly reassign from the largest occupant ---
    # (Only do this if #distinct_enemies <= num_slots, so it's actually possible
    # for each to appear at least once.)
    if len(distinct_enemies) <= num_slots:
        zero_enemies = [e for e in distinct_enemies if final_dist[e] == 0]
        for ze in zero_enemies:
            # Find some enemy with > 1 slot from whom we can steal
            # to keep total distribution = num_slots
            # If no such occupant, we can't fix it
            donor = max(distinct_enemies, key=lambda e2: final_dist[e2])
            if final_dist[donor] > 1:
                final_dist[donor] -= 1
                final_dist[ze] = 1
            else:
                # If there's no occupant with more than 1, we cannot fix it further
                # But in practice, if #distinct <= num_slots, this rarely happens
                pass

    # --- 5) Convert the final_dist to a list of slots, fill up to num_slots, etc. ---
    # We might end up with fewer or more than num_slots if there's rounding weirdness,
    # so let's build the list carefully.
    slot_list = []
    for e in final_dist:
        slot_list.extend([e] * final_dist[e])

    # If fewer than num_slots, fill with '*'
    while len(slot_list) < num_slots:
        slot_list.append("*")
    # If more than num_slots (rare rounding edge case), truncate
    slot_list = slot_list[:num_slots]

    return slot_list
def compute_spawner_slots_with_guarantees_steal_by_ratio( enemy_list, num_slots=8 ):
    """
    1) If more distinct enemies than num_slots, drop the least frequent so we have at most num_slots distinct.
    2) Compute "ideal" fraction for each enemy = (count[e]/total_count) * num_slots
    3) Assign final_dist[e] = floor(ideal[e]) + (maybe +1 from leftover distribution by largest remainder).
    4) If any enemy ended up with final_dist[e] == 0, have them "steal" from whichever occupant
       is most above its ideal (final_dist - ideal), provided that occupant has at least 2 slots.
    5) Build and return a list of exactly num_slots, possibly including '*'.
    """

    if not enemy_list:
        return ["*"] * num_slots

    # --- Step 1: Count and maybe drop least-frequent if too many distinct ---
    counts = Counter(enemy_list)
    distinct_enemies = list(counts.keys())
    total_count = sum(counts.values())

    if len(distinct_enemies) > num_slots:
        # Sort ascending by frequency, drop from the smallest
        distinct_enemies.sort(key=lambda e: counts[e])
        to_remove = len(distinct_enemies) - num_slots
        for i in range(to_remove):
            enemy_to_remove = distinct_enemies[i]
            del counts[enemy_to_remove]
        # Refresh
        distinct_enemies = list(counts.keys())
        total_count = sum(counts.values())

    if not distinct_enemies:
        return ["*"] * num_slots

    # --- Step 2: Compute ideal fraction for each enemy ---
    ideal = {}
    for e in distinct_enemies:
        ideal[e] = (counts[e] / total_count) * num_slots

    # --- Step 3: Integer assignment by floor + largest remainder ---
    # Floor pass
    floor_vals = {}
    for e in distinct_enemies:
        floor_vals[e] = floor(ideal[e])
    used_so_far = sum(floor_vals.values())
    leftover = num_slots - used_so_far

    # Sort enemies by remainder descending
    # remainder = ideal[e] - floor(ideal[e])
    sorted_by_remainder = sorted(distinct_enemies,
                                 key=lambda e: (ideal[e] - floor_vals[e]),
                                 reverse=True)

    # Build the final distribution from floors
    final_dist = dict(floor_vals)

    # Distribute leftover by largest remainder
    idx = 0
    while leftover > 0 and idx < len(sorted_by_remainder):
        e = sorted_by_remainder[idx]
        final_dist[e] += 1
        leftover -= 1
        idx += 1

    # --- Step 4: If some enemy got 0, fix it by "stealing" from the occupant 
    #     that is most overrepresented (final_dist[e] - ideal[e] is largest).
    #     But only if final_dist[donor] > 1, so we don't push them to zero.

    zero_enemies = [e for e in distinct_enemies if final_dist[e] == 0]
    for z in zero_enemies:
        # Find the occupant that can best afford to lose 1 slot:
        # We want occupant with final_dist[donor] > 1
        # and with the largest (final_dist[donor] - ideal[donor]).
        possible_donors = [d for d in distinct_enemies if final_dist[d] > 1]
        if not possible_donors:
            # Can't fix if no occupant has more than 1
            break

        # Find the occupant that is the most "above" their ideal
        donor = max(possible_donors, key=lambda d: (final_dist[d] - ideal[d]))

        final_dist[donor] -= 1
        final_dist[z] = 1  # ensure z enemy has 1 now

    # --- Step 5: Build the final list from final_dist ---
    slot_list = []
    for e in distinct_enemies:
        slot_list.extend([e] * final_dist[e])

    # If short, fill with '*'
    while len(slot_list) < num_slots:
        slot_list.append("*")

    # If too long (rare rounding edge cases), truncate
    slot_list = slot_list[:num_slots]

    return slot_list
def sortby_group( xs ):
    """
    Return a new list in which enemies are grouped by descending frequency.
    Ties in frequency are broken alphabetically.
    """
    counter = Counter( xs )
    # sort by desc freq (-counter[e]) then by alpha (e)
    sorted_enemies = sorted( counter.keys(), key=lambda e: (-counter[e], e) )
    
    # rebuild list according to elem sort order * num occurrences
    result = []
    for e in sorted_enemies:
        result.extend( [e] * counter[e] )
    return result
def test_gippity_math():
    designer_list = ["Adam","Adam","Adam","Adam","Adam","Adam",
                    "Eve","Eve","Eve",
                    "Snek","Snek",
                    "Dragon",
                    "Bob",
                    "Charlie",
                    ]

    for method in [ compute_spawner_slots, compute_spawner_slots_with_guarantees_jank_ratio, compute_spawner_slots_with_guarantees_steal_from_rich, compute_spawner_slots_with_guarantees_steal_by_ratio ]:
        #print( method.__name__ )
        print( sortby_group(method( designer_list, 8 )) )

# Load/Save
def load_2da( path ):
    buf = open( path ).read()
    lines = buf.split( '\n' )
    header = lines[0:2]

    groups = {} # Map ColumnIndex -> { name, diff, [creatures] }

    for y, line in enumerate( lines[2:] ):
        if y == 0: line = 'dummy ' + line
        for x, col in enumerate( line.split() ):
            if y == 0: # spawn group name
                groups[x] = { 'name': col, 'diff': 'dummy', 'creatures': [] }
            elif y == 1: # difficulty row
                groups[x]['diff'] = col
            elif y > 1: # creature slots
                groups[x]['creatures'].append( col )
    groups[0]['name'] = ''

    for group in groups.values():
        assert len( group['creatures'] ) == 8
    return groups
def save_2da( path, groups, SIZE = 10 ):
    s = '2DA V1.0\n0\n'
    s += '\t'.join( [ f"{g['name'] :{SIZE}}" for g in groups.values() ] ) + '\n'
    s += '\t'.join( [ f"{g['diff'] :{SIZE}}" for g in groups.values() ] ) + '\n'
    for slot in range( 8 ):
        s += '\t'.join( [ f"{g['creatures'][slot] :{SIZE}}" for g in groups.values() ] ) + '\n'
    open( path, 'w' ).write( s )

# Calculate area groups
def uniques( es ):
    seen = set()
    xs = []
    for e in es:
        elower = e.lower()
        if elower not in seen:
            seen.add( elower )
            xs.append( e )
    return xs
def nuniques( es ): return len( uniques( es ) )
def normalize_to_first( items ):
    normalized_map = {}  # Maps lowercase version to the first actual-cased version seen
    result = []
    for element in items:
        key = element.lower()
        if key not in normalized_map:
            # First time we see this (case-insensitive) string, store its original casing
            normalized_map[key] = element
        # Use the first casing we encountered
        result.append(normalized_map[key])
    return result
def update_groups( groups ):
    data = json.loads( open( 'bin/actor_stats.json' ).read() )

    # find all _reasonable_ enemies for the area, duplicates according to frequency
    areas = {} # :: Map AreaName -> [?]CreatureName
    creatures = {} # :: Map CreatureName -> [ActorStats]
    spawns = {} # :: Map AreaName -> [8]CreatureName
    difficulty = {} # :: Map AreaName -> Diff

    for actor in data:
        area_name = actor['area']
        actor_name = actor['creature_file']
        hostile = actor['hostile']
        if not actor['found_cre_file']: hostile = True # assume hostile if no CRE file

        if actor_name not in creatures: creatures[ actor_name ] = []
        creatures[ actor_name ].append( actor )

        if area_name not in areas: areas[ area_name ] = [] # make sure to create spawn for every area

        if not hostile: continue
        areas[ area_name ].append( actor_name )

    # calculate slots for each area based on frequency analysis
    for area in areas:
        mobs = areas[ area ]

        neighbor_distance = 0
        while nuniques( mobs ) < 4:
            if nuniques( mobs ) == 0: break # probably a non-hostile area
            neighbor_distance += 1
            name_prefix = area[:-neighbor_distance]
            print( f"Warning: Area {area} has only {nuniques( mobs )} enemies {uniques( mobs )}. Filling with {name_prefix}*" )
            for neighbor in areas:
                if neighbor.startswith( name_prefix ):
                    mobs.extend( areas[ neighbor ] )

        spawns[ area ] = compute_spawner_slots_with_guarantees_steal_by_ratio( normalize_to_first(mobs), 8 )
    
    # override with manual data when possible
    for line in manual.split( '\n' ):
        if not line.split('#')[0]: continue
        area, diff, *creatures = line.split()
        diff = int(diff)
        assert 1 < diff < 50000, f"Invalid difficulty {diff}"
        assert area in spawns, f"Unknown area {area}"
        assert len( creatures ) == 8, f"Expected 8 creatures for {area}"
        spawns[ area ] = creatures
        difficulty[ area ] = diff
    
    # display
    for area in spawns:
        pass
        mobs = spawns[ area ]
        powers = []
        for mob in mobs:
            if mob == '*': continue
            cre = creatures[ mob ][0]
            clvl = max( cre['class_levels'] )
            plvl = cre['power_level']
            hp = cre['hp_max']
            power = max( clvl, plvl, hp/8 )
            if power > 0:
                powers.append( power )
        area_power = max( powers ) if powers else -1
        #print( f'{area} [{area_power}] {mobs}' )
        #print( 'plevel', [ creatures[mob][0]['power_level'] if mob != '*' else '*' for mob in mobs ] )
        #print( 'clvl  ', [ max(creatures[mob][0]['class_levels']) if mob != '*' else '*' for mob in mobs ] )
        #print( 'hp_max', [ creatures[mob][0]['hp_max'] if mob != '*' else '*' for mob in mobs ] )
    
    # update groups
    for area in spawns:
        group_name = f'RD{area}'
        groups[ group_name ] = { 'name': group_name, 'diff': str( difficulty.get(area, DEFAULT_DIFFICULTY) ), 'creatures': spawns[ area ] }

groups = load_2da( path_pristine )
update_groups( groups )
save_2da( path_output, groups )
#test_gippity_math()