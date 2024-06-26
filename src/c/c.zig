pub usingnamespace @cImport({
    // OGC Library
    @cInclude("ogcsys.h");
    @cInclude("ogc/lwp_watchdog.h");
    @cInclude("gccore.h");
    // @cInclude("fat.h");
    // @cInclude("ogc/usbmouse.h");
    // @cInclude("wiikeyboard/keyboard.h");
    // @cInclude("wiiuse/wpad.h");

    // C library
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("dirent.h");
});
