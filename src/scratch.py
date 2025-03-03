PATH_BASE_GAME = 'bin/game'

path = f'{PATH_BASE_GAME}/chitin.key'

buf = open( path, 'rb' ).read()

sig = buf[0:4]
print( sig )
