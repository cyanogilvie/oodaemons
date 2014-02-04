# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create oodaemons::ftpd_con {
	variable {*}{
		socket
		client_info
	}

	constructor {a_socket cl_ip cl_port} { #<<<
		set socket			$a_socket
		set client_info		"$cl_ip:$cl_port"

		set coro	"::consumer_[string map {:: _} [self]]"
		coroutine $coro my _consumer
		chan event $socket readable [list $coro]
		my log LOG_DEBUG "Set up command socket readable event"

		my _send 220 "Connected"
	}

	#>>>
	destructor { #<<<
		my _close
	}

	#>>>
	method _close {} { #<<<
		my variable pasv_listen_socket pasv_data_socket

		if {[info exists pasv_listen_socket]} {
			if {$pasv_listen_socket in [chan names]} {
				try {
					close $pasv_listen_socket
				} on error {errmsg options} {
					my log LOG_ERR "Error closing PASV listen socket: $errmsg"
				} on ok {} {
					my log LOG_DEBUG "Closed PASV listen socket"
				}
			}
			unset pasv_listen_socket
		}

		if {[info exists pasv_data_socket]} {
			if {$pasv_data_socket in [chan names]} {
				try {
					close $pasv_data_socket
				} on error {errmsg options} {
					my log LOG_ERR "Error closing PASV data socket: $errmsg"
				} on ok {} {
					my log LOG_DEBUG "Closed PASV data socket"
				}
				unset pasv_data_socket
			}
		}

		if {[info exists socket]} {
			if {$socket in [chan names]} {
				# Could this leak coroutines?
				try {
					chan close $socket
				} on error {errmsg options} {
					my log LOG_ERR "Error closing command socket: $errmsg"
				} on ok {} {
					my log LOG_INFO "Closed command socket from $client_info"
				}
			}
			unset socket
		}
	}

	#>>>
	method _consumer {} { #<<<
		try {
			while {1} {
				my log LOG_DEBUG "Readable fired"
				my _cmd_processor
			}
		} trap {close} {} {
			# Destructor will take care of it
		} on error {errmsg options} {
			my log LOG_ERR "Unhandled error in _consumer: $errmsg\n[dict get $options -errorinfo]"
		} finally {
			my destroy
		}
	}

	#>>>
	method _cmd_processor {} { #<<<
		# Authentication <<<
		while {1} {
			lassign [my _readcommand] cmd rest

			if {$cmd ne "USER"} {
				my _send 530 "Please login with USER and PASS"
				continue
			}
			my _send 331 "User ok, send password"

			set user	$rest

			lassign [my _readcommand] cmd rest

			if {$cmd ne "PASS"} {
				my _send 530 "Please login with USER and PASS"
				continue
			}

			set pass	$rest

			if {![my authenticate $user $pass]} {
				my _send 530 "Invalid credentials"
				continue
			}

			my _send 230 "Logged in ok"
			break
		}
		# Authentication >>>

		while {1} {
			lassign [my _readcommand] cmd rest

			switch -- $cmd {
				"TYPE" { #<<<
					if {$rest eq "I"} {
						my log LOG_ERR "got unsupported type req: ($rest)"
						my _send 200 "Type is now 8-bit binary"
					} else {
						my _send 504 "Type not supported"
					}
					#>>>
				}
				"PWD" { #<<<
					my _send 257 "\"/\""
					#>>>
				}
				"FEAT" { #<<<
					set supported {
						PASV
					}
					my _send 211 "Extensions supported:\n [join $supported "\n "]\nEnd."
					#>>>
				}
				"PASV" { #<<<
					set pasv_info	[my _pasv_open]
					my _send 227 "Entering passive mode ($pasv_info)"
					#>>>
				}
				"ALLO" { #<<<
					my variable pasv_expecting
					if {![string is digit -strict $rest]} {
						my _send 501 "Cannot parse specified size: \"$rest\""
					} else {
						set pasv_expecting	$rest
						my _send 200 "No pre-allocation required"
					}
					#>>>
				}
				"PORT" { #<<<
					my _send 500 "Port not supported, use passive mode"
					#>>>
				}
				"STOR" { #<<<
					my variable incoming_filename pasv_data_socket

					set incoming_filename	$rest
					my log LOG_DEBUG "Saving incoming_filename: \"$incoming_filename\""
					if {[info exists pasv_data_socket]} {
						my _send 150 "Accepted data connection"
					} else {
						my variable need_stor_resp
						set need_stor_resp	1
					}
					#>>>
				}
				"QUIT" { #<<<
					my _send 221 "Logout."
					throw {close} ""
					#>>>
				}
				default { #<<<
					my _send 500 "Unsupported command $cmd"
					#>>>
				}
			}
		}
	}

	#>>>
	method _readcommand {} { #<<<
		chan configure $socket \
				-blocking 0 \
				-buffering line \
				-translation crlf \
				-encoding iso8859-1

		while {1} {
			set line	[gets $socket]
			if {[chan eof $socket]} {throw {close} ""}
			if {![chan blocked $socket]} break
			my log LOG_DEBUG "Waiting for command"
			yield
		}

		if {![regexp {^([^\s]+)\s+(.*)$} $line -> cmd rest]} {
			set cmd		$line
			set rest	{}
		}

		set cmd		[string trim [string toupper $cmd]]
		set rest	[string trim $rest]

		my log LOG_DEBUG "Read command ($cmd) ($rest)"
		return [list $cmd $rest]
	}

	#>>>
	method _send {code msg} { #<<<
		set respdata	""
		if {[string first "\n" $msg] == -1} {
			set respdata	"$code $msg"
		} else {
			# Multi-line response.  Handle in the convoluted fashion specified
			# in RFC 959
			set lines	[split $msg "\n"]
			set respdata	"$code-[lindex $lines 0]\n"
			foreach line [lrange $lines 1 end-1] {
				if {[regexp {^[0-9]{3}\s} $line]} {
					set line	" $line"
				}
				append respdata	$line \n
			}
			append respdata	"$code [lindex $lines end]"
		}
		my log LOG_DEBUG "Sending response:\n$respdata"
		puts $socket $respdata
		flush $socket
	}

	#>>>
	method authenticate {user pass} { #<<<
		# Override and return a boolean
		if {$user in {anonymous ftp}} {
			return 1
		} else {
			return 0
		}
	}

	unexport authenticate
	#>>>
	method _pasv_open {} { #<<<
		my variable pasv_listen_socket pasv_data_socket

		if {[info exists pasv_data_socket]} {
			if {$pasv_data_socket in [chan names]} {
				try {
					close $pasv_data_socket
				} on error {errmsg options} {
					my log LOG_ERR "Error closing existing PASV data socket: $errmsg"
				}
			}
			unset pasv_data_socket
		}

		if {[info exists pasv_listen_socket]} {
			if {$pasv_listen_socket in [chan names]} {
				try {
					close $pasv_listen_socket
				} on error {errmsg options} {
					my log LOG_ERR "Error closing PASV listen socket: $errmsg"
				}
			}
			unset pasv_listen_socket
		}

		set pasv_listen_socket	[socket -server [namespace code {my _pasv_accept}] 0]
		my log LOG_DEBUG "Getting allocated PASV listen port"
		lassign [chan configure $pasv_listen_socket -sockname] \
				addr hostname port
		my log LOG_DEBUG "Getting our address from client command socket"
		lassign [chan configure $socket -sockname] \
				command_addr command_hostname command_port
		my log LOG_DEBUG "Finished gathering info for pasv_info"

		set info	[split $command_addr .]

		set port_top	[expr {$port >> 8}]
		set port_bot	[expr {$port & 0xff}]

		lappend info	$port_top $port_bot

		return [join $info ,]
	}

	#>>>
	method _pasv_accept {pasv_socket cl_ip cl_port} { #<<<
		my variable pasv_data_socket pasv_expecting
		if {[info exists pasv_pasv_data_socket]} {
			my log LOG_ERR "Already accepted a connection on PASV port, got another from $cl_ip:$cl_port"
			close $pasv_data_socket
			return
		}

		set pasv_data_socket	$pasv_socket

		chan configure $pasv_data_socket \
				-blocking 0 \
				-buffering full \
				-translation binary \
				-encoding binary

		set coro	"::pasv_data_reader_[string map {:: _} [self]]"
		coroutine $coro my _pasv_read_data
		my variable need_stor_resp
		if {[info exists need_stor_resp] && $need_stor_resp} {
			my _send 150 "Accepted data connection"
			unset need_stor_resp
		}
		chan event $pasv_data_socket readable [list $coro]
	}

	#>>>
	method _pasv_read_data {} { #<<<
		my variable \
				pasv_data_socket \
				pasv_listen_socket \
				pasv_expecting \
				incoming_filename

		try {
			set data	""
			while {1} {
				set chunk	[read $pasv_data_socket]

				if {[chan eof $pasv_data_socket]} {
					my log LOG_DEBUG "PASV data socket closed"
					if {
						[info exists pasv_expecting] &&
						[string length $data] != $pasv_expecting
					} {
						throw {close error 450} "Not storing file, promised $pasv_expecting bytes, gave [string length $data]"
					} else {
						try {
							if {![info exists incoming_filename]} {
								my log LOG_WARNING "No STOR command received"
								return
							}
							my receive_file $incoming_filename $data
							my log LOG_DEBUG "Saved file"
						} trap {STORE_FAILED} {errmsg} {
							my log LOG_WARNING "Store rejected: $errmsg"
							throw {close error 450} $errmsg
						} on error {errmsg options} {
							my log LOG_ERR "Error storing file \"$incoming_filename\": $errmsg\n[dict get $options -errorinfo]"
							throw {close error 450} "Internal error"
						} on ok {} {
							my log LOG_DEBUG "receive_file successful, signalling close"
							throw {close normal} ""
						}
					}
				}

				set chunklen	[string length $chunk]
				if {$chunklen == 0} {
					my log LOG_DEBUG "Waiting for more data on PASV data channel"
					yield
					my log LOG_DEBUG "PASV data channel readable"
					continue
				}

				append data	$chunk
				my log LOG_DEBUG "Recevied chunk on PASV data channel, total now: [string length $data]"
			}
		} trap {close normal} {} { #<<<
			my log LOG_DEBUG "got close normal"
			my _send 226 "File received successfully"
			#>>>
		} trap {close error} {errmsg options} { #<<<
			set code	[lindex [dict get $options -errorcode] 2]
			if {![regexp {^[0-9]{3}$} $code]} {
				my log LOG_ERR "Invalid custom code specified: \"$code\""
				set code	450
			}
			my log LOG_ERR "Error with data connection: $errmsg"
			my _send $code $errmsg
			#>>>
		} on error {errmsg options} { #<<<
			my log LOG_ERR "Unexpected error handling data connection: $errmsg\n[dict get $options -errorinfo]"
			my _send 450 "Internal error"
			#>>>
		} finally { #<<<
			if {[info exists pasv_data_socket]} {
				if {$pasv_data_socket in [chan names]} {
					try {
						close $pasv_data_socket
					} on error {errmsg options} {
						my log LOG_ERR "Error closing PASV data connection: $errmsg"
					}
				}
				unset pasv_data_socket
			}

			if {[info exists pasv_expecting]} {
				unset pasv_expecting
			}
			#>>>
		}
	}

	#>>>
	method log {lvl msg} { #<<<
		puts stderr $msg
	}

	unexport log
	#>>>
	method receive_file {filename data} { #<<<
		# Override, throw {STORE_FAILED} with error message for the user if
		# not successful
		my log LOG_INFO "Would store [string length $data] bytes in \"$filename\""
		throw {STORE_FAILED} "Saving files not implemented"
	}

	#>>>
}


