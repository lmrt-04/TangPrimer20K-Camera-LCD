# usage: gw_sh.exe build.tcl
set cfgfile "impl/Camera_LCD_process_config.json"
if {[file exists $cfgfile]} {
    set fp  [open $cfgfile r]
    set txt [read $fp]
    close $fp
    set new [string map [list {"SSPI" : false} {"SSPI" : true}] $txt]
    if {$new ne $txt} {
        set fp [open $cfgfile w]
        puts -nonewline $fp $new
        close $fp
    }
}
open_project "Camera_LCD.gprj"
set_option -top_module top
run all