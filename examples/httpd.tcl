# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require oodaemons::httpd
package require cflib
#package require aop

cflib::config create cfg $argv {
	variable port	8008
	variable debug	no
}

cflib::pclass create example_httpd {
	superclass oodaemons::httpd

	method got_req {req} { #<<<
		set uri	[$req request_uri]

		puts "Got request for path: \"[$uri path]\""

		$req send_response [dict create \
				response-data "hello, world" \
		]
	}

	#>>>
}

if {[info commands "::??"] ne "::??"} {
	if {[cfg get debug]} {
		proc ?? {script} {
			uplevel $script
		}
	} else {
		proc ?? {args} {}
	}
}

proc log {lvl msg args} {
	puts $msg
}

example_httpd create httpd -port [cfg get port]
#aop::logger attach httpd

puts "Listening on [cfg get port]"
vwait ::forever
