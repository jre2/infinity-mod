if 0:
    PATH_BASE_GAME = 'bin/game'
    path = f'{PATH_BASE_GAME}/chitin.key'
    buf = open( path, 'rb' ).read()
    sig = buf[0:4]
    print( sig )

import zlib

buf = open( 'bin/test_data_compressed.are', 'rb' ).read()
data = zlib.decompress( buf )
sig = data[:4]
ver = data[4:8]
print( sig, ver )
open( 'bin/test_data_decompressed.are', 'wb' ).write( data )
cdata = zlib.compress( data, 9 )
print( f'{len(buf)} -> {len(cdata)}' )
if buf == cdata:
    print( 'recompressed version matches original' )