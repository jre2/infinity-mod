package main

import "core:bytes"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:os"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

DEBUG_MEMORY :: false
//PATH_BASE_GAME :: `D:\games\Infinity Engine\Icewind Dale Enhanced Edition`
PATH_BASE_GAME :: `game`

/* .plan
* be able to fetch the current version of a given creature, item, area, 2da, etc and read/modify it
    * need to be able to pull from data/ BIFs, override/ loose files, and save file archive
*/

RESREF :: [8]u8
Orientation :: enum u16 {
    South, SSW, SW, WSW, West, WNW, NW, NNW, North, NNE, NE, ENE, East, ESE, SE, SSE
}

BIF_Header :: struct {
    signature : [4]u8,
    version : [4]u8,
    num_files : u32,
    num_tilesets : u32,
    offset_files : u32, // offset from start of file to file table
}
ARE_Header :: struct {
    signature : [4]u8,
    version : [4]u8,
    wed_resource : RESREF,
    last_saved : u32, // realtime seconds
    area_flags : u32,

    north_resref : RESREF,
    north_flags : u32,
    east_resref : RESREF,
    east_flags : u32,
    south_resref : RESREF,
    south_flags : u32,
    west_resref : RESREF,
    west_flags : u32,

    area_flags2 : u16,
    rain_probability : u16,
    snow_probability : u16,
    fog_probability : u16,
    lightning_probability : u16,
    overlay_transparency_or_wind_speed : u16,

    offset_actors : u32,
    num_actors : u16,
    num_regions : u16, // aka triggers?
    offset_regions : u32,
    offset_spawns : u32,
    num_spawns : u32,
    offset_entrances : u32,
    num_entrances : u32,
    offset_containers : u32,
    num_containers : u16,
    num_items : u16,
    offset_items : u32,
    offset_verticies : u32,
    num_verticies : u16,
    num_ambients : u16,
    offset_ambients : u32,
    offset_variables : u32,
    num_variables : u32,
    num_object_flags : u16,
    offset_object_flags : u16,
    area_script : RESREF,
    size_explored_bitmask : u32,
    offset_explored_bitmask : u32,
    num_doors : u32,
    offset_doors : u32,
    num_animations : u32,
    offset_animations : u32,
    num_tiled_objects : u32,
    offset_tiled_objects : u32,
    offset_songs : u32,
    offset_rest_encounters : u32,
    offset_automap_notes : u32,
    num_automap_notes : u32,
    offset_projectile_traps : u32,
    num_projectile_traps : u32,
    rest_movie_day : RESREF,
    rest_movie_night : RESREF,
}
ARE_Actor :: struct {
    name : [32]u8,
    coord_cur : [2]u16,
    coord_dest : [2]u16,
    flags : u32,
    is_random : u16, // 0 no, 1 created by spawn point or rest interruption; also bits for flags related to spawning
    first_letter_cre_resref : [1]u8,
    unused1 : u8,
    animation : u32,
    orientation : Orientation,
    unused2 : u16,
    expiry_time : i32, // -1 for never
    wander_distance : u16,
    follow_distance : u16,
    schedule_present_at : u32,
    num_times_talked_to : u32,
    dialog : RESREF,
    script_override : RESREF,
    script_general : RESREF,
    script_class : RESREF,
    script_race : RESREF,
    script_default : RESREF,
    script_specific : RESREF,
    cre_file : RESREF,
    offset_cre_struct : u32, // for embedded cre files
    size_cre_struct : u32,
    unused3 : [128]u8,
}
ARE :: struct {
    backing : []u8,
    header : ARE_Header,
    actors : []ARE_Actor,
}


Locator :: bit_field u32 {
    file_index: u32 | 14, // non-tileset file index (any 12bit value so long as it matches value in BIF)
    tileset_index: u32 | 6, // tileset index
    bif_index: u32 | 12, // source BIF index
}
KEY_Header :: struct {
    signature : [4]u8,
    version : [4]u8,
    num_bifs : u32,
    num_resources : u32,
    offset_bifs : u32, // offset from start of file to bif table
    offset_resources : u32, // offset from start of file to resource table
}
#assert( size_of(KEY_Header) == 24 )
KEY_BIF :: struct {
    file_length : u32,
    offset_name : u32,
    name_length : u16, // includes null terminator
    location_bits : u16,
}
#assert( size_of(KEY_BIF) == 12 )
KEY_Resource :: struct #packed {
    name : RESREF,
    type : u16,
    locator : Locator,
}
#assert( size_of(KEY_Resource) == 14 )
KEY :: struct {
    backing : []u8,
    header : KEY_Header,
    bifs : []KEY_BIF,
    resources : []KEY_Resource,

    // not automatically kept in sync
    bif_names : [dynamic]string,
    res_names : [dynamic]string,
}

DB :: struct {
    key : KEY,
}

resref_move_to_string :: proc( resref: ^RESREF ) -> string {
    return string( bytes.trim_right_null( resref[:] ) )
}
print_KEY_Resource :: proc( key: KEY, res: KEY_Resource ) {
    res := res
    fmt.printfln( "<name: %s type: %d locator: %d", resref_move_to_string( &res.name ), res.type, res.locator )
    foo := key.bif_names[ res.locator.bif_index ]
    fmt.printfln( "bif name: %s", foo )
}

do_key :: proc() -> bool {
    path := filepath.join( {PATH_BASE_GAME, "chitin.key"} )
    key : KEY
    key.backing = os.read_entire_file( path ) or_return
    key.header = slice.to_type( key.backing[0:], KEY_Header )
    assert( key.header.signature == "KEY ", "Unexpected signature" )
    assert( key.header.version == "V1  ", "Unexpected version" )
    key.bifs = transmute( []KEY_BIF )key.backing[ key.header.offset_bifs: ] [ :key.header.num_bifs ]
    key.resources = transmute( []KEY_Resource )key.backing[ key.header.offset_resources: ] [ :key.header.num_resources ]

    // convienence views on data
    for bif in key.bifs {
        filename := key.backing[ bif.offset_name: ][:bif.name_length-1] // -1 to exclude null terminator
        append( &key.bif_names, string(filename) )
    }
    for &res in key.resources {
        res_name := resref_move_to_string( &res.name )
        append( &key.res_names, res_name )
    }
    when true { // tests
        fmt.printfln( "# BIF: %d # RES: %d", len(key.bifs), len(key.resources) )
        print_KEY_Resource( key, key.resources[0] )
        print_KEY_Resource( key, key.resources[100] )
        print_KEY_Resource( key, key.resources[1000] )
        print_KEY_Resource( key, key.resources[5000] )
    }
    return true
}

main :: proc() {
    when DEBUG_MEMORY {
        tracking_allocator : mem.Tracking_Allocator
        mem.tracking_allocator_init( &tracking_allocator, context.allocator )
        context.allocator = mem.tracking_allocator( &tracking_allocator )

        print_alloc_stats := proc( tracking: ^mem.Tracking_Allocator ) {
            for _, entry in tracking.allocation_map {
                fmt.printfln( "%v: Leaked %v bytes", entry.location, entry.size )
            }
            for entry in tracking.bad_free_array {
                fmt.printfln( "%v: Bad free @ %v", entry.location, entry.memory )
            }
        }
        defer { print_alloc_stats( &tracking_allocator ) }
    }
    test_locator()

    when false { // sample globbing files
        path_data := filepath.join( {PATH_BASE_GAME, "data"}, context.temp_allocator )
        pat_bifs := filepath.join( {path_data, "*.bif"}, context.temp_allocator )
        path_bifs, err := filepath.glob( pat_bifs ) //FIXME err handle
        fmt.printfln( "pat_bifs: %v", pat_bifs )
        fmt.printfln( "path_bifs: %v", path_bifs[0] )
    }

    when false { // sample load KEY file
        path := `D:\games\Infinity Engine\Icewind Dale Enhanced Edition\chitin.key`
        fmt.printfln( "Loading KEY file" )
        file, err := os.open( path, os.O_RDONLY )
        defer os.close( file )
        if err != nil {
            fmt.printfln( "Error opening file: %s", os.error_string(err) )
            return
        }

        header : KEY_Header
        os.read_ptr( file, &header, size_of( header ) )
        assert( header.signature == "KEY ", "Unexpected signature" )
        assert( header.version == "V1  ", "Unexpected version" )
        fmt.printfln( "header: %v", header )

        // read one BIF entry
        bif_entry : KEY_BIF
        os.seek( file, cast(i64) header.offset_bifs, os.SEEK_SET )
        os.read_ptr( file, &bif_entry, size_of( bif_entry ) )
        fmt.printfln( "bif_entry: %v", bif_entry )

    }

    when false { // sample loading a BIF file
        fmt.printfln( "Loading BIF file" )
        path := "AR120X.bif"

        header : BIF_Header
        //file, err := os.open( path, os.O_RDONLY )

        buf, succ := os.read_entire_file( path )
        if succ {
            fmt.printfln( "read %v bytes", len(buf) )
            fmt.printfln( "buf: %s", buf[:4] )
        }

        fmt.printfln( "header: %v", header )

    }

    when false { // sample ARE file
        fmt.printfln( "Loading ARE file" )
        path := `D:\games\Infinity Engine\Icewind Dale Enhanced Edition\override\AR9714.ARE`

        file, err := os.open( path, os.O_RDONLY )
        defer os.close( file )
        if err != nil {
            fmt.printfln( "Error opening file: %s", os.error_string(err) )
            return
        }

        area : ARE
        os.read_ptr( file, &area.header, size_of( ARE_Header ) )
        assert( area.header.signature == "AREA", "Unexpected signature" )
        assert( area.header.version == "V1.0", "Unexpected version" )
        fmt.printfln( "header [%d]: %v", size_of(ARE_Header), area.header )
        fmt.printfln( "area script: %s", area.header.area_script )

        /* test loading single actor
        actor : ARE_Actor
        actor_index := 41
        os.seek( file, cast(i64)header.offset_actors + cast(i64)actor_index * size_of(ARE_Actor), os.SEEK_SET )
        os.read_ptr( file, &actor, size_of( actor ) )
        fmt.printfln( "actor: %v", actor )
        fmt.printfln( "actor name %s cre %s", actor.name, actor.cre_file )
        */
        // load all actors into area struct
        os.seek( file, cast(i64)area.header.offset_actors, os.SEEK_SET )
        for i := 0; i < cast(int)area.header.num_actors; i += 1 {
            actor : ARE_Actor
            os.read_ptr( file, &actor, size_of( ARE_Actor ) )
            append( &area.actors, actor )
        }
        fmt.printfln( "ex actor name %s cre %s", area.actors[41].name, area.actors[41].cre_file )
    }
    when false { // ARE with full data and slice method
        fmt.printfln( "Loading ARE file" )
        //path := `D:\games\Infinity Engine\Icewind Dale Enhanced Edition\override\AR9714.ARE`
        path := filepath.join( {PATH_BASE_GAME, "override", "AR9714.ARE"} )

        file_data, succ := os.read_entire_file( path )
        if !succ {
            fmt.printfln( "Error reading file" )
            return
        }
        area : ARE
        area.backing = file_data
        area.header = slice.to_type( area.backing[0:], ARE_Header )
        assert( area.header.signature == "AREA", "Unexpected signature" )
        assert( area.header.version == "V1.0", "Unexpected version" )

        fmt.printfln( "actors block offset: %d", area.header.offset_actors )
        fmt.printfln( "num actors: %d", area.header.num_actors )
        // method 1
        area.actors = slice.from_ptr( cast([^]ARE_Actor) raw_data( area.backing[ area.header.offset_actors: ] ), cast(int)area.header.num_actors )
        // method 2
        area.actors = ([^]ARE_Actor)(raw_data(area.backing[ area.header.offset_actors: ]))[:area.header.num_actors]
        // method 3
        area.actors = slice.reinterpret( []ARE_Actor, area.backing[ area.header.offset_actors: ] )[ :area.header.num_actors ]
        // method 4
        area.actors = mem.slice_data_cast( []ARE_Actor, area.backing[ area.header.offset_actors: ] )[ :area.header.num_actors ]
        // method 5
        area.actors = transmute( []ARE_Actor )area.backing[ area.header.offset_actors: ] [ :area.header.num_actors ]
        // method 6
        //area.actors = transmute( []ARE_Actor )area.backing[ area.header.offset_actors : area.header.offset_actors + cast(u32)area.header.num_actors * size_of( ARE_Actor ) ]
        area.actors = mem.slice_data_cast( []ARE_Actor, area.backing[ area.header.offset_actors : area.header.offset_actors + cast(u32)area.header.num_actors * size_of( ARE_Actor ) ] )
        fmt.printfln( "num actors: %d", len(area.actors) )
        fmt.printfln( "should be skeleton: actor name %s cre %s", area.actors[41].name, area.actors[41].cre_file )
    }
    ret := do_key()
    fmt.printfln( "do_key: %v", ret )
}
