package main

test_locator :: proc() {
    test_locator_raw := 0xF00028
    locator := Locator( test_locator_raw )
    assert( locator.file_index == 40 )
    assert( locator.tileset_index == 0 )
    assert( locator.bif_index == 15 )
}


