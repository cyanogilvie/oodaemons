# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

cflib::pclass create oodaemons::ftpd {
	property port			21 _need_rebind
	property ip				"" _need_rebind
	property con_handler	"oodaemons::ftpd_con"

	variable {*}{
		dominos
		listen
	}

	constructor {args} { #<<<
		sop::domino new dominos(rebind) -name "[self] rebind"

		$dominos(rebind) attach_output [my code _rebind]

		my configure {*}$args
	}

	#>>>
	destructor { #<<<
		my _close_listen
	}

	#>>>
	method _need_rebind {} { #<<<
		$dominos(rebind) tip
	}

	#>>>
	method _rebind {} { #<<<
		my _close_listen

		if {$ip ne ""} {
			set listen	[socket -server [my code _accept] -myaddr $ip $port]
		} else {
			set listen	[socket -server [my code _accept] $port]
		}
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
	method accept {socket cl_ip cl_port} { #<<<
		return 1
	}

	#>>>
	method _accept {socket cl_ip cl_port} { #<<<
		set accept_ok	0
		try {
			my accept $socket $cl_ip $cl_port
		} trap {DENY} {errmsg options} {
			set accept_ok	0
		} on error {errmsg options} {
			my log LOG_ERR "Unexpected error in accept callback: $errmsg\n[dict get $options -errorinfo]"
			set accept_ok	0
		} on ok {res options} {
			if {$res} {
				set accept_ok	1
			} else {
				set accept_ok	0
			}
		}

		if {$accept_ok} {
			my log LOG_INFO "Accepting connection from $cl_ip:$cl_port"
			$con_handler new $socket $cl_ip $cl_port
		} else {
			my log LOG_WARNING "Rejecting connection from $cl_ip:$cl_port"
			chan close $socket
		}
	}

	#>>>
	method log {lvl msg} { #<<<
		puts stderr $msg
	}

	unexport log
	#>>>
}


