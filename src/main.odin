package main

import "core:fmt"
import "core:mem"
import "core:path/filepath"
import rl "vendor:raylib"

DEBUG_MEMORY :: false
PATH_BASE_GAME :: `D:\games\Infinity Engine\Icewind Dale Enhanced Edition`

/* .plan
be able to fetch the current version of a given creature, item, area, 2da, etc
    this means pull from the override folder first, and only if a file isn't there, load one from the base data
        override has loose files directly editable
        base data is packed in bif files

should we load all BIFs and override files all at once, or only on demand?
    we at least need to know what the possible files are though, so that implies at least partially loading everything
*/

State :: struct {
}
st : State

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

    // sample globbing files
    when true {
        path_data := filepath.join( {PATH_BASE_GAME, "data"}, context.temp_allocator )
        pat_bifs := filepath.join( {path_data, "*.bif"}, context.temp_allocator )
        path_bifs, err := filepath.glob( pat_bifs ) //FIXME err handle
        fmt.printfln( "pat_bifs: %v", pat_bifs )
        fmt.printfln( "path_bifs: %v", path_bifs[0] )
    }
    // sample loading a BIF file
    when false {
        path := `D:\games\Infinity Engine\Icewind Dale Enhanced Edition\data\AR120X.bif`
        file, err := os.open( path, os.O_RDONLY )
    }
}