# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

cflib::pclass create oodaemons::httpd {
	property port				80 _need_rebind
	property ip					"" _need_rebind
	property use_keepalive		1

	variable {*}{
		dominos
		listen
		codes
	}

	constructor {args} { #<<<
		sop::domino new dominos(need_relisten) -name "[self] need_relisten"

		$dominos(need_relisten) attach_output [my code _rebind]

		dict set codes 100	"Continue"
		dict set codes 101	"Switching Protocols"
		dict set codes 200	"OK"
		dict set codes 201	"Created"
		dict set codes 202	"Accepted"
		dict set codes 203	"Non-Authoritive Information"
		dict set codes 204	"No Content"
		dict set codes 205	"Reset Content"
		dict set codes 206	"Partial Content"
		dict set codes 300	"Multiple Choices"
		dict set codes 301	"Moved Permanently"
		dict set codes 302	"Found"
		dict set codes 303	"See Other"
		dict set codes 304	"Not Modified"
		dict set codes 305	"Use Proxy"
		dict set codes 306	"(Unused)"
		dict set codes 307	"Temporary Redirect"
		dict set codes 400	"Bad Request"
		dict set codes 401	"Unauthorized"
		dict set codes 402	"Payment Required"
		dict set codes 403	"Forbidden"
		dict set codes 404	"Not Found"
		dict set codes 405	"Method Not Allowed"
		dict set codes 406	"Not Acceptable"
		dict set codes 407	"Proxy Authentication Required"
		dict set codes 408	"Request Timeout"
		dict set codes 409	"Conflict"
		dict set codes 410	"Gone"
		dict set codes 411	"Length Required"
		dict set codes 412	"Precondition Failed"
		dict set codes 413	"Request Entity Too Large"
		dict set codes 414	"Request-URI Too Large"
		dict set codes 415	"Unsupported Media Type"
		dict set codes 416	"Requested Range Not Satisfiable"
		dict set codes 417	"Expectation Failed"
		dict set codes 500	"Internal Server Error"
		dict set codes 501	"Not Implemented"
		dict set codes 502	"Bad Gateway"
		dict set codes 503	"Service Unavailable"
		dict set codes 504	"Gateway Timeout"
		dict set codes 505	"HTTP Version Not Supported"

		my configure {*}$args
	}

	#>>>
	destructor { #<<<
		my _close_listen
	}

	#>>>

	method lookup_code {code} { #<<<
		if {![dict exists $codes $code]} {
			my log error "No such code: ($code)"
			return "Internal Server Error"
		}
		return [dict get $codes $code]
	}

	#>>>
	method got_req {req} { #<<<
		# Override
		throw {http_error 404} "No handler for [[$req request_uri] encoded]"
	}

	#>>>

	method _need_rebind {} { #<<<
		$dominos(need_relisten) tip
	}

	#>>>
	method _accept {con client_ip client_port} { #<<<
		try {
			set conobj	[oodaemons::httpd::con new [dict create \
					httpd			[self] \
					con				$con \
					use_keepalive	$use_keepalive \
					client_ip		$client_ip \
					client_port		$client_port]]
		} on error {errmsg options} {
			my log error "Error constructing connection handler: $errmsg\n[dict get $options -errorinfo]"
			if {[info exists con]} {
				if {$con in [chan names]} {
					close $con
				}
				unset con
			}
		}
	}

	#>>>
	method _rebind {} { #<<<
		my _close_listen

		set listen	[socket -server [my code _accept] $port]
		?? {my log notice "Httpd ready on port $port"}
	}

	#>>>
	method _close_listen {} { #<<<
		if {[info exists listen]} {
			if {$listen in [chan names]} {
				chan close $listen
			}
			unset listen
		}
	}

	#>>>
	method log {lvl msg args} { #<<<
		puts stderr $msg
	}

	unexport log
	#>>>
}


