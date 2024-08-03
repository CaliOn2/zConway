const std = @import("std");
const c = @cImport({
    @cInclude("sys/ioctl.h");
});

const gamefield = struct {
    fields: [2][400][80]u8 = undefined,

    tick: u1 = 0,
    screenx: u16 = 0,
    screeny: u16 = 0,
    x: u16 = 0,
    y: u16 = 0,

    fn gameTick(self: *gamefield) void {
        self.x = 0;
        while (self.x < self.screenx) : (self.x += 1) {
            self.y = 0;
            while (self.y < self.screeny) : (self.y += 1) {
                self.reaper();
            }
        }
        self.tick = ~self.tick;
    }

    fn reaper(self: *gamefield) void {
        var xadd: u8 = 0;
        var yadd: u8 = 0;
        var xfull: u16 = 0;
        var yfull: u16 = 0;
        var ybyte: u8 = 0;
        var ybit: u3 = 0;
        var aliveCount: u8 = 0;

        while (xadd < 3) : (xadd += 1) {
            xfull = @abs(@mod(self.x + xadd, self.screenx));
            yadd = 0;

            while (yadd < 3) : (yadd += 1) {
                if ((yadd != 1) or (xadd != 1)) {
                    yfull = @abs(@mod(self.y + yadd, self.screeny));
                    ybyte = @intCast(@divFloor(yfull, 8));
                    ybit = @intCast(@mod(yfull, 8));
                    ybit = 7 - ybit;

                    if ((self.fields[self.tick][xfull][ybyte] >> ybit) & 1 == 1) {
                        aliveCount += 1;
                    }
                }
            }
        }
        xfull = @mod(self.x + 1, self.screenx);
        yfull = @mod(self.y + 1, self.screeny);
        ybit = @intCast(@mod(yfull, 8));
        ybyte = @intCast(@divFloor(yfull, 8));
        ybit = 7 - ybit;

        if (aliveCount == 3) {
            self.fields[~self.tick][xfull][ybyte] |= @as(u8, 1) << ybit;
        } else {
            self.fields[~self.tick][xfull][ybyte] &= ~(@as(u8, 1) << ybit);

            if (aliveCount == 2) {
                self.fields[~self.tick][xfull][ybyte] |= (self.fields[self.tick][xfull][ybyte] >> ybit & 1) << ybit;
            }
        }
    }

    fn display(self: *gamefield) !void {
        const stdout = std.io.getStdOut().writer();
        const alive: *const [3]u8 = "█";
        const dead: *const [1]u8 = " ";
        var displaybuffer: [400 * 80 * 8 * 3]u8 = undefined;
        var arrayOffset: u16 = 0;
        self.x = 0;
        self.y = 0;
        var ybit: u3 = 0;
        var ybyte: u8 = 0;

        while (self.x < self.screenx) : (self.x += 1) {
            self.y = 0;

            while (self.y < self.screeny) : (self.y += 1) {
                ybit = @intCast(@mod(self.y, 8));
                ybit = 7 - ybit;
                ybyte = @intCast(@divFloor(self.y, 8));
                if (self.fields[self.tick][self.x][ybyte] >> ybit & 1 == 1) {
                    for (alive.*, 0..) |_, i| {
                        displaybuffer[i + arrayOffset] = alive.*[i];
                    }
                    arrayOffset += 3;
                } else {
                    for (dead.*, 0..) |_, i| {
                        displaybuffer[i + arrayOffset] = dead.*[i];
                    }
                    arrayOffset += 1;
                }
            }
        }
        const displayslice = displaybuffer[0..arrayOffset];
        try stdout.print("\x1B[2J\n{s}", .{displayslice});
    }
};

pub fn close(_: c_int) callconv(.C) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("\x1B[?1049l\x1B[?25h", .{}) catch |err| {
        std.debug.print("it seems like there are issues closing : {}", .{err});
    };
    std.os.linux.exit(0);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const prng = std.crypto.random;

    var termCol: *const [8]u8 = "\x1B[00m";

    if (1 < std.os.argv.len) {
        var val: [3]u8 = undefined;

        for (0..3) |ind| {
            val[ind] = std.os.argv[1][ind];
        }

        if (std.mem.eql(u8, &val, "bla")) {
            termCol = "\x1B[30m";
        } else if (std.mem.eql(u8, &val, "red")) {
            termCol = "\x1B[31m";
        } else if (std.mem.eql(u8, &val, "gre")) {
            termCol = "\x1B[32m";
        } else if (std.mem.eql(u8, &val, "yel")) {
            termCol = "\x1B[33m";
        } else if (std.mem.eql(u8, &val, "blu")) {
            termCol = "\x1B[34m";
        } else if (std.mem.eql(u8, &val, "mag")) {
            termCol = "\x1B[35m";
        } else if (std.mem.eql(u8, &val, "cya")) {
            termCol = "\x1B[36m";
        } else if (std.mem.eql(u8, &val, "whi")) {
            termCol = "\x1B[37m";
        } else if (std.mem.eql(u8, &val, "--h")) {
            try stdout.print("This program displays a randomly generated field to simulate life by conway's game rules.\nChange colors by adding the first three letters of a color after the program.\n", .{});
            std.os.linux.exit(0);
        }
    }

    //ansi escape codes
    const esc = "\x1B";
    const csi = esc ++ "[";

    const cursor_hide = csi ++ "?25l"; //l=low
    const cursor_home = csi ++ "1;1H"; //1,1

    const screen_clear = csi ++ "2J";
    const screen_buf_on = csi ++ "?1049h"; //h=high

    const term_on = screen_buf_on ++ cursor_hide ++ cursor_home ++ screen_clear ++ termCol ++ termCol;

    var w: c.winsize = undefined;
    _ = c.ioctl(0, c.TIOCGWINSZ, &w);

    const sa: std.os.linux.Sigaction = .{
        .handler = .{ .handler = close },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    _ = std.os.linux.sigaction(std.os.linux.SIG.INT, &sa, null);
    try stdout.print("{s}", .{term_on});

    var game = gamefield{};

    game.screeny = @min(w.ws_col, 80 * 8);
    game.screenx = @min(w.ws_row, 400);

    for (game.fields[0], 0..) |_, x| {
        for (game.fields[0][x], 0..) |_, y| {
            if (x < game.screenx and y < @divFloor(game.screeny, 8)) {
                game.fields[0][x][y] = prng.int(u8);
            } else {
                game.fields[0][x][y] = 0;
            }
        }
    }
    for (game.fields[1], 0..) |_, x| {
        for (game.fields[1][x], 0..) |_, y| {
            game.fields[1][x][y] = 0;
        }
    }

    while (true) {
        _ = c.ioctl(0, c.TIOCGWINSZ, &w);
        game.screeny = @min(w.ws_col, 80 * 8);
        game.screenx = @min(w.ws_row, 400);
        game.gameTick();
        try game.display();
        std.time.sleep(100 * 1000 * 1000);
    }
}
