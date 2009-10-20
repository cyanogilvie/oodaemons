#!/usr/bin/env kbskit8.6

# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require oodaemons::ftpd
package require sqlite3
package require cflib

cflib::config create cfg $argv {
	variable port	21
}

# Init db <<<
set db_fn	[file join [file dirname [info script]] ftp_filestore.sqlite3]
sqlite3 db $db_fn

if {![db exists {
	select
		1
	from
		sqlite_master
	where
		type = 'table'
		and name = 'files'
}]} {
	db eval {
		create table files (
			filename		text primary key,
			data			blob
		);
	}
}
# Init db >>>

oo::class create my_ftpd_con {
	superclass oodaemons::ftpd_con

	method authenticate {user pass} { #<<<
		if {$user eq "bisftp" && $pass eq "bisftp"} {
			return 1
		} else {
			return 0
		}
	}

	#>>>
	method receive_file {filename data} { #<<<
		try {
			db eval {
				insert or replace into files (
					filename,
					data
				) values (
					$filename,
					@data
				)
			}
		} on error {errmsg options} {
			puts stderr "Error saving file in database: $errmsg\n[dict get $options -errorinfo]"
		}
	}

	#>>>
	method log {lvl msg} { #<<<
		puts stderr $msg
	}

	#>>>
}

oodaemons::ftpd create ftpd -port [cfg get port] -con_handler my_ftpd_con

oo::objdefine ftpd method log {lvl msg} { #<<<
	puts stderr $msg
}

#>>>
oo::objdefine ftpd method accept {socket cl_ip cl_port} { #<<<
	# Only allow connections from localhost
	if {$cl_ip eq "127.0.0.1"} {
		return 1
	} else {
		return 0
	}
}

#>>>

puts "Started ftp server on port [cfg get port]"
vwait ::forever
