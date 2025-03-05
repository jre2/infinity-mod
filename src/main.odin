#+feature dynamic-literals
package main

import "core:bytes"
import odin_zlib "core:compress/zlib"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:os"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"
import zlib "vendor:zlib"

DEBUG_MEMORY :: true
PATH_GAME_BASE := `D:\games\Infinity Engine\Icewind Dale Enhanced Edition`
PATH_SAVE_BASE := `C:\Users\rin\Documents\Icewind Dale - Enhanced Edition`
PATH_REL_OVERRIDE_READ := "override.pristine"
PATH_REL_OVERRIDE_WRITE := "override"
SAVE_NAME := "000000047-all purchases but haste and intercession"

/* .plan
FUTURE: fully load .ARE files and rebuild from scratch (to enable changing number of Actors)
NOTE: struct .header sections are not linked to backing buffer; they are copies. might want to change later
*/

ZError :: enum i32 {
    OK = 0,
    STREAM_END = 1,
    NEED_DICT = 2,
    ERRNO = -1,
    STREAM_ERROR = -2,
    DATA_ERROR = -3,
    MEM_ERROR = -4,
    BUF_ERROR = -5,
    VERSION_ERROR = -6,
}
ErrorIMod :: enum {
    ResourceNotFound,
}
Error :: union #shared_nil {
    os.Error,
    odin_zlib.Error,
    ZError,
    mem.Allocator_Error,
    ErrorIMod,
}
RESREF :: [8]u8
STRREF :: u32
Locator :: bit_field u32 {
    file: u32 | 14, // non-tileset file index (any 12bit value so long as it matches value in BIF)
    tileset: u32 | 6, // tileset index
    bif: u32 | 12, // source BIF index
}
RESType :: enum u16 {
    None = 0,
    BMP = 0x001,
    WAVC = 0x004,
    BAM = 0x3e8,
    WED = 0x3e9,
    TIS = 0x3eb,
    MOSC = 0x3ec,
    ITM = 0x3ed,
    SPL = 0x3ee,
    BCS = 0x3ef,
    IDS = 0x3f0,
    CRE = 0x3f1,
    ARE = 0x3f2,
    _2DA = 0x3f4,
    GAM = 0x3f5,
    STO = 0x3f6,
    EFF = 0x3f8, // usually instead just an embedded 30b in CRE,ITM,SPL files
    PVRZ = 0x404,
}
RESType_TO_EXTENTION := map[RESType]string { .ARE="are" } // add more as needed or find alternative
Orientation :: enum u16 {
    South, SSW, SW, WSW, West, WNW, NW, NNW, North, NNE, NE, ENE, East, ESE, SE, SSE
}
Location :: enum {
    DNE,
    Data,
    Override,
    Save,
}
LocationData :: struct {
    type : Location,
    path_save_key : string,
    path_override : string,
    path_bif : string,
    file_index_within_bif : u32,

    path_save_file_new : string,
    path_override_new : string,
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
ARE_RestEncounter :: struct {
    name : [32]u8,
    creature_strings: [10]STRREF,
    creature_refs: [10]RESREF,
    creature_count : u16,
    difficulty : u16,
    removal_time: u32, // duration
    distance_wander : u16,
    distance_follow : u16,
    max_creature_spawns : u16,
    is_active : u16, // 0 inactive 1 active
    spawn_probability_per_hour_day : u16,
    spawn_probability_per_hour_night : u16,
    unused : [56]u8,
}
ARE :: struct {
    backing : []u8,
    header : ARE_Header,
    actors : []ARE_Actor,
    rest_encounters : ^ARE_RestEncounter,
}

BIF_Header :: struct {
    signature : [4]u8,
    version : [4]u8,
    num_files : u32,
    num_tilesets : u32,
    offset_files : u32, // offset from start of file to file table
}
#assert( size_of(BIF_Header) == 20 )
BIF_File :: struct {
    loc : Locator,
    offset : u32, // within the BIF file
    size : u32,
    type : RESType,
    unknown : u16,
}
#assert( size_of(BIF_File) == 16 )
BIF_Tileset :: struct {
    loc : Locator,
    offset : u32, // within the BIF file
    num_tiles : u32,
    sizeof_tile : u32,
    type : RESType, // always 0x3eb (TIS)
    unknown : u16,
}
#assert( size_of(BIF_Tileset) == 20 )
BIF :: struct {
    backing : []u8,
    header : BIF_Header,
    files : []BIF_File,
    tilesets : []BIF_Tileset,
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
    size : u32,
    offset_name : u32, // within the KEY file
    len_name : u16, // includes null terminator
    location_bits : u16, // (MSB) xxxx xxxx ABCD EFGH (LSB); A=CD6, F=CD1, G=cache/, H=data/
}
#assert( size_of(KEY_BIF) == 12 )
KEY_Resource :: struct #packed {
    name : RESREF,
    type : RESType,
    loc : Locator,
}
#assert( size_of(KEY_Resource) == 14 )
KEY :: struct {
    backing : []u8,
    header : KEY_Header,
    bifs : []KEY_BIF,
    resources : []KEY_Resource,
}

SAV_Header :: struct {
    signature : [4]u8,
    version : [4]u8,
}
#assert( size_of(SAV_Header) == 8 )
SAV_File :: struct { // not stored; just used for convenience
    len_filename : u32,
    filename : []u8,
    len_data_uncompressed : u32,
    len_data_compressed : u32,
    data_compressed : []u8,
}
SAV :: struct {
    backing : []u8,
    header : SAV_Header,
    // convienence and not automatically kept in sync
    files : map[string][]u8,
}

DB :: struct {
    key : KEY,
    sav : SAV,
    // convienence and not automatically kept in sync
    areas: [dynamic]string, // resource names for .ARE files
}

get_KEY_BIF_name :: proc( db: DB, keybif: KEY_BIF ) -> string {
    return string( db.key.backing[ keybif.offset_name: ][ :keybif.len_name-1] ) // -1 to exclude null terminator
}
resref_move_to_string :: proc( resref: ^RESREF ) -> string {
    return string( bytes.trim_right_null( resref[:] ) )
}
get_Key_Resource_BIF_name :: proc( db: DB, res: KEY_Resource ) -> string {
    return get_KEY_BIF_name( db, db.key.bifs[ res.loc.bif ] )
}
print_KEY_BIF :: proc( db: DB, keybif: KEY_BIF ) {
    fmt.printfln( "<KEY_BIF name '%s' len %d b loc_bits '%v'>", get_KEY_BIF_name( db, keybif ), keybif.size, keybif.location_bits )
}
print_KEY_Resource :: proc( db: DB, res: KEY_Resource ) {
    res := res
    fmt.printfln( "<KEY_RES name: %s type: %v locator: %d bif: %s", resref_move_to_string( &res.name ), res.type, res.loc, get_KEY_BIF_name( db, db.key.bifs[ res.loc.bif ] ) )
}

load_KEY :: proc( path: string ) -> (key: KEY, err: Error) {
    key.backing = os.read_entire_file_or_err( path ) or_return
    key.header = slice.to_type( key.backing[0:], KEY_Header )
    assert( key.header.signature == "KEY ", "Unexpected signature" )
    assert( key.header.version == "V1  ", "Unexpected version" )
    key.bifs = transmute( []KEY_BIF )key.backing[ key.header.offset_bifs: ] [ :key.header.num_bifs ]
    key.resources = transmute( []KEY_Resource )key.backing[ key.header.offset_resources: ] [ :key.header.num_resources ]
    return
}
load_BIF :: proc( path: string ) -> (bif: BIF, err: Error) {
    bif.backing = os.read_entire_file_or_err( path ) or_return
    bif.header = slice.to_type( bif.backing[0:], BIF_Header )
    assert( bif.header.signature == "BIFF", "Unexpected signature" )
    assert( bif.header.version == "V1  ", "Unexpected version" )
    bif.files = transmute( []BIF_File )bif.backing[ bif.header.offset_files: ] [ :bif.header.num_files ]
    offset_tiles := bif.header.offset_files + bif.header.num_files * size_of( BIF_File )
    bif.tilesets = transmute( []BIF_Tileset )bif.backing[ offset_tiles: ] [ :bif.header.num_tilesets ]
    for tile in bif.tilesets {
        assert( tile.type == .TIS, "Unexpected tileset type" )
    }
    return
}
load_ARE :: proc( buf: []u8 ) -> (are: ARE, err: Error) {
    are.backing = buf
    are.header = slice.to_type( are.backing[0:], ARE_Header )
    assert( are.header.signature == "AREA", "Unexpected signature" )
    assert( are.header.version == "V1.0", "Unexpected version" )
    are.actors = transmute( []ARE_Actor )are.backing[ are.header.offset_actors: ] [ :are.header.num_actors ]
    are.rest_encounters = cast(^ARE_RestEncounter) raw_data( are.backing[ are.header.offset_rest_encounters: ] )
    return
}
save_SAV :: proc( sav: SAV, path: string ) -> (err: Error) {
    sav := sav
    fd := os.open( path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC ) or_return
    defer os.close( fd )

    os.write_ptr( fd, &sav.header, size_of( SAV_Header ) ) or_return
    for filename, data_uncompressed in sav.files {
        // len filename, filename ; null terminate it
        len_filename := cast(u32)len(filename) +1
        os.write_ptr( fd, &len_filename, size_of( u32 ) ) or_return
        os.write_ptr( fd, raw_data(filename), len(filename) ) or_return
        os.write_byte( fd, 0 ) or_return

        // len uncomp, len comp, comp data
        len_uncompressed := cast(u32)len(data_uncompressed)
        len_compressed := len_uncompressed // reasonable upper bound on buffer required
        data_compressed := make( []u8, len_compressed )
        defer delete( data_compressed )
        zerr := zlib.compress2( raw_data(data_compressed), &len_compressed, raw_data(data_uncompressed), len_uncompressed, 9 )
        if zerr < 0 { return ZError( zerr ) }

        os.write_ptr( fd, &len_uncompressed, size_of( u32 ) ) or_return
        os.write_ptr( fd, &len_compressed, size_of( u32 ) ) or_return
        os.write_ptr( fd, raw_data(data_compressed), cast(int)len_compressed ) or_return
    }
    return
}
load_SAV :: proc( path: string ) -> (sav: SAV, err: Error) {
    sav.backing = os.read_entire_file_or_err( path ) or_return
    sav.header = slice.to_type( sav.backing[0:], SAV_Header )
    assert( sav.header.signature == "SAV ", "Unexpected signature" )
    assert( sav.header.version == "V1.0", "Unexpected version" )

    i : u32 = size_of( SAV_Header )
    for len(sav.backing) - int(i) > 0xC { // File Entry must have 3x u32 lengths (and a filename but theoretically could be 0-length)
        savfile : SAV_File
        savfile.len_filename = slice.to_type( sav.backing[i:i+4], u32 ); i+=4
        savfile.filename = sav.backing[i:i+savfile.len_filename]; i+=savfile.len_filename
        savfile.len_data_uncompressed = slice.to_type( sav.backing[i:i+4], u32 ); i+=4
        savfile.len_data_compressed = slice.to_type( sav.backing[i:i+4], u32 ); i+=4
        savfile.data_compressed = sav.backing[i:i+savfile.len_data_compressed]; i+=savfile.len_data_compressed

        // odin zlib implementation
        zbuf : bytes.Buffer
        odin_zlib.inflate( savfile.data_compressed, &zbuf ) or_return
        sav.files[ string(savfile.filename[: len(savfile.filename)-1]) ] = bytes.buffer_to_bytes( &zbuf )
        /* vendor zlib implementation
        dest_len : u32 = savfile.len_data_uncompressed
        dest := make( []u8, savfile.len_data_uncompressed )
        zerr := zlib.uncompress( raw_data(dest), &dest_len, raw_data(savfile.data_compressed), savfile.len_data_compressed )
        if zerr < 0 { return sav, ZError( zerr ) }
        */
    }
    remaining_bytes := len(sav.backing) - int(i)
    if remaining_bytes != 0 {
        fmt.printfln( "Warning: SAV has %d bytes remaining at the end", remaining_bytes )
    }
    return
}
load_DB :: proc() -> (db: DB, err: Error) {
    path_key := filepath.join( {PATH_GAME_BASE, "chitin.key"} )
    path_sav := filepath.join( {PATH_SAVE_BASE, "save", SAVE_NAME, "BALDUR.SAV"} )
    defer delete( path_key )
    defer delete( path_sav )
    db.key = load_KEY( path_key ) or_return
    db.sav = load_SAV( path_sav ) or_return
    for &res in db.key.resources {
        if res.type == .ARE {
            append( &db.areas, resref_move_to_string( &res.name ) )
        }
    }
    return
}
delete_SAV :: proc( sav: SAV ) {
    for key, value in sav.files {
        delete( sav.files[ key ] )
    }
    delete( sav.files )
    delete( sav.backing )
}
delete_DB :: proc( db: ^DB ) {
    delete_SAV( db.sav )
    delete( db.areas )
    delete( db.key.backing )
}
update_area :: proc( db: DB, old: ARE ) -> (new: ARE, err: Error) {
    // callee responsible for cleaning up memory of both old and new
    new = load_ARE( bytes.clone( old.backing ) ) or_return
    new.rest_encounters.max_creature_spawns = 17
    //fmt.printfln( "Max spawns %d -> %d", old.rest_encounters.max_creature_spawns, new.rest_encounters.max_creature_spawns )
    return
}
locate_resource :: proc( db: DB, res_name: string, res_type: RESType ) -> (loc: LocationData, err: Error) {
    loc.path_save_key = fmt.aprintf( "%s.%s", res_name, RESType_TO_EXTENTION[ res_type ] )
    loc.path_override = filepath.join( {PATH_GAME_BASE, PATH_REL_OVERRIDE_READ, loc.path_save_key} )
    loc.path_bif = fmt.aprintf( "dummy" ) // for consistent memory free logic

    loc.path_save_file_new = fmt.aprintf( "dummy.sav" )
    loc.path_override_new = filepath.join( {PATH_GAME_BASE, PATH_REL_OVERRIDE_WRITE, loc.path_save_key} )

    for &res in db.key.resources {
        if resref_move_to_string(&res.name) == res_name && res.type == res_type {
            delete( loc.path_bif )
            loc.path_bif = filepath.join( {PATH_GAME_BASE, get_Key_Resource_BIF_name( db, res ) } )
            loc.file_index_within_bif = res.loc.file
            loc.type = .Data
            break
        }
    }
    assert( loc.type == .Data, "Resource not found in BIFs, which should be impossible" )
    if os.exists( loc.path_override ) {
        loc.type = .Override
    }
    if loc.path_save_key in db.sav.files {
        loc.type = .Save
    }
    assert( loc.type != .DNE, "Resource not found in any location" )
    return
}
delete_LocationData :: proc( loc: ^LocationData ) {
    delete( loc.path_save_key )
    delete( loc.path_override )
    delete( loc.path_bif )

    delete( loc.path_save_file_new )
    delete( loc.path_override_new )
}
update_areas :: proc( db: ^DB ) -> (err: Error){
    for area in db.areas {
        loc := locate_resource( db^, area, .ARE ) or_return
        defer delete_LocationData( &loc )

        switch loc.type {
        case .Data:
            bif := load_BIF( loc.path_bif ) or_return
            defer delete( bif.backing )
            bif_file := bif.files[ loc.file_index_within_bif ]
            bif_file_buf := bif.backing[ bif_file.offset:bif_file.offset+bif_file.size ]
            are_old := load_ARE( bif_file_buf ) or_return

            are_new := update_area( db^, are_old ) or_return
            defer delete( are_new.backing )
            
            os.write_entire_file_or_err( loc.path_override_new, are_new.backing ) or_return
        case .Override:
            buf := os.read_entire_file_or_err( loc.path_override ) or_return
            are_old := load_ARE( buf ) or_return // owned as buf and are_old.backing
            defer delete( are_old.backing )

            are_new := update_area( db^, are_old ) or_return
            defer delete( are_new.backing )

            os.write_entire_file_or_err( loc.path_override_new, are_new.backing ) or_return
        case .Save:
            buf := db.sav.files[ loc.path_save_key ]
            are_old := load_ARE( buf ) or_return // memory owned by db.sav, so delete iff replacing

            are_new := update_area( db^, are_old ) or_return
            delete( are_old.backing ) // cleanup old but db.sav is responsible for deleting new later on

            db.sav.files[ loc.path_save_key ] = are_new.backing
            // single combined write to save file will occur after loop
        case .DNE:
            panic( "Should not have reached here" )
        }
    }
    // save any modifications to the SAV file
    save_SAV( db.sav, "dummy.sav" ) or_return
    new_sav := load_SAV( "dummy.sav" ) or_return // sanity check we can load our own save file
    delete_SAV( new_sav )
    return
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

    db, err := load_DB()
    if err != nil {
        fmt.printfln( "Error loading game data: %v", err )
        return
    }
    defer delete_DB( &db )

    when true { // update areas
        err = update_areas( &db )
        if err != nil {
            fmt.printfln( "Error updating areas: %v", err )
            return
        }
    }
}