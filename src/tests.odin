package main

import "core:testing"

@test
test_locator :: proc(t: ^testing.T) {
    test_locator_raw := 0xF00028
    locator := Locator( test_locator_raw )

    testing.expect_value( t, locator.file, 40 )
    testing.expect_value( t, locator.tileset, 0 )
    testing.expect_value( t, locator.bif, 15 )
}
