# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create oodaemons::httpd::con {
	variable {*}{
		con
		client_ip
		client_port
		httpd
		use_keepalive
		dominos
		myseq
		req_pipeline
		response_buffer
		parse_state
		linemode
		entity_encoding_in
		entity_encoding_out
		headers_in
	}

	constructor {settings} { #<<<
		set req_pipeline		{}
		set response_buffer		[dict create]
		set linemode			1
		set entity_encoding_in	"utf-8"
		set entity_encoding_out	"utf-8"
		set headers_in			{}

		set use_keepalive	1
		dict for {k v} $settings {
			set $k $v
		}
		array set dominos	{}

		if {[info commands "\?\?"] eq {}} {
			proc ::?? {args} {}
		}

		namespace eval [self class] {
			variable sockseq
		}
		upvar [self class]::sockseq sockseq
		set myseq	[incr sockseq]

		?? {
			dict set ::g_con_stats $myseq [dict create \
					start		[clock microseconds] \
					httpd_con	[self] \
					client_ip	$client_ip \
					client_port	$client_port \
					requests	[dict create] \
					events		{} \
			]
		}

		foreach reqf {con client_ip client_port httpd} {
			if {![info exists $reqf] || [set $reqf] eq ""} {
				error "Must set -$reqf" "" [list syntax_error]
			}
		}

		#set baselog_instancename	"$con,$myseq"

		chan configure $con \
				-blocking 0 \
				-buffering none

		my _set_parse_state "entity-header"

		chan event $con readable [namespace code {my _readable}]
		#chan event $con writable [namespace code {my _writable}]
	}

	#>>>
	destructor { #<<<
		foreach req $req_pipeline {
			if {[info object isa object $req]} {
				$req destroy
			}
		}
		set req_pipeline	{}
		if {[info exists con]} {
			if {$con in [chan names]} {
				?? {my log notice "closing connection $con"}
				chan close $con
			}
			unset con
		}
		dict set ::g_con_stats $myseq end [clock microseconds]
	}

	#>>>

	method send_response {from code headers {entity_body ""}} { #<<<
		?? {my log debug}
		if {$from ne [self] && $from ne [lindex $req_pipeline 0]} {
			dict set response_buffer $from [dict create \
					from	$from \
					code	$code \
					headers	$headers \
					entity_body	$entity_body \
			]
			return
		}

		my _send_response $code $headers $entity_body

		if {$from eq [lindex $req_pipeline 0]} {
			set req_pipeline	[lrange $req_pipeline 1 end]
			while {[dict exists $response_buffer [lindex $req_pipeline 0]]} {
				set req_pipeline	[lassign $req_pipeline this_req]
				my _send_response \
						[dict get $response_header $this_req code] \
						[dict get $response_header $this_req headers] \
						[dict get $response_header $this_req entity_body]
			}
		}

		# In non-blocking mode (which we are), this doesn't wait for the flush
		chan flush $con
		#chan flush stdout
	}

	#>>>
	method get_myseq {} { #<<<
		return $myseq
	}

	#>>>

	method _readable {} { #<<<
		?? {dict set ::g_con_stats $myseq events [clock microseconds] readable}
		if {![info exists con]} {
			my log error "Con disappeared!"
			return
		}
		try {
			if {$linemode} {
				chan configure $con \
						-translation crlf \
						-buffering line \
						-encoding "ascii"

				while {1} {
					set line		[chan gets $con]
					if {[chan blocked $con]} return
					if {[chan eof $con]} break
					#?? {puts $line}
					if {$line eq ""} {
						if {$headers_in eq ""} {
							?? {my log debug "Ignoring blank line preceding request-line"}
							# RFC specifies that blank lines before a request-line
							# must be ignored
							continue
						}
						set req		[oodaemons::httpd::req new $httpd [self]]
						lappend req_pipeline	$req
						[$req signal_ref ready] attach_output \
								[namespace code {my _req_ready_changed}]
						?? {
							my log debug "New request headers:\n[join $headers_in \n\t]"
						}
						set tmp		$headers_in
						set headers_in	{}
						$req _set_headers_raw $tmp
						if {![info object isa object $req]} {
							?? {my log warning "req ($req) is stillborn"}
							set req_pipeline	[lrange $req_pipeline 0 end-1]
							return
						}
						?? {my log debug "got req: ($req)"}
						set headers_in		{}
						if {[$req expecting_entity]} {
							?? {my log debug "Expecting an entity, turning linemode off"}
							set linemode		0
							break
						} else {
							?? {my log debug "Not expecting an entity, ready for next request"}
						}
					} else {
						lappend headers_in	$line
					}
				}
			}
			
			if {!($linemode)} {
				?? {my log debug "out of linemode, try to read some entity data"}
				if {[llength $req_pipeline] == 0 || ![info object isa object [lindex $req_pipeline end]]} {
					my log error "Pending request MIA: [lindex $req_pipeline end]"
					throw {http_error 500} "Pending request MIA"
				}
				[lindex $req_pipeline end] _entity_data_ready $con
			}

			if {[chan eof $con]} {
				?? {my log debug "Got EOF, closing"}
				my destroy
				return
			}
		} trap {http_error} {errmsg options} {
			set code			[lindex [dict get $options -errorcode] 1]
			set extra_headers	[lindex [dict get $options -errorcode] 2]
			set user_message	"$errmsg\n"
			?? {my log debug "http_error: ($code)"}

			?? {my log debug "sending error response"}
			my send_response [self] $code $extra_headers $user_message
		} on error {errmsg options} {
			my log error "Error in _readable: $errmsg\n[dict get $options -errorinfo]"
			set user_message	"Internal Server Error\n"
			set extra_headers	{connection close}
			set code			500

			?? {my log debug "sending error response"}
			my send_response [self] $code $extra_headers $user_message
			?? {my log error "Forcing panic close due to unexpected error in readable callback"}
			my destroy
			return
		}
	}

	#>>>
	method _writable {} { #<<<
		# In non-blocking mode, Tcl takes care of internal buffering
	}

	#>>>
	method _set_parse_state {newstate} { #<<<
		switch -- $newstate {
			"entity-header" {
				set parse_state	$newstate
				set translation	[chan configure $con -translation]
				lset translation 0 crlf
				chan configure $con \
						-translation $translation \
						-buffering line \
						-encoding "ascii"
			}

			"entity-body" {
				set parse_state	$newstate
				set translation	[chan configure $con -translation]
				lset translation 0 lf
				chan configure $con -translation $translation
			}

			default {
				error "Invalid parse state: ($parse_state)"
			}
		}
	}

	#>>>
	method _apply_transfer_encoding {headers entity_body} { #<<<
		# TODO: implement
		?? {
			my log warning "_apply_transfer_encoding: Not implemented yet"
		}
		return $entity_body
	}

	#>>>
	method _serialize_mime_headers {headers} { #<<<
		set serialized	""

		dict for {header values} $headers {
			switch -- [string tolower $header] {
				"accept-ranges" -
				"age" -
				"etag" -
				"location" -
				"proxy-authenticate" -
				"retry-after" -
				"server" -
				"vary" -
				"www-authenticate" {
					#if {[llength $values] != 1} {
					#	my log warning "Header $header requires a single value"
					#}
					set type	"response_header"
				}

				default {
					set type	"entity_header"
				}
			}
			switch -- [string tolower $header] {
				"accept-ranges" {
					set value	[lindex $values 0]
					if {[string tolower $value] ni {bytes none}} {
						my log warning "Accept-Ranges header should be one of \"bytes\" or \"none\", got \"$value\""
					}
				}

				"age" {
					set value	[lindex $values 0]
					if {![string is integer -strict $value]} {
						set values	[list [expr {2**31}]]
					}
				}

				"location" {
					set values	[list encode_uri [lindex $values 0]]
				}

				"proxy-authenticate" -
				"retry-after" -
				"server" -
				"vary" -
				"www-authenticate" {
					set type	"response_header"
				}

				default {
					set type	"entity_header"
				}
			}
			append serialized	$header ": " $values "\n"
		}

		return $serialized
	}

	#>>>
	method _req_ready_changed {newstate} { #<<<
		?? {my log debug}
		if {$newstate} {
			set linemode	1
			try {
				$httpd got_req [lindex $req_pipeline end]
			} trap {http_error} {errmsg options} {
				set code			[lindex [dict get $options -errorcode] 1]
				set extra_headers	[lindex [dict get $options -errorcode] 2]
				set user_message	"$errmsg\n"
				?? {my log debug "http_error: ($code)"}

				?? {my log debug "sending error response"}
				my send_response [self] $code $extra_headers $user_message
			} on error {errmsg options} {
				my log error "Error in _readable: $errmsg\n[dict get $options -errorinfo]"
				set user_message	"Internal Server Error\n"
				set extra_headers	{connection close}
				set code			500

				?? {my log debug "sending error response"}
				my send_response [self] $code $extra_headers $user_message
				?? {my log error "Forcing panic close due to unexpected error in readable callback"}
				my destroy
				return
			}
		}
	}

	#>>>
	method _send_response {code headers entity_body} { #<<<
		?? {dict set ::g_con_stats $myseq events [clock microseconds] respond $code}
		?? {my log debug "entity_body:\n$entity_body"}
		chan configure $con \
				-translation crlf \
				-encoding "ascii" \
				-buffering full

		try {
			set desc	[$httpd lookup_code $code]
		} on error {errmsg options} {
			my log error "Unexpected error looking up code \"$code\": $errmsg"
			set code	500
			set desc	"Internal Server Error"
		}
		?? {my log debug "response: $code \"$desc\""}
		if {
			[string index $code 0] ne "1" &&
			$code ni {204 304} &&
			$entity_body ne ""
		} {
			set has_entity	1
			if {[dict exists $headers content-encoding]} {
				set to_encoding		[dict get $headers content-encoding]
				if {$to_encoding ni [encoding names]} {
					my log error "response content-encoding not supported: \"$to_encoding\""
				}
				?? {my log debug "Converting to encoding ($to_encoding)"}
				set encoded_body	[encoding convertto $to_encoding $entity_body]
			} else {
				set encoded_body	$entity_body
			}
			dict set headers content-length [string length $encoded_body]
		} else {
			set has_entity	0
		}
		dict set headers server "Experimental oodaemons HTTP Server 0.1"
		if {!$use_keepalive} {
			dict set headers connection close
		} else {
			dict set headers connection "Keep-Alive"
			dict set headers keep-alive "timeout=30, max=600"
		}
		chan puts $con "HTTP/1.1 $code $desc"
		?? {chan puts "HTTP/1.1 $code $desc"}
		chan puts -nonewline $con [my _serialize_mime_headers $headers]
		?? {chan puts -nonewline [my _serialize_mime_headers $headers]}
		chan puts $con ""
		?? {chan puts ""}

		if {
			[string index $code 0] ne "1" &&
			$code ni {204 304} &&
			$entity_body ne ""
		} {
			chan configure $con \
					-translation lf \
					-encoding binary
			set tx_encoded	[my _apply_transfer_encoding $headers $encoded_body]
			chan puts -nonewline $con $tx_encoded
			?? {chan puts $tx_encoded; chan flush stdout}
		}
	}

	#>>>
	method log {lvl {msg ""} args} { #<<<
		puts stderr $msg
	}

	unexport log
	#>>>
}


