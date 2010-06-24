# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create oodaemons::httpd::req {
	superclass sop::signalsource

	variable {*}{
		signals
		httpd
		httpd_con
		headers
		expecting_entity
		entity_charset
		length_mode
		uri
		expecting
		raw_entity
		entity_body
		chunked_read_state
		trailer_lines
		cleanup_objs
		request_line
		con_seq
		extravars
	}

	constructor {a_httpd a_httpd_con} { #<<<
		set httpd				$a_httpd
		set httpd_con			$a_httpd_con
		set expecting_entity	0
		set raw_entity			""
		set entity_body			""
		set chunked_read_state	"chunk-size"
		set trailer_lines		{}
		set cleanup_objs		[dict create]
		set request_line		[dict create]
		set extravars			[dict create]

		sop::signal new signals(ready) -name "[self] received"

		set con_seq		[$httpd_con get_myseq]

		?? {
			dict set ::g_con_stats $con_seq requests [self] [dict create \
					start		[clock microseconds] \
			]
		}

		#set baselog_instancename "[self]($httpd_con,$con_seq)"
		next
	}

	#>>>
	destructor { #<<<
		?? {my log notice "request [self] dieing"}
		dict for {name obj} $cleanup_objs {
			if {[info object isa object $obj]} {
				$obj destroy
			}
			dict unset cleanup_objs $name
		}
		?? {
			dict set ::g_con_stats $con_seq requests [self] [dict create \
					end		[clock microseconds] \
			]
		}
	}

	#>>>

	method expecting_entity {} { #<<<
		return $expecting_entity
	}

	#>>>
	method request_uri {} { #<<<
		return $uri
	}

	#>>>
	method headers {} { #<<<
		set headers
	}

	#>>>
	method send_response {respinfo} { #<<<
		set respinfo	[dict merge {
			code				200
			mimetype			"text/html"
			content-encoding	"utf-8"
			response-headers	{}
			response-data		""
		} $respinfo]

		if {[dict get $respinfo content-encoding] eq "binary"} {
			if {[dict exists $respinfo charset]} {
				dict set respinfo response-headers content-type "[dict get $respinfo mimetype]; charset=[dict get $respinfo charset]"
			} else {
				dict set respinfo response-headers content-type "[dict get $respinfo mimetype]"
			}
		} else {
			dict set respinfo response-headers content-type "[dict get $respinfo mimetype]; charset=[dict get $respinfo content-encoding]"
			dict set respinfo response-headers content-encoding [dict get $respinfo content-encoding]
		}

		$httpd_con send_response [self] \
				[dict get $respinfo code] \
				[dict get $respinfo response-headers] \
				[dict get $respinfo response-data]
		?? {my log debug "[self] dieing"}
		my destroy
	}

	#>>>

	# compatibility with old Reqobj
	method dump_vars {} { #<<<
		set request_uri	[$uri as_dict]
		?? {
			array set r $request_line
			parray debug r
		}
		if {![dict exists $request_line method]} {
			my log error "Request method not defined:"
			array set r $request_line
			parray error r
		}
		switch -- [dict get $request_line method] {
			"OPTIONS" -
			"GET" {
				return [dict get $request_uri query]
			}

			"POST" {
				if {[dict exists $headers content-type]} {
					lassign [my _parse_mime_params [dict get $headers content-type]] \
							content_type \
							content_type_params
				} else {
					set content_type		"application/x-www-form-urlencoded"
					set content_type_params	[dict create]
					my log warning "No content-type specified - assuming $content_type"
				}

				switch -- $content_type {
					"mutlipart/form" {
						# TODO: should the encoding transform happen after the
						# hexhex decode
						return [my _parse_mime_headers $entity_body]
					}

					"application/x-www-form-urlencoded" {
						# TODO: should the encoding transform happen after the
						# hexhex decode?
						return [$uri query_decode $entity_body]
					}

					"text/json" {
						if {![dict exists $cleanup_objs json_params]} {
							dict set cleanup_objs json_params \
									[oodaemons::json new]
							[dict get $cleanup_objs json_params] parse $entity_body
						}
						set j			[dict get $cleanup_objs json_params]
						set basenode	[[$j root] firstChild]
						switch -- [$basenode nodeName] {
							"list" {
								set childnodes	[$basenode childNodes]
								if {[llength $childnodes] == 0} {
									return {}
								} elseif {[llength $childnodes] == 1} {
									return [$j as_dict [lindex $childnodes 0]]
								} else {
									my log warning "Got a list of more than 1 item, returning dict of item 0"
									return [$j as_dict [lindex $childnodes 0]]
								}
							}

							"object" {
								return [$j as_dict $basenode]
							}
						}
					}

					default {
						error "Don't know how to deal with content_type ($content_type)"
					}
				}
			}

			default {
				error "Can only supply variables for GET and POST requests, this is a [dict get $request_uri method]"
			}
		}
	}

	#>>>
	method json_obj {} { #<<<
		if {![dict exists $cleanup_objs json_params]} {
			error "No json associated with request"
		}
		return [dict get $cleanup_objs json_params]
	}

	#>>>
	method store_var {name value} { #<<<
		dict set extravars $name $value
	}

	#>>>
	method retrieve_var {name args} { #<<<
		if {[dict exists $extravars $name]} {
			return [dict get $extravars $name]
		} else {
			switch -- [llength $args] {
				0 {
					throw [list variable_not_set $name] \
							"No value set for variable \"$name\""
				}

				1 {
					?? {
						my log debug "name ($name) doesn't exist, sending default"
						my log debug "vars set:"
						array set e $extravars
						parray debug e
						unset e
					}
					return [lindex $args 0]
				}

				default {
					throw {syntax_error} "Too many arguments"
				}
			}
		}
	}

	#>>>

	# These are public so that httpd::con can call them.  Not intended
	# to be called by consumers of this class
	method _set_headers_raw {headers_raw} { #<<<
		?? {set before_usec	[clock microseconds]}
		set headers_lines	[lassign $headers_raw request_line_raw]
		lassign [split $request_line_raw] \
				method request_uri_encoded http_version
		set method	[string toupper $method]
		set uri		[oodaemons::uri new $request_uri_encoded]

		dict set request_line method $method
		dict set request_line uri $uri
		dict set request_line http_version $http_version
		?? {
			dict set ::g_con_stats $con_seq requests [self] \
					request_line $request_line
		}
		?? {my log debug "$method [dict get [$uri as_dict] path]"}

		# TODO: verify $http_version

		set headers	[my _parse_request_headers $headers_lines]

		#my log debug "got \"$method\" for URI \"$request_uri_encoded\", version \"$http_version\":"
		#array set request		[$uri as_dict]
		#parray debug request
		#array set reqhdr	$headers
		#parray debug reqhdr

		# Determine entity-body encoding <<<
		# TODO: for method OPTIONS, entity-body is optional
		if {$method in {POST PUT}} {
			set length_mode	"chunked"
			if {[dict exists $headers transfer-encoding]} {
				set encodings	[string tolower [dict get $headers transfer-encoding]]
				if {$encodings eq {identity}} {
					set length_mode	"content-length"
				} else {
					if {[lindex $encodings end] ne "chunked"} {
						throw {http_error 400} "When using a non-identity Transfer-Encoding, chunked must be the last applied encoding"
					}
				}
			} else {
				set length_mode	"content-length"
			}
			if {$length_mode eq "content-length"} {
				if {![dict exists $headers content-length]} {
					throw {http_error 411} "Require a Content-Length or Transfer-Encoding header to determine message length"
				}
				set expecting	[dict get $headers content-length]
			}
			set expecting_entity	1
		}
		?? {my log debug "Are we expecting an entity? (method: [dict get $request_line method]): $expecting_entity"}
		if {$expecting_entity} {
			if {[dict exists $headers content-type]} {
				lassign [my _parse_mime_params [dict get $headers content-type]] \
						content_type \
						content_type_params

				if {[dict exists $content_type_params charset]} {
					set entity_charset	[string tolower [dict get $content_type_params charset]]
				} elseif {[dict exists $headers content-encoding]} {
					set entity_charset	[string tolower [dict get $headers content-encoding]]
				} else {
					set entity_charset	"iso8859-1"
				}
			}
		} else {
			$signals(ready) set_state 1
		}
		# Determine entity-body encoding >>>
		?? {
			set after_usec	[clock microseconds]
			puts stderr "_set_headers_raw: [expr {$after_usec - $before_usec}]"
		}
	}

	export _set_headers_raw
	#>>>
	method _entity_data_ready {con} { #<<<
		switch -- $length_mode {
			"content-length" { #<<<
				chan configure $con \
						-translation lf \
						-buffering none \
						-encoding binary

				set dat	[chan read $con $expecting]
				if {[chan eof $con]} {
					# TODO: think carefully about this
					$httpd_con destroy
					return
				}
				set got	[string length $dat]
				incr expecting -$got
				append raw_entity	$dat
				#>>>
			}
			"chunked" { #<<<
				# Crikey.  Whoever cooked this one up was on some very exotic drugs
				while {1} {
					switch -- $chunked_read_state {
						"chunk-size" { #<<<
							chan configure $con \
									-translation crlf \
									-buffering line \
									-encoding binary

							set line	[gets $con]
							if {[chan blocked $con]} return
							if {[chan eof $con]} {
								# TODO: think carefully about this
								$httpd_con destroy
								return
							}
							set chunk_extensions \
									[lassign [my _parse_mime_params $line] chunk_length]
							if {![string is xdigit -strict $chunk_length]} {
								throw {http_error 400 {connection close}} "Invalid transfer-encoding: chunked encoding: expecting hex chunk length, got ($chunk_length)"
							}
							set expecting	[expr "0x$chunk_length"]	;# ouch
							if {$expecting == 0} {
								set chunked_read_state	"trailer"
							} else {
								set chunked_read_state	"chunk-body"
							}
							#>>>
						}

						"chunk-body" { #<<<
							chan configure $con \
									-translation lf \
									-buffering none \
									-encoding binary

							set dat	[chan read $con $expecting]
							if {[chan eof $con]} {
								# TODO: think carefully about this
								$httpd_con destroy
								return
							}
							set got	[string length $dat]
							incr expecting -$got
							append raw_entity	$dat

							if {$expecting == 0} {
								?? {my log debug "Unset expecting: ready for next chunk"}
								unset expecting
								set chunked_read_state	"chunk-size"
							}
							#>>>
						}

						"trailer" { #<<<
							chan configure $con \
									-translation crlf \
									-buffering line \
									-encoding binary

							while {1} {
								set line	[chan gets $con]
								if {[chan blocked $con]} return
								if {[chan eof $con]} {
									# TODO: think carefully about this
									$httpd_con destroy
									return
								}

								if {$line eq ""} {
									break
								}
								lappend trailer_lines $line
							}
							#>>>
						}

						default { #<<<
							throw {http_error 500 {connection close}} "Invalid chunk parse state ($chunked_read_state)"
							#>>>
						}
					}
				}
				#>>>
			}
			default { #<<<
				throw {http_error 500 {connection close}} "Unexpected length_mode: ($length_mode), must be one of (content-length) or (chunked)"
				#>>>
			}
		}

		if {[info exists expecting] && $expecting == 0} {
			set entity_body	[encoding convertfrom $entity_charset $raw_entity]
			?? {my log debug "Unset expecting: got all we are after"}
			unset expecting
			?? {my log debug "Got entity_body:\n$entity_body"}
			$signals(ready) set_state 1
		}
	}

	export _entity_data_ready
	#>>>

	method _parse_request_headers {lines} { #<<<
		return [my _parse_mime_headers $lines {
			accept
			accept-charset
			accept-encoding
			accept-language
			expect
			if-match
			if-none-match
			te
			user-agent

			cache-control
			connection
			pragma
			trailer
			transfer-encoding
			upgrade
			via
			warning

			allow
			content-encoding
			content-language
		}]
	}

	#>>>
	method _parse_mime_headers {lines {list_types {}}} { #<<<
		set headers	[dict create]
		set lines	[my _unfold_headers $lines]

		?? {
			set list_timings	{}
			set straight_timings	{}
		}
		foreach line $lines {
			set idx	[string first ":" $line]
			if {$idx == -1} {
				my log error "Invalid mime header line: ($line)"
				continue
			}
			set field_name	[string tolower [string range $line 0 $idx-1]]
			set field_value	[string trim [string range $line $idx+1 end]]
			if {$field_name in $list_types} {
				if {[dict exists $headers $field_name]} {
					set old	[dict get $headers $field_name]
				} else {
					set old	{}
				}
				?? {set before_usec	[clock microseconds]}
				dict set headers $field_name [concat $old [my _split_mime_values $field_value]]
				?? {
					set after_usec	[clock microseconds]
					lappend list_timings	[expr {$after_usec - $before_usec}]
				}
			} else {
				?? {set before_usec	[clock microseconds]}
				dict set headers $field_name $field_value
				?? {
					set after_usec	[clock microseconds]
					lappend straight_timings	[expr {$after_usec - $before_usec}]
				}
			}
		}

		?? {
			puts "list_timings: ($list_timings)"
			if {[llength $list_timings] > 0} {
				puts "average list times: [expr {[tcl::mathop::+ {*}$list_timings] / double([llength $list_timings])}]"
			}
			puts "average straight times: [expr {[tcl::mathop::+ {*}$straight_timings] / double([llength straight_timings])}]"
		}

		return $headers
	}

	#>>>
	method _unfold_headers {lines} { #<<<
		set out_lines	{}
		set current_line	""
		foreach line $lines {
			if {[string index $line 0] in {" " "\t"}} {
				# Folded line continuation
				append current_line	" " [string trim $line]
			} else {
				if {$current_line ne ""} {
					lappend out_lines	$current_line
					set current_line	""
				}
				set current_line	$line
			}
		}
		if {$current_line ne ""} {
			lappend out_lines	$current_line
			set current_line	""
		}

		#my log debug "returning unfolded lines:\n[join $out_lines \n]"
		return $out_lines
	}

	#>>>
	method _split_mime_values {field_value} { #<<<
		set valuelist	{}
		set build		""
		set state		"plain"
		set last_state	""
		set field_length	[string length $field_value]
		for {set i 0} {$i < $field_length} {incr i} {
			set c	[string index $field_value $i]
			switch -- $state {
				"plain" {
					switch -- $c {
						"\"" {
							set state	"qstring"
						}

						"\\" {
							set last_state	$state
							set state		"backquote"
						}

						"," {
							if {$build ne ""} {
								# RFC says empty list elements don't count
								lappend valuelist	$build
								set build	""
							}
						}

						default {
							append build	$c
						}
					}
				}

				"backquote" {
					append build	$c
					set state		$last_state
				}

				"qstring" {
					switch -- $c {
						"\"" {
							set state	"plain"
						}

						"\\" {
							set last_state	$state
							set state	"backquote"
						}

						default {
							append build	$c
						}
					}
				}

				default {
					error "Bogus parse state: ($state)"
				}
			}
		}
		if {$build ne ""} {
			lappend valuelist	$build
		}
		return $valuelist
	}

	#>>>
	method _parse_mime_params {raw_field_value} { #<<<
		set valuelist	{}
		set build	""
		set state	"plain"
		set last_state	""
		set field_length	[string length $raw_field_value]
		for {set i 0} {$i < $field_length} {incr i} {
			set c	[string index $raw_field_value $i]
			switch -- $state {
				"plain" { #<<<
					switch -- $c {
						"\"" {
							set state	"qstring"
						}

						"\\" {
							set last_state	$state
							set state		"backquote"
						}

						";" {
							if {$build ne ""} {
								# RFC says empty list elements don't count
								lappend valuelist	$build
								set build	""
							}
						}

						default {
							append build	$c
						}
					}
					#>>>
				}
				"backquote" { #<<<
					append build	$c
					set state		$last_state
					#>>>
				}
				"qstring" { #<<<
					switch -- $c {
						"\"" {
							set state	"plain"
						}

						"\\" {
							set last_state	$state
							set state	"backquote"
						}

						default {
							append build	$c
						}
					}
					#>>>
				}
				default { #<<<
					error "Bogus parse state: ($state)"
					#>>>
				}
			}
		}
		if {$build ne ""} {
			lappend valuelist	$build
		}

		# TODO: figure out how reserved char quoting works in mime parameters
		set param_terms	[lassign $valuelist field_value]
		set field_params	[dict create]
		foreach param_term $param_terms {
			set idx	[string first "=" $param_term]
			if {$idx == -1} {
				my log warning "malformed parameter in term \"$param_term\": \"=\" not found"
				continue
			}
			dict set field_params \
					[string tolower [string trim [string range $param_term 0 $idx-1]]] \
					[string trim [string range $param_term $idx+1 end]]
		}

		list $field_value $field_params
	}

	#>>>
	method log {lvl {msg ""} args} { #<<<
		puts stderr $msg
	}

	unexport log
	#>>>
}


