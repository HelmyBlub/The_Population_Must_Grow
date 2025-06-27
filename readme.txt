# setup zig path
export PATH="/opt/zig:$PATH"

# SDL3 for Zig
- found at https://github.com/castholm/SDL
zig fetch --save git+https://github.com/castholm/SDL.git


# build and run
zig build-exe test1.zig
$ ./test1


## performant build
zig build-exe -O ReleaseFast src/main.zig


# maybe helpful examples
https://github.com/ValorZard/awesome-zig-gamedev


#
linux build
zig build -Dtarget=x86_64-linux-gnu